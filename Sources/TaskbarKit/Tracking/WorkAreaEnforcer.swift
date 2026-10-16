// Sources/TaskbarKit/Tracking/WorkAreaEnforcer.swift

@preconcurrency import ApplicationServices
import Foundation
import AppKit
import CoreGraphics
import TaskbarCore

public final class WorkAreaEnforcer: @unchecked Sendable {
    public static let shared = WorkAreaEnforcer()
    
    private let lock = NSLock()
    private var _isEnabled: Bool = NSClassFromString("XCTestCase") == nil
    private var _barHeight: CGFloat = CGFloat(TaskbarConstants.Layout.defaultBarHeight)
    private var _screens: [ScreenDescriptor] = []
    
    // Per-window debounce generation counters: [windowID: generation]
    private var generationCounters: [UInt64: UInt64] = [:]
    
    // Tracks whether a resize was part of the current debounce burst
    private var windowWasResizedInDebounce: [UInt64: Bool] = [:]
    
    // Tracks programmatic clamp sizes and timestamps to filter out self-inflicted notifications
    private struct SelfNudge {
        var size: CGSize
        var timestamp: Date
    }
    private var lastSelfNudges: [UInt64: SelfNudge] = [:]
    
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
    
    private func logNudge(_ msg: String) {
        TaskbarLogger.workArea.info("\(msg, privacy: .public)")
    }
    
    public func updateScreens(_ screens: [ScreenDescriptor]) {
        lock.withLock {
            self._screens = screens
        }
    }
    
