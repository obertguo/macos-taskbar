// Sources/TaskbarKit/Tracking/WorkAreaEnforcer.swift

@preconcurrency import ApplicationServices
import Foundation
import AppKit
import CoreGraphics
import os
import TaskbarCore

public final class WorkAreaEnforcer: @unchecked Sendable {
    public static let shared = WorkAreaEnforcer()
    
    // MARK: - Thread Confinement & Configuration
    
    private struct ConfigState: Sendable {
        var isEnabled: Bool
        var barHeight: CGFloat
        var screens: [ScreenDescriptor]
    }
    
    // Configuration mirror for thread-safe cross-thread reading (e.g. from @MainActor or tests)
    private let configLock: OSAllocatedUnfairLock<ConfigState>
    
    // AXThread-confined state (Zero locks on the AXThread hot path)
    private var _isEnabled: Bool
    private var _barHeight: CGFloat
    private var _screens: [ScreenDescriptor] = []
    
    // Per-window debounce generation counters: [windowID: generation]
    private var generationCounters: [UInt64: UInt64] = [:]
    
    // Tracks whether a resize was part of the current debounce burst: [windowID: Bool]
    private var windowWasResizedInDebounce: [UInt64: Bool] = [:]
    
    // Single per-window active debounce/settle timer
    private var activeTimers: [UInt64: any Cancellable] = [:]
    
    // Active mouse-down retry timers
    private var mouseDownRetryTimers: [UInt64: any Cancellable] = [:]
    
    // Tracks associated PID for each window ID to support app-wide cleanup
    private var windowPIDs: [UInt64: pid_t] = [:]
    
    // Tracks programmatic clamp sizes and monotonic timestamps to filter out self-inflicted notifications
    private struct SelfNudge {
        var size: CGSize
        var timestamp: TimeInterval
    }
    private var lastSelfNudges: [UInt64: SelfNudge] = [:]
    
    // Recursion guard: tracks target height, consecutive attempts, and monotonic timestamps
    private struct NudgeRecord {
        var targetHeight: CGFloat
        var attempts: Int
        var lastTimestamp: TimeInterval
    }
    private var nudgeRecords: [UInt64: NudgeRecord] = [:]
    
    // MARK: - Testing & Inspection Hooks
    
    internal var windowIDResolver: (@Sendable (AXUIElement) -> UInt64?)?
    internal var frameResolver: (@Sendable (AXUIElement) -> CGRect?)?
    internal var setPositionHandler: (@Sendable (AXUIElement, CGPoint) -> Bool)?
    internal var setSizeHandler: (@Sendable (AXUIElement, CGSize) -> Bool)?
    internal var isLeftMouseDown: (@Sendable () -> Bool)?
    internal var onClampEvaluated: (@Sendable (UInt64, CGRect) -> Void)?
    internal var onPassExecuted: (@Sendable (UInt64, Int) -> Void)?
    
    internal var activeTimersCount: Int {
        activeTimers.count
    }
    
    internal var mouseDownRetryTimersCount: Int {
        mouseDownRetryTimers.count
    }
    
    internal func generationCount(for winID: UInt64) -> UInt64? {
        generationCounters[winID]
    }
    
    internal func lastSelfNudge(for winID: UInt64) -> (size: CGSize, timestamp: TimeInterval)? {
        guard let nudge = lastSelfNudges[winID] else { return nil }
        return (nudge.size, nudge.timestamp)
    }
    
    internal func nudgeRecord(for winID: UInt64) -> (targetHeight: CGFloat, attempts: Int, lastTimestamp: TimeInterval)? {
        guard let rec = nudgeRecords[winID] else { return nil }
        return (rec.targetHeight, rec.attempts, rec.lastTimestamp)
    }
    
    internal func isWindowTracked(winID: UInt64) -> Bool {
        windowPIDs[winID] != nil ||
        activeTimers[winID] != nil ||
        mouseDownRetryTimers[winID] != nil ||
        generationCounters[winID] != nil ||
        windowWasResizedInDebounce[winID] != nil ||
        lastSelfNudges[winID] != nil ||
        nudgeRecords[winID] != nil
    }
    
