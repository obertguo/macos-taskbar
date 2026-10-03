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
    
    // Recursion guard: tracks the last attempted target height and timestamp
    private struct LastNudge {
        let height: CGFloat
        let timestamp: Date
    }
    private var lastNudges: [UInt64: LastNudge] = [:]
    
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
        
        // 100ms settle debounce: allows smooth dragging/resizing without fighting user input
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.1) { [element] in
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
        
        // Recursion guard: check if we already attempted this exact height recently
        if let prev = lock.withLock({ lastNudges[winID] }) {
            let isSameHeight = abs(prev.height - clampedFrame.height) < 1.0
            let isRecent = Date().timeIntervalSince(prev.timestamp) < 0.5
            if isSameHeight && isRecent {
                return
            }
        }
        
        // Check if size attribute is settable
        guard element.isSizeSettable else { return }
        
        lock.withLock {
            lastNudges[winID] = LastNudge(height: clampedFrame.height, timestamp: Date())
        }
        
        _ = element.setSize(clampedFrame.size)
    }
    
    /// Cleans up state when a window is closed/destroyed.
    public func removeWindow(winID: UInt64) {
        lock.withLock {
            generationCounters.removeValue(forKey: winID)
            lastNudges.removeValue(forKey: winID)
        }
    }
}
