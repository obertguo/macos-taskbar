// Sources/TaskbarApp/Tracking/WorkAreaEnforcer.swift

@preconcurrency import ApplicationServices
import Foundation
import CoreGraphics
import TaskbarCore

public final class WorkAreaEnforcer: @unchecked Sendable {
    public static let shared = WorkAreaEnforcer()
    
    private let lock = NSLock()
    private var _isEnabled: Bool = true
    private var _barHeight: CGFloat = 30.0
    private var _screens: [ScreenDescriptor] = []
    
    // Per-window debounce generation counters: [windowID: generation]
    private var generationCounters: [UInt64: UInt64] = [:]
    
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
        lock.unlock()
        
        // 150ms settle debounce: allows window manager animations (e.g. titlebar double-click zoom)
        // and mouse drag operations to coalesce before evaluating clamping
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.15) { [element] in
            AXThread.shared.async {
                let enforcer = WorkAreaEnforcer.shared
                let currentGen = enforcer.lock.withLock { enforcer.generationCounters[winID] }
                guard currentGen == generation else { return }
                enforcer.evaluateAndClamp(element: element, pid: pid, winID: winID, isResize: isResize)
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
        
        element.setTimeout(0.3)
        
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
        
        // Recursion guard: allow up to 2 attempts within 600ms to recover from
        // OS zoom animations that revert the frame upon completion.
        let shouldProceed: Bool = lock.withLock {
            if var record = nudgeRecords[winID] {
                let isSameTarget = abs(record.targetHeight - clampedFrame.height) < 1.0
                let isRecent = Date().timeIntervalSince(record.lastTimestamp) < 0.6
                
                if isSameTarget && isRecent {
                    if record.attempts >= 2 {
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
        
        // Follow-up settle verification (250ms):
        // AppKit's native zoom animation can take ~200ms to complete. If AppKit's completion
        // handler overwrites the frame with its full un-nudged bounds, this verification pass
        // ensures the window settles cleanly at the taskbar boundary.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.25) { [element] in
            AXThread.shared.async {
                let enforcer = WorkAreaEnforcer.shared
                guard enforcer.isEnabled else { return }
                guard !element.isMinimized, !element.isFullScreen else { return }
                guard let finalFrame = element.frame else { return }
                
                let (activeScreens, barH) = enforcer.lock.withLock { (enforcer._screens, enforcer._barHeight) }
                if let reClamped = WorkAreaMath.clampedFrameForWindow(
                    finalFrame,
                    across: activeScreens,
                    taskbarHeight: barH,
                    allowNonMaximized: false
                ) {
                    _ = element.setSize(reClamped.size)
                }
            }
        }
    }
    
    /// Cleans up state when a window is closed/destroyed.
    public func removeWindow(winID: UInt64) {
        lock.withLock {
            generationCounters.removeValue(forKey: winID)
            nudgeRecords.removeValue(forKey: winID)
        }
    }
}