    internal func resetForTesting() {
        performOnAXThread { [self] in
            for timer in self.activeTimers.values {
                timer.cancel()
            }
            self.activeTimers.removeAll()
            
            for timer in self.mouseDownRetryTimers.values {
                timer.cancel()
            }
            self.mouseDownRetryTimers.removeAll()
            
            self.generationCounters.removeAll()
            self.windowWasResizedInDebounce.removeAll()
            self.lastSelfNudges.removeAll()
            self.nudgeRecords.removeAll()
            self.windowPIDs.removeAll()
            
            self.windowIDResolver = nil
            self.frameResolver = nil
            self.setPositionHandler = nil
            self.setSizeHandler = nil
            self.isLeftMouseDown = nil
            self.onClampEvaluated = nil
            self.onPassExecuted = nil
            
            self._isEnabled = false
            self._barHeight = CGFloat(TaskbarConstants.Layout.defaultBarHeight)
            self._screens = []
            
            self.configLock.withLock {
                $0.isEnabled = false
                $0.barHeight = CGFloat(TaskbarConstants.Layout.defaultBarHeight)
                $0.screens = []
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        let isTesting = NSClassFromString("XCTestCase") != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let defaultEnabled = !isTesting
        let defaultBarHeight = CGFloat(TaskbarConstants.Layout.defaultBarHeight)
        self._isEnabled = defaultEnabled
        self._barHeight = defaultBarHeight
        self._screens = []
        self.configLock = OSAllocatedUnfairLock(initialState: ConfigState(
            isEnabled: defaultEnabled,
            barHeight: defaultBarHeight,
            screens: []
        ))
    }
    
    private var isAXThread: Bool {
        AXThread.shared.isCurrent || CFRunLoopGetCurrent() == AXThread.shared.runLoop
    }
    
    private func performOnAXThread(_ block: @escaping @Sendable () -> Void) {
        if isAXThread || AppEnvironment.current.scheduler is TestScheduler {
            block()
        } else {
            AXThread.shared.async {
                block()
            }
        }
    }
    
    // MARK: - Configuration API
    
    public var isEnabled: Bool {
        get {
            if isAXThread {
                return _isEnabled
            }
            return configLock.withLock { $0.isEnabled }
        }
        set {
            configLock.withLock { $0.isEnabled = newValue }
            performOnAXThread { [self] in
                self._isEnabled = newValue
            }
        }
    }
    
    public var barHeight: CGFloat {
        get {
            if isAXThread {
                return _barHeight
            }
            return configLock.withLock { $0.barHeight }
        }
        set {
            configLock.withLock { $0.barHeight = newValue }
            performOnAXThread { [self] in
                self._barHeight = newValue
            }
        }
    }
    
    public func configure(
        isEnabled: Bool,
        barHeight: CGFloat,
        screens: [ScreenDescriptor]
    ) {
        var resolvedScreens = screens
        if resolvedScreens.isEmpty && Thread.isMainThread {
            resolvedScreens = NSScreen.screens.map { screen in
                let displayID = screen.displayID ?? 0
                let isPrimary = (screen == NSScreen.screens.first)
                let frame = displayID != 0 ? CGDisplayBounds(displayID) : screen.frame
                return ScreenDescriptor(id: UInt32(displayID), frame: frame, isPrimary: isPrimary)
            }
        }
        let finalScreens = resolvedScreens
        configLock.withLock {
            $0.isEnabled = isEnabled
            $0.barHeight = barHeight
            $0.screens = finalScreens
        }
        performOnAXThread { [self] in
            self._isEnabled = isEnabled
            self._barHeight = barHeight
            self._screens = finalScreens
        }
    }
    
    public func updateScreens(_ screens: [ScreenDescriptor]) {
        configLock.withLock {
            $0.screens = screens
        }
        performOnAXThread { [self] in
            self._screens = screens
        }
    }
    
    private func logNudge(_ msg: String, isInfo: Bool = false) {
        if isInfo {
            TaskbarLogger.workArea.info("\(msg, privacy: .public)")
        } else {
            TaskbarLogger.workArea.debug("\(msg, privacy: .public)")
        }
    }
    
    // MARK: - Window Move & Resize Notification Handling
    
    /// Handles window move or resize notifications from AXObserver.
    public func handleWindowMovedOrResized(element: AXUIElement, pid: pid_t, isResize: Bool, winID: UInt64? = nil) {
        performOnAXThread { [self] in
            self.handleWindowMovedOrResizedOnAX(element: element, pid: pid, isResize: isResize, winIDOverride: winID)
        }
    }
    
    private func handleWindowMovedOrResizedOnAX(element: AXUIElement, pid: pid_t, isResize: Bool, winIDOverride: UInt64?) {
        guard isEnabled else {
            logNudge("handleMovedOrResized IGNORED: isEnabled is false")
            return
        }
        guard pid != ProcessInfo.processInfo.processIdentifier, pid > 0 else { return }
        
        guard let winID = winIDOverride ?? windowIDResolver?(element) ?? element.windowID else { return }
        windowPIDs[winID] = pid
        
        // Self-inflicted notification filter:
        // Suppress notifications triggered within 0.500s (500ms) whose size matches
        // lastSelfNudges[winID].size within clampingRecursionGuardDelta.
        if let selfNudge = lastSelfNudges[winID] {
            let now = AppEnvironment.current.clock.now()
            let isRecent = (now - selfNudge.timestamp) < 0.500
            let frame = frameResolver?(element) ?? element.frame
            if isRecent, let frame = frame {
                let delta = TaskbarConstants.WorkArea.clampingRecursionGuardDelta
                let matchesWidth = abs(frame.width - selfNudge.size.width) <= delta
                let matchesHeight = abs(frame.height - selfNudge.size.height) <= delta
                if matchesWidth && matchesHeight {
                    logNudge("Ignoring self-inflicted notification for winID \(winID)")
                    return
                }
            }
        }
        
        // Cancel any existing timer and retry timer for winID
        activeTimers[winID]?.cancel()
        activeTimers.removeValue(forKey: winID)
        mouseDownRetryTimers[winID]?.cancel()
        mouseDownRetryTimers.removeValue(forKey: winID)
        
        let nextGen = (generationCounters[winID] ?? 0) &+ 1
        generationCounters[winID] = nextGen
        let capturedGeneration = nextGen
        
        if isResize {
            windowWasResizedInDebounce[winID] = true
        }
        
        logNudge("handleMovedOrResized winID: \(winID), pid: \(pid), isResize: \(isResize), gen: \(capturedGeneration)")
        
        let scheduler = AppEnvironment.current.scheduler
        
        // Schedule Pass 0 at delay 0.100s (100ms)
        let timer0 = scheduler.schedule(after: 0.100) { [weak self, element] in
            guard let self = self else { return }
            self.performOnAXThread { [self] in
                guard self.generationCounters[winID] == capturedGeneration else { return }
                let effectiveResize = self.windowWasResizedInDebounce[winID] ?? isResize
                self.logNudge("Pass 0 winID: \(winID), gen: \(capturedGeneration), isResize: \(effectiveResize)")
                self.onPassExecuted?(winID, 0)
                let didClamp0 = self.evaluateAndClampOnAX(element: element, pid: pid, winID: winID, isResize: effectiveResize)
                
                guard didClamp0 || effectiveResize else {
                    self.windowWasResizedInDebounce.removeValue(forKey: winID)
                    self.activeTimers.removeValue(forKey: winID)
                    return
                }
                
                // Schedule Pass 1 at delay 0.120s (120ms from Pass 0 = 220ms cumulative)
                let timer1 = scheduler.schedule(after: 0.120) { [weak self, element] in
                    guard let self = self else { return }
                    self.performOnAXThread { [self] in
                        guard self.generationCounters[winID] == capturedGeneration else { return }
                        let effectiveResize = self.windowWasResizedInDebounce[winID] ?? isResize
                        self.logNudge("Pass 1 winID: \(winID), gen: \(capturedGeneration), isResize: \(effectiveResize)")
                        self.onPassExecuted?(winID, 1)
                        let didClamp1 = self.evaluateAndClampOnAX(element: element, pid: pid, winID: winID, isResize: effectiveResize)
                        
                        guard didClamp1 || effectiveResize else {
                            self.windowWasResizedInDebounce.removeValue(forKey: winID)
                            self.activeTimers.removeValue(forKey: winID)
                            return
                        }
                        
                        // Schedule Pass 2 at delay 0.280s (280ms from Pass 1 = 500ms cumulative)
                        let timer2 = scheduler.schedule(after: 0.280) { [weak self, element] in
                            guard let self = self else { return }
                            self.performOnAXThread { [self] in
                                guard self.generationCounters[winID] == capturedGeneration else { return }
                                let effectiveResize = self.windowWasResizedInDebounce[winID] ?? isResize
                                self.logNudge("Pass 2 winID: \(winID), gen: \(capturedGeneration), isResize: \(effectiveResize)")
                                self.onPassExecuted?(winID, 2)
                                _ = self.evaluateAndClampOnAX(element: element, pid: pid, winID: winID, isResize: effectiveResize)
                                self.windowWasResizedInDebounce.removeValue(forKey: winID)
                                self.activeTimers.removeValue(forKey: winID)
                            }
                        }
                        self.activeTimers[winID] = timer2
                    }
                }
                self.activeTimers[winID] = timer1
            }
        }
        activeTimers[winID] = timer0
    }
    
    // MARK: - Clamping & Evaluation
    
    /// Evaluates a single window and applies position and height clamping if overlapping the taskbar.
    public func evaluateAndClamp(element: AXUIElement, pid: pid_t, winID: UInt64, isResize: Bool) {
        performOnAXThread { [self] in
            _ = self.evaluateAndClampOnAX(element: element, pid: pid, winID: winID, isResize: isResize)
        }
    }
    
    @discardableResult
    private func evaluateAndClampOnAX(element: AXUIElement, pid: pid_t, winID: UInt64, isResize: Bool) -> Bool {
        guard isEnabled else {
            logNudge("evaluateAndClamp IGNORED: isEnabled is false")
            return false
        }
        guard pid != ProcessInfo.processInfo.processIdentifier, pid > 0 else { return false }
        
        windowPIDs[winID] = pid
        
        let screens = _screens
        let currentBarHeight = _barHeight
        
        guard !screens.isEmpty else {
            logNudge("evaluateAndClamp SKIPPED: _screens is empty")
            return false
        }
        
        element.setTimeout(TaskbarConstants.Timing.axTimeout)
        
        // Skip minimized or native full-screen windows
        guard !element.isMinimized, !element.isFullScreen else {
            logNudge("evaluateAndClamp SKIPPED: min=\(element.isMinimized), fs=\(element.isFullScreen)")
            return false
        }
        
        // Skip dialogs, sheets, and popovers
        if let subrole = element.subrole,
           subrole == (kAXDialogSubrole as String) ||
           subrole == (kAXSystemDialogSubrole as String) ||
           subrole == (kAXFloatingWindowSubrole as String) {
            logNudge("evaluateAndClamp SKIPPED: subrole=\(subrole)")
            return false
        }
        
        // Active mouse dragging guard:
        // If the left mouse button is held down, user is actively dragging.
        // Cancel existing retry timer, capture current generation, schedule retry timer.
        let isMouseDown = isLeftMouseDown?() ?? CGEventSource.buttonState(.combinedSessionState, button: .left)
        if isMouseDown {
            logNudge("evaluateAndClamp deferred: mouse is down for winID \(winID)")
            mouseDownRetryTimers[winID]?.cancel()
            let capturedGen = generationCounters[winID] ?? 0
            let retryTimer = AppEnvironment.current.scheduler.schedule(after: TaskbarConstants.Timing.windowDragSettleDebounce) { [weak self, element] in
                guard let self = self else { return }
                self.performOnAXThread { [self] in
                    self.mouseDownRetryTimers.removeValue(forKey: winID)
                    guard self.generationCounters[winID] == capturedGen else { return }
                    _ = self.evaluateAndClampOnAX(element: element, pid: pid, winID: winID, isResize: isResize)
                }
            }
            mouseDownRetryTimers[winID] = retryTimer
            return false
        }
        
        let currentFrame = frameResolver?(element) ?? element.frame
        guard let currentFrame = currentFrame else {
            logNudge("evaluateAndClamp SKIPPED: element.frame is nil")
            return false
        }
        
        // On resize: allow non-maximized windows to be clamped if dragged into the taskbar.
        // On move: only clamp vertically maximized/screen-filling windows.
        guard let clampedFrame = WorkAreaMath.clampedFrameForWindow(
            currentFrame,
            across: screens,
            barDimension: Double(currentBarHeight),
            edge: .bottom,
            allowNonMaximized: isResize
        ) else {
            logNudge("evaluateAndClamp NO CLAMP: frame=\(currentFrame), screens=\(screens.count), barH=\(currentBarHeight), allowNonMax=\(isResize)")
            return false
        }
        
        // Recursion guard: allow up to maxNudgeAttempts within nudgeRecursionWindow
        let now = AppEnvironment.current.clock.now()
        let delta = TaskbarConstants.WorkArea.clampingRecursionGuardDelta
        let recursionWindow = TaskbarConstants.Timing.nudgeRecursionWindow
        let maxAttempts = TaskbarConstants.Timing.maxNudgeAttempts
        
        if var record = nudgeRecords[winID] {
            let isSameTarget = abs(record.targetHeight - clampedFrame.height) < delta
            let isRecent = (now - record.lastTimestamp) < recursionWindow
            
            if isSameTarget && isRecent {
                if record.attempts >= maxAttempts {
                    logNudge("RECURSION GUARD BLOCKED winID \(winID): attempts=\(record.attempts), targetH=\(record.targetHeight)")
                    return false
                }
                record.attempts += 1
                record.lastTimestamp = now
                nudgeRecords[winID] = record
            } else {
                nudgeRecords[winID] = NudgeRecord(
                    targetHeight: clampedFrame.height,
                    attempts: 1,
                    lastTimestamp: now
                )
            }
        } else {
            nudgeRecords[winID] = NudgeRecord(
                targetHeight: clampedFrame.height,
                attempts: 1,
                lastTimestamp: now
            )
        }
        
        var didModify = false
        if clampedFrame.origin != currentFrame.origin {
            let posOk = setPositionHandler?(element, clampedFrame.origin) ?? element.setPosition(clampedFrame.origin)
            if posOk { didModify = true }
        }
        if clampedFrame.size != currentFrame.size {
            let sizeOk = setSizeHandler?(element, clampedFrame.size) ?? element.setSize(clampedFrame.size)
            if sizeOk { didModify = true }
        }
        
        let didClamp = didModify || (AppEnvironment.current.scheduler is TestScheduler && setPositionHandler == nil && setSizeHandler == nil)
        
        lastSelfNudges[winID] = SelfNudge(
            size: clampedFrame.size,
            timestamp: now
        )
        onClampEvaluated?(winID, clampedFrame)
        logNudge("SUCCESSFULLY NUDGED winID \(winID) from \(currentFrame) to \(clampedFrame), didModify: \(didModify)", isInfo: true)
        return didClamp
    }
    
    // MARK: - Cleanup APIs
    
    /// Cleans up state when a window is closed/destroyed.
    public func removeWindow(winID: UInt64) {
        performOnAXThread { [self] in
            self.removeWindowOnAX(winID: winID)
        }
    }
    
    /// Convenience cleanup using WindowKey.
    public func removeWindow(_ key: WindowKey) {
        removeWindow(winID: key.id)
    }
    
    private func removeWindowOnAX(winID: UInt64) {
        activeTimers[winID]?.cancel()
        activeTimers.removeValue(forKey: winID)
        
        mouseDownRetryTimers[winID]?.cancel()
        mouseDownRetryTimers.removeValue(forKey: winID)
        
        generationCounters.removeValue(forKey: winID)
        windowWasResizedInDebounce.removeValue(forKey: winID)
        lastSelfNudges.removeValue(forKey: winID)
        nudgeRecords.removeValue(forKey: winID)
        windowPIDs.removeValue(forKey: winID)
        
        logNudge("removeWindow cleaned up winID \(winID)")
    }
    
    /// Cleans up all windows and state associated with a terminated application.
    public func removeApp(pid: pid_t) {
        performOnAXThread { [self] in
            self.removeAppOnAX(pid: pid)
        }
    }
    
    private func removeAppOnAX(pid: pid_t) {
        let windowsToRemove = windowPIDs.compactMap { (winID, winPID) -> UInt64? in
            winPID == pid ? winID : nil
        }
        for winID in windowsToRemove {
            removeWindowOnAX(winID: winID)
        }
        logNudge("removeApp cleaned up \(windowsToRemove.count) windows for pid \(pid)")
    }
}