    /// Handles window move or resize notifications from AXObserver.
    public func handleWindowMovedOrResized(element: AXUIElement, pid: pid_t, isResize: Bool) {
        guard isEnabled else {
            logNudge("handleMovedOrResized IGNORED: isEnabled is false")
            return
        }
        guard pid != ProcessInfo.processInfo.processIdentifier, pid > 0 else { return }
        
        guard let winID = element.windowID else { return }
        
        // Self-inflicted notification filter:
        // If this notification was triggered by our own setSize within the last 350ms,
        // ignore it so that we don't invalidate the settle verification passes (Pass 2/3)
        // or re-trigger redundant debounce cycles.
        let isSelfNudge: Bool = lock.withLock {
            if let selfNudge = lastSelfNudges[winID] {
                let isRecent = Date().timeIntervalSince(selfNudge.timestamp) < 0.35
                if isRecent, let frame = element.frame {
                    let matchesWidth = abs(frame.width - selfNudge.size.width) < TaskbarConstants.WorkArea.clampingRecursionGuardDelta
                    let matchesHeight = abs(frame.height - selfNudge.size.height) < TaskbarConstants.WorkArea.clampingRecursionGuardDelta
                    if matchesWidth && matchesHeight {
                        return true
                    }
                }
            }
            return false
        }
        if isSelfNudge {
            logNudge("Ignoring self-inflicted notification for winID \(winID)")
            return
        }
        
        let generation: UInt64
        
        lock.lock()
        // If an active resize debounce burst is currently in-flight for this window, do not allow
        // a passive move or window reconcile to cancel or push out the resize settle passes.
        if !isResize, windowWasResizedInDebounce[winID] == true {
            lock.unlock()
            logNudge("handleMovedOrResized ignoring passive move/reconcile while resize debounce in-flight for winID \(winID)")
            return
        }
        
        let nextGen = (generationCounters[winID] ?? 0) &+ 1
        generationCounters[winID] = nextGen
        generation = nextGen
        if isResize {
            windowWasResizedInDebounce[winID] = true
        }
        lock.unlock()
        
        logNudge("handleMovedOrResized winID: \(winID), pid: \(pid), isResize: \(isResize), gen: \(generation)")
        
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
                enforcer.logNudge("Pass 1 winID: \(winID), gen: \(generation), isCurrent: \(isCurrent), wasResized: \(wasResized)")
                guard isCurrent else { return }
                enforcer.evaluateAndClamp(element: element, pid: pid, winID: winID, isResize: wasResized || isResize)
            }
        }
        
        // Pass 2: Settle verification pass ensures window manager animations (e.g. titlebar zoom,
        // snap-to-edge, or window tiling) that take ~250-300ms to complete are evaluated once settled,
        // recovering from any mid-animation frame checks or AppKit completion resets.
        let pass2Delay = TaskbarConstants.Timing.windowDragSettleDebounce + TaskbarConstants.Timing.windowZoomAnimationSettleDelay
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + pass2Delay) { [element] in
            AXThread.shared.async {
                let enforcer = WorkAreaEnforcer.shared
                let (isCurrent, wasResized) = enforcer.lock.withLock { () -> (Bool, Bool) in
                    guard enforcer.generationCounters[winID] == generation else {
                        return (false, false)
                    }
                    let wasResized = enforcer.windowWasResizedInDebounce[winID] ?? false
                    return (true, wasResized)
                }
                enforcer.logNudge("Pass 2 winID: \(winID), gen: \(generation), isCurrent: \(isCurrent), wasResized: \(wasResized)")
                guard isCurrent else { return }
                enforcer.evaluateAndClamp(element: element, pid: pid, winID: winID, isResize: wasResized || isResize)
            }
        }
        
        // Pass 3: Extended animation settle pass (650ms) handles sluggish Chromium/Electron window
        // transitions or slower system animations that settle beyond 400ms.
        let pass3Delay = pass2Delay + 0.25
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + pass3Delay) { [element] in
            AXThread.shared.async {
                let enforcer = WorkAreaEnforcer.shared
                let (isCurrent, wasResized) = enforcer.lock.withLock { () -> (Bool, Bool) in
                    guard enforcer.generationCounters[winID] == generation else {
                        return (false, false)
                    }
                    let wasResized = enforcer.windowWasResizedInDebounce.removeValue(forKey: winID) ?? false
                    return (true, wasResized)
                }
                enforcer.logNudge("Pass 3 winID: \(winID), gen: \(generation), isCurrent: \(isCurrent), wasResized: \(wasResized)")
                guard isCurrent else { return }
                enforcer.evaluateAndClamp(element: element, pid: pid, winID: winID, isResize: wasResized || isResize)
            }
        }
    }
    
    /// Evaluates a single window and applies height clamping if overlapping the taskbar.
    public func evaluateAndClamp(element: AXUIElement, pid: pid_t, winID: UInt64, isResize: Bool) {
        guard isEnabled else {
            logNudge("evaluateAndClamp IGNORED: isEnabled is false")
            return
        }
        guard pid != ProcessInfo.processInfo.processIdentifier, pid > 0 else { return }
        
        var screens: [ScreenDescriptor]
        let currentBarHeight: CGFloat
        
        do {
            lock.lock()
            screens = _screens
            currentBarHeight = _barHeight
            lock.unlock()
        }
        
        if screens.isEmpty {
            screens = NSScreen.screens.map { screen in
                let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
                let isPrimary = (screen == NSScreen.screens.first)
                let frame = displayID != 0 ? CGDisplayBounds(displayID) : screen.frame
                return ScreenDescriptor(id: UInt32(displayID), frame: frame, isPrimary: isPrimary)
            }
        }
        
        element.setTimeout(TaskbarConstants.Timing.axTimeout)
        
        // Skip minimized or native full-screen windows
        guard !element.isMinimized, !element.isFullScreen else {
            logNudge("evaluateAndClamp SKIPPED: min=\(element.isMinimized), fs=\(element.isFullScreen)")
            return
        }
        
        // Skip dialogs, sheets, and popovers
        if let subrole = element.subrole,
           subrole == (kAXDialogSubrole as String) ||
           subrole == (kAXSystemDialogSubrole as String) ||
           subrole == (kAXFloatingWindowSubrole as String) {
            logNudge("evaluateAndClamp SKIPPED: subrole=\(subrole)")
            return
        }
        
        // Active mouse dragging guard:
        // If the left mouse button is currently held down, the user is actively dragging the window.
        // Defer clamping until mouse release to avoid fighting WindowServer and burning attempt limits.
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            logNudge("evaluateAndClamp deferred: mouse is down for winID \(winID)")
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + TaskbarConstants.Timing.windowDragSettleDebounce) { [element] in
                AXThread.shared.async {
                    WorkAreaEnforcer.shared.evaluateAndClamp(element: element, pid: pid, winID: winID, isResize: isResize)
                }
            }
            return
        }
        
        guard let currentFrame = element.frame else {
            logNudge("evaluateAndClamp SKIPPED: element.frame is nil")
            return
        }
        
        // On resize: allow non-maximized windows to be clamped if dragged into the taskbar.
        // On move: only clamp vertically maximized/screen-filling windows.
        guard let clampedFrame = WorkAreaMath.clampedFrameForWindow(
            currentFrame,
            across: screens,
            taskbarHeight: currentBarHeight,
            allowNonMaximized: isResize
        ) else {
            logNudge("evaluateAndClamp NO CLAMP: frame=\(currentFrame), screens=\(screens.count), barH=\(currentBarHeight), allowNonMax=\(isResize)")
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
                        logNudge("RECURSION GUARD BLOCKED winID \(winID): attempts=\(record.attempts), targetH=\(record.targetHeight)")
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
        guard element.isSizeSettable else {
            logNudge("evaluateAndClamp SKIPPED: isSizeSettable is false")
            return
        }
        
        let setResult = element.setSize(clampedFrame.size)
        if setResult {
            lock.withLock {
                lastSelfNudges[winID] = SelfNudge(size: clampedFrame.size, timestamp: Date())
            }
        }
        logNudge("SUCCESSFULLY NUDGED winID \(winID) from \(currentFrame) to \(clampedFrame), setResult: \(setResult)")
    }
    
    /// Cleans up state when a window is closed/destroyed.
    public func removeWindow(winID: UInt64) {
        lock.withLock {
            generationCounters.removeValue(forKey: winID)
            windowWasResizedInDebounce.removeValue(forKey: winID)
            nudgeRecords.removeValue(forKey: winID)
            lastSelfNudges.removeValue(forKey: winID)
        }
    }
}
