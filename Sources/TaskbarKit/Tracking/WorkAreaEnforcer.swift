// Sources/TaskbarApp/Tracking/WorkAreaEnforcer.swift

@preconcurrency import ApplicationServices
import Foundation
import CoreGraphics
import TaskbarCore

public final class WorkAreaEnforcer: @unchecked Sendable {
    public static let shared = WorkAreaEnforcer()
    
    private let lock = NSLock()
    private var _isEnabled: Bool = true
    private var _barHeight: CGFloat = CGFloat(TaskbarConstants.Layout.defaultBarHeight)
    private var _screens: [ScreenDescriptor] = []
    
    // Per-window debounce generation counters: [windowID: generation]
    private var generationCounters: [UInt64: UInt64] = [:]
    
    // Tracks whether a resize was part of the current debounce burst
    private var windowWasResizedInDebounce: [UInt64: Bool] = [:]
    
    // Recursion guard: tracks target height, consecutive attempts, and timestamps
    private struct NudgeRecord {
        var targetHeight: CGFloat
        var attempts: Int
        var lastTimestamp: Date
    }
    private var nudgeRecords: [UInt64: NudgeRecord] = [:]
    
    public var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }
    
    public var barHeight: CGFloat {
        get { lock.withLock { _barHeight } }
        set { lock.withLock { _barHeight = newValue } }
    }
    
    public func configure(
        isEnabled: Bool,
        barHeight: CGFloat,
        screens: [ScreenDescriptor]
    ) {
        lock.withLock {
            self._isEnabled = isEnabled
            self._barHeight = barHeight
            self._screens = screens
        }
    }
    
    public func updateScreens(_ screens: [ScreenDescriptor]) {
        lock.withLock {
            self._screens = screens
        }
    }
    
    /// Handles window move or resize notifications from AXObserver.
    public func handleWindowMovedOrResized(element: AXUIElement, pid: pid_t, isResize: Bool) {
        guard isEnabled else { return }
        guard pid != ProcessInfo.processInfo.processIdentifier, pid > 0 else { return }
        
        let winID = element.windowID
        let generation: UInt64
        
        lock.lock()
        let nextGen = (generationCounters[winID] ?? 0) &+ 1
        generationCounters[winID] = nextGen
        generation = nextGen
        if isResize {
            windowWasResizedInDebounce[winID] = true
        }
        lock.unlock()
        
        // Pass 1: Quick settle debounce allows fast mouse dragging/resizing to coalesce
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + TaskbarConstants.Timing.windowDragSettleDebounce) { [element] in
            AXThread.shared.async {
                let enforcer = WorkAreaEnforcer.shared
                let (isCurrent, wasResized) = enforcer.lock.withLock { () -> (Bool, Bool) in
                    guard enforcer.generationCounters[winID] == generation else {
                        return (false, false)
                    }
                    let wasResized = enforcer.windowWasResizedInDebounce[winID] ?? false
                    return (true, wasResized)
                }
                guard isCurrent else { return }
                enforcer.evaluateAndClamp(element: element, pid: pid, winID: winID, isResize: wasResized || isResize)
            }
        }
        
        // Pass 2: Settle verification pass ensures window manager animations (e.g. titlebar zoom,
        // snap-to-edge, or window tiling) that take ~250-300ms to complete are evaluated once settled,
        // recovering from any mid-animation frame checks or AppKit completion resets.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + TaskbarConstants.Timing.windowDragSettleDebounce + TaskbarConstants.Timing.windowZoomAnimationSettleDelay) { [element] in
            AXThread.shared.async {
                let enforcer = WorkAreaEnforcer.shared
                let (isCurrent, wasResized) = enforcer.lock.withLock { () -> (Bool, Bool) in
                    guard enforcer.generationCounters[winID] == generation else {
                        return (false, false)
                    }
                    let wasResized = enforcer.windowWasResizedInDebounce.removeValue(forKey: winID) ?? false
                    return (true, wasResized)
                }
                guard isCurrent else { return }
                enforcer.evaluateAndClamp(element: element, pid: pid, winID: winID, isResize: wasResized || isResize)
            }
        }
    }
    
    /// Evaluates a single window and applies height clamping if overlapping the taskbar.
    public func evaluateAndClamp(element: AXUIElement, pid: pid_t, winID: UInt64, isResize: Bool) {
        guard isEnabled else { return }
        guard pid != ProcessInfo.processInfo.processIdentifier, pid > 0 else { return }
        
        let screens: [ScreenDescriptor]
        let currentBarHeight: CGFloat
        
        do {
            lock.lock()
            screens = _screens
            currentBarHeight = _barHeight
            lock.unlock()
        }
        
        element.setTimeout(TaskbarConstants.Timing.axTimeout)
        
        // Skip minimized or native full-screen windows
        guard !element.isMinimized, !element.isFullScreen else { return }
        
        // Skip dialogs, sheets, and popovers
        if let subrole = element.subrole,
           subrole == (kAXDialogSubrole as String) ||
           subrole == (kAXSystemDialogSubrole as String) ||
           subrole == (kAXFloatingWindowSubrole as String) {
            return
        }
        
        guard let currentFrame = element.frame else { return }
        
        // On resize: allow non-maximized windows to be clamped if dragged into the taskbar.
        // On move: only clamp vertically maximized/screen-filling windows.
        guard let clampedFrame = WorkAreaMath.clampedFrameForWindow(
            currentFrame,
            across: screens,
            taskbarHeight: currentBarHeight,
            allowNonMaximized: isResize
        ) else {
            return
        }
        
        // Recursion guard: allow up to maxNudgeAttempts within nudgeRecursionWindow to recover from
        // OS zoom animations that revert the frame upon completion.
        let shouldProceed: Bool = lock.withLock {
            if var record = nudgeRecords[winID] {
                let isSameTarget = abs(record.targetHeight - clampedFrame.height) < TaskbarConstants.WorkArea.clampingRecursionGuardDelta
                let isRecent = Date().timeIntervalSince(record.lastTimestamp) < TaskbarConstants.Timing.nudgeRecursionWindow
                
                if isSameTarget && isRecent {
                    if record.attempts >= TaskbarConstants.Timing.maxNudgeAttempts {
                        // Max attempts reached; break infinite feedback loop
                        return false
                    }
                    record.attempts += 1
                    record.lastTimestamp = Date()
                    nudgeRecords[winID] = record
                    return true
                }
            }
            nudgeRecords[winID] = NudgeRecord(
                targetHeight: clampedFrame.height,
                attempts: 1,
                lastTimestamp: Date()
            )
            return true
        }
        
        guard shouldProceed else { return }
        guard element.isSizeSettable else { return }
        
        _ = element.setSize(clampedFrame.size)
    }
    
    /// Cleans up state when a window is closed/destroyed.
    public func removeWindow(winID: UInt64) {
        lock.withLock {
            generationCounters.removeValue(forKey: winID)
            windowWasResizedInDebounce.removeValue(forKey: winID)
            nudgeRecords.removeValue(forKey: winID)
        }
    }
}
