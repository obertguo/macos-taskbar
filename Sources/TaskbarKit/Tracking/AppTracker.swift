// Sources/TaskbarKit/Tracking/AppTracker.swift

import AppKit
import ApplicationServices
import TaskbarCore

@MainActor
public final class AppTracker: WindowSource {
    public let store: WindowStore
    public var onWindowsChanged: (() -> Void)?
    
    // MARK: - $O(1)$ WindowKey -> AXUIElement Cache
    
    nonisolated private static let elementCacheLock = NSLock()
    nonisolated(unsafe) private static var elementCache: [WindowKey: AXUIElement] = [:]
    
    nonisolated public static func elementForWindowKey(_ key: WindowKey) -> AXUIElement? {
        elementCacheLock.withLock {
            elementCache[key]
        }
    }
    
    nonisolated public static func cacheElement(_ element: AXUIElement, for key: WindowKey) {
        elementCacheLock.withLock {
            elementCache[key] = element
        }
    }
    
    nonisolated public static func removeElement(for key: WindowKey) {
        elementCacheLock.withLock {
            _ = elementCache.removeValue(forKey: key)
        }
    }
    
    nonisolated public static func removeAllElements(forPID pid: pid_t) {
        elementCacheLock.withLock {
            elementCache = elementCache.filter { $0.key.pid != pid }
        }
    }
    
    nonisolated public static func clearElementCache() {
        elementCacheLock.withLock {
            elementCache.removeAll()
        }
    }
    
    // MARK: - Per-PID Circuit Breaker (M-04)
    
    nonisolated private static let backoffLock = NSLock()
    nonisolated(unsafe) private static var backoffUntilByPID: [pid_t: TimeInterval] = [:]
    
    nonisolated public static func isPIDBackedOff(_ pid: pid_t) -> Bool {
        backoffLock.withLock {
            guard let until = backoffUntilByPID[pid] else { return false }
            let now = AppEnvironment.current.clock.now()
            if now < until {
                return true
            } else {
                backoffUntilByPID.removeValue(forKey: pid)
                return false
            }
        }
    }
    
    nonisolated public static func recordTimeout(for pid: pid_t) {
        let now = AppEnvironment.current.clock.now()
        setPIDBackedOff(pid, until: now + 5.0)
    }
    
    nonisolated public static func setPIDBackedOff(_ pid: pid_t, until: TimeInterval) {
        backoffLock.withLock {
            backoffUntilByPID[pid] = until
        }
    }
    
    nonisolated public static func clearBackoff(for pid: pid_t) {
        backoffLock.withLock {
            _ = backoffUntilByPID.removeValue(forKey: pid)
        }
    }
    
    nonisolated public static func clearAllBackoffs() {
        backoffLock.withLock {
            backoffUntilByPID.removeAll()
        }
    }
    
    // MARK: - Instance State
    
    nonisolated(unsafe) private var observers: [pid_t: AXAppObserver] = [:]
    nonisolated(unsafe) private var pendingPIDs: Set<pid_t> = []
    
    private let dirtyPIDsLock = NSLock()
    nonisolated(unsafe) private var dirtyPIDs: Set<pid_t> = []
    
    private let sweepGenerationLock = NSLock()
    nonisolated(unsafe) private var _currentSweepGeneration: UInt64 = 0
    nonisolated private var currentSweepGeneration: UInt64 {
        get {
            sweepGenerationLock.withLock { _currentSweepGeneration }
        }
        set {
            sweepGenerationLock.withLock { _currentSweepGeneration = newValue }
        }
    }
    private var pendingDirtyDebounceWorkItem: DispatchWorkItem?
    private var pendingFullDebounceWorkItem: DispatchWorkItem?
    private var spaceSettleWorkItem: DispatchWorkItem?
    private var permissionPollTask: Task<Void, Never>?
    nonisolated(unsafe) private var knownWindowKeys: Set<WindowKey> = []
    
    public init(store: WindowStore) {
        self.store = store
        setupWorkspaceNotifications()
        startTrackingAllRunningApps()
    }
    
    private func setupWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        
        center.addObserver(self, selector: #selector(handleAppLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppHidden(_:)), name: NSWorkspace.didHideApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppUnhidden(_:)), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(handleActiveSpaceChanged(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAccessibilityApiChanged(_:)),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
    }
    
    public func startTracking() {
        startTrackingAllRunningApps()
    }
    
    public func startTrackingAllRunningApps() {
        guard AccessibilityPermission.isGranted() else {
            schedulePermissionCheck()
            return
        }
        stopPermissionCheck()
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in runningApps {
            trackApp(app.processIdentifier)
        }
        
        scheduleFullSweep(delay: 0.0)
    }
    
    private func schedulePermissionCheck() {
        guard permissionPollTask == nil else { return }
        permissionPollTask = Task { @MainActor [weak self] in
            for attempt in 1...60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self = self else { return }
                if AccessibilityPermission.isGranted() {
                    TaskbarLogger.lifecycle.info("Accessibility permission granted on poll attempt \(attempt). Initializing app tracking.")
                    self.stopPermissionCheck()
                    self.startTrackingAllRunningApps()
                    return
                }
            }
            guard !Task.isCancelled, let self = self else { return }
            TaskbarLogger.lifecycle.info("Accessibility permission polling timed out after 60 attempts.")
            self.stopPermissionCheck()
        }
    }
    
    private func stopPermissionCheck() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
    }
    
    private func trackApp(_ pid: pid_t) {
        AXThread.shared.async { [weak self] in
            guard let self = self else { return }
            guard self.observers[pid] == nil, !self.pendingPIDs.contains(pid) else { return }
            self.pendingPIDs.insert(pid)
            
            let observer = AXAppObserver(pid: pid) { [weak self] event in
                self?.handleNotificationEvent(event)
            }
            self.pendingPIDs.remove(pid)
            if let obs = observer {
                self.observers[pid] = obs
            }
        }
    }
    
    private func untrackApp(_ pid: pid_t) {
        AppTracker.removeAllElements(forPID: pid)
        AppTracker.clearBackoff(for: pid)
        dirtyPIDsLock.withLock {
            _ = dirtyPIDs.remove(pid)
        }
        WorkAreaEnforcer.shared.removeApp(pid: pid)
        AXThread.shared.async { [weak self] in
            guard let self = self else { return }
            self.knownWindowKeys = self.knownWindowKeys.filter { $0.pid != pid }
            self.pendingPIDs.remove(pid)
            if let observer = self.observers.removeValue(forKey: pid) {
                observer.invalidate()
            }
        }
        store.removeWindows(forPID: pid)
        onWindowsChanged?()
    }
    
    // MARK: - Workspace Notifications
    
    @objc private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        trackApp(app.processIdentifier)
        markPIDDirty(app.processIdentifier)
        scheduleDirtyReconcile(delay: TaskbarConstants.Timing.appLifecycleDebounce)
    }
    
    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        IconCache.shared.evict(bundleID: app.bundleIdentifier ?? "")
        IconCache.shared.evict(pid: app.processIdentifier)
        untrackApp(app.processIdentifier)
    }
    
    @objc private func handleAppActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        store.setFrontmostPID(pid)
        trackApp(pid)
        markPIDDirty(pid)
        scheduleDirtyReconcile(delay: TaskbarConstants.Timing.frameRenderDebounce)
    }
    
    @objc private func handleAppHidden(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        store.setAppHidden(pid: pid, isHidden: true)
        onWindowsChanged?()
    }
    
    @objc private func handleAppUnhidden(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        store.setAppHidden(pid: pid, isHidden: false)
        markPIDDirty(pid)
        scheduleDirtyReconcile(delay: TaskbarConstants.Timing.frameRenderDebounce)
    }
    
    @objc private func handleActiveSpaceChanged(_ notification: Notification) {
        scheduleFullSweep(delay: TaskbarConstants.Timing.spaceChangeInitialDebounce)
        spaceSettleWorkItem?.cancel()
        let settleItem = DispatchWorkItem { [weak self] in
            self?.performFullSweep()
        }
        spaceSettleWorkItem = settleItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TaskbarConstants.Timing.spaceChangeSettleDelay,
            execute: settleItem
        )
    }
    
    @objc private func handleAccessibilityApiChanged(_ notification: Notification) {
        if AccessibilityPermission.isGranted() {
            TaskbarLogger.lifecycle.info("Received com.apple.accessibility.api notification; permission granted. Initializing app tracking.")
            stopPermissionCheck()
            startTrackingAllRunningApps()
        }
    }
    
    // MARK: - 3-Tier Delta Router (M-02)
    
    nonisolated private func handleNotificationEvent(_ event: AXNotificationEvent) {
        let name = event.notification
        
        // Tier 1: Single-Window Delta
        if name == (kAXTitleChangedNotification as String) ||
           name == (kAXWindowMiniaturizedNotification as String) ||
           name == (kAXWindowDeminiaturizedNotification as String) ||
           name == (kAXWindowMovedNotification as String) ||
           name == (kAXWindowResizedNotification as String) {
            
            // If the app sent us an AX event, it is responsive; clear backoff
            if AppTracker.isPIDBackedOff(event.pid) {
                AppTracker.clearBackoff(for: event.pid)
            }
            
            if let winID = event.resolvedWindowID ?? event.element.windowID {
                let key = WindowKey(id: winID, pid: event.pid)
                AppTracker.cacheElement(event.element, for: key)
                
                let startTime = AppEnvironment.current.clock.now()
                event.element.setTimeout(TaskbarConstants.Timing.axTimeout)
                let batch = event.element.fetchWindowAttributesBatch()
                let elapsed = AppEnvironment.current.clock.now() - startTime
                if batch == nil && elapsed >= Double(TaskbarConstants.Timing.axTimeout) {
                    AppTracker.recordTimeout(for: event.pid)
                    return
                }
                
                let role: String?
                let subrole: String?
                let title: String
                let frame: CGRect
                let isMin: Bool
                let isMain: Bool
                let isFullScreen: Bool
                
                let app = NSRunningApplication(processIdentifier: event.pid)
                let appName = app?.localizedName ?? "App"
                let bundleID = app?.bundleIdentifier ?? ""
                let isAppHidden = app?.isHidden ?? false
                
                if let batch = batch {
                    role = batch.role
                    subrole = batch.subrole
                    title = batch.title ?? appName
                    frame = batch.frame ?? .zero
                    isMin = batch.isMinimized
                    isMain = batch.isMain
                    isFullScreen = batch.isFullScreen
                } else {
                    role = event.element.role
                    subrole = event.element.subrole
                    title = event.element.title ?? appName
                    frame = event.element.frame ?? .zero
                    isMin = event.element.isMinimized
                    isMain = event.element.isMain
                    isFullScreen = event.element.isFullScreen
                }
                
                if name == (kAXWindowMovedNotification as String) {
                    WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: event.element, pid: event.pid, isResize: false)
                } else if name == (kAXWindowResizedNotification as String) {
                    WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: event.element, pid: event.pid, isResize: true)
                }
                
                guard let role = role, WindowFilter.shouldInclude(
                    role: role,
                    subrole: subrole,
                    frame: frame,
                    bundleID: bundleID,
                    isAppRegular: true,
                    isMinimized: isMin
                ) else {
                    DispatchQueue.main.async { [weak self] in
                        self?.store.removeWindow(key: key)
                        self?.onWindowsChanged?()
                    }
                    return
                }
                
                let info = WindowInfo(
                    key: key,
                    pid: event.pid,
                    appName: appName,
                    bundleID: bundleID,
                    title: title,
                    frame: frame,
                    isMinimized: isMin,
                    isAppHidden: isAppHidden,
                    isMain: isMain,
                    isFullScreen: isFullScreen
                )
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let isMoveOrResize = (name == (kAXWindowMovedNotification as String) || name == (kAXWindowResizedNotification as String))
                    if isMoveOrResize {
                        let previous = self.store.window(forKey: key)
                        let screens = NSScreen.screens.map(\.screenDescriptor)
                        let oldDisplayID = previous.flatMap { ScreenAssignment.assignScreen(for: $0.frame, across: screens) }
                        let newDisplayID = ScreenAssignment.assignScreen(for: info.frame, across: screens)
                        let oldFullScreen = previous?.isFullScreen
                        self.store.addOrUpdateWindow(info)
                        if isMain && !isMin && event.pid == self.store.frontmostPID {
                            self.store.setFocusedWindow(key: key)
                        }
                        if oldDisplayID != newDisplayID || oldFullScreen != info.isFullScreen {
                            self.onWindowsChanged?()
                        }
                    } else {
                        self.store.addOrUpdateWindow(info)
                        if isMain && !isMin && event.pid == self.store.frontmostPID {
                            self.store.setFocusedWindow(key: key)
                        }
                        self.onWindowsChanged?()
                    }
                }
                return
            }
        }
        
        // Tier 2: Dirty-PID Reconcile
        if name == (kAXWindowCreatedNotification as String) ||
           name == (kAXUIElementDestroyedNotification as String) ||
           name == (kAXFocusedWindowChangedNotification as String) ||
           name == (kAXMainWindowChangedNotification as String) {
            
            if name == (kAXWindowCreatedNotification as String) {
                if let winID = event.resolvedWindowID ?? event.element.windowID {
                    let key = WindowKey(id: winID, pid: event.pid)
                    AppTracker.cacheElement(event.element, for: key)
                    let startTime = AppEnvironment.current.clock.now()
                    event.element.setTimeout(TaskbarConstants.Timing.axTimeout)
                    let batch = event.element.fetchWindowAttributesBatch()
                    let elapsed = AppEnvironment.current.clock.now() - startTime
                    if batch == nil && elapsed >= Double(TaskbarConstants.Timing.axTimeout) {
                        AppTracker.recordTimeout(for: event.pid)
                        return
                    }
                    
                    let app = NSRunningApplication(processIdentifier: event.pid)
                    let appName = app?.localizedName ?? "App"
                    let bundleID = app?.bundleIdentifier ?? ""
                    let isHidden = app?.isHidden ?? false
                    
                    let role: String?
                    let subrole: String?
                    let title: String
                    let frame: CGRect
                    let isMin: Bool
                    let isMain: Bool
                    let isFullScreen: Bool
                    
                    if let batch = batch {
                        role = batch.role
                        subrole = batch.subrole
                        title = batch.title ?? appName
                        frame = batch.frame ?? .zero
                        isMin = batch.isMinimized
                        isMain = batch.isMain
                        isFullScreen = batch.isFullScreen
                    } else {
                        role = event.element.role
                        subrole = event.element.subrole
                        title = event.element.title ?? appName
                        frame = event.element.frame ?? .zero
                        isMin = event.element.isMinimized
                        isMain = event.element.isMain
                        isFullScreen = event.element.isFullScreen
                    }
                    
                    if let role = role, WindowFilter.shouldInclude(
                        role: role,
                        subrole: subrole,
                        frame: frame,
                        bundleID: bundleID,
                        isAppRegular: true,
                        isMinimized: isMin
                    ) {
                        self.knownWindowKeys.insert(key)
                        let info = WindowInfo(
                            key: key,
                            pid: event.pid,
                            appName: appName,
                            bundleID: bundleID,
                            title: title,
                            frame: frame,
                            isMinimized: isMin,
                            isAppHidden: isHidden,
                            isMain: isMain,
                            isFullScreen: isFullScreen
                        )
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.store.addOrUpdateWindow(info)
                            let isFront = (event.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier)
                            if isFront && !isMin {
                                self.store.setFrontmostPID(event.pid)
                                self.store.setFocusedWindow(key: key)
                            }
                            self.onWindowsChanged?()
                        }
                    }
                }
            } else if name == (kAXUIElementDestroyedNotification as String) {
                if let winID = event.resolvedWindowID ?? event.element.windowID {
                    let key = WindowKey(id: winID, pid: event.pid)
                    self.knownWindowKeys.remove(key)
                    AppTracker.removeElement(for: key)
                    WorkAreaEnforcer.shared.removeWindow(winID: winID)
                    DispatchQueue.main.async { [weak self] in
                        self?.store.removeWindow(key: key)
                    }
                }
            }
            
            markPIDDirty(event.pid)
            DispatchQueue.main.async { [weak self] in
                self?.scheduleDirtyReconcile(delay: TaskbarConstants.Timing.frameRenderDebounce)
            }
            return
        }
        
        // Fallback for any other events: mark dirty
        markPIDDirty(event.pid)
        DispatchQueue.main.async { [weak self] in
            self?.scheduleDirtyReconcile(delay: TaskbarConstants.Timing.frameRenderDebounce)
        }
    }
    
    // MARK: - Tier 2 (Dirty-PID Reconcile)
    
    nonisolated private func markPIDDirty(_ pid: pid_t) {
        dirtyPIDsLock.withLock {
            _ = dirtyPIDs.insert(pid)
        }
    }
    
    private func scheduleDirtyReconcile(delay: TimeInterval = TaskbarConstants.Timing.frameRenderDebounce) {
        pendingDirtyDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcileDirtyPIDs()
        }
        pendingDirtyDebounceWorkItem = workItem
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    private func reconcileDirtyPIDs() {
        guard AccessibilityPermission.isGranted() else { return }
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let activePIDs = Set(runningApps.map(\.processIdentifier))
        let validPIDs: Set<pid_t> = dirtyPIDsLock.withLock {
            let matching = dirtyPIDs.intersection(activePIDs)
            dirtyPIDs.subtract(matching)
            return matching
        }
        guard !validPIDs.isEmpty else { return }
        
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        
        AXThread.shared.async { [weak self] in
            guard let self = self else { return }
            var updatedWindows: [pid_t: [WindowInfo]] = [:]
            var focusedKey: WindowKey? = nil
            
            for pid in validPIDs {
                if AppTracker.isPIDBackedOff(pid) {
                    continue
                }
                guard let app = runningApps.first(where: { $0.processIdentifier == pid }) else {
                    continue
                }
                let (windows, appFocused) = self.inspectApp(app: app, isFrontmost: pid == frontmostPID)
                if let windows = windows {
                    updatedWindows[pid] = windows
                    let currentKeys = Set(windows.map(\.key))
                    self.knownWindowKeys = self.knownWindowKeys.filter { $0.pid != pid }.union(currentKeys)
                }
                if let f = appFocused {
                    focusedKey = f
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var didChange = false
                if let frontmostPID = frontmostPID {
                    if self.store.setFrontmostPID(frontmostPID) {
                        didChange = true
                    }
                }
                if let focusedKey = focusedKey {
                    if self.store.setFocusedWindow(key: focusedKey) {
                        didChange = true
                    }
                } else if let frontmostPID = frontmostPID, validPIDs.contains(frontmostPID), !AppTracker.isPIDBackedOff(frontmostPID) {
                    if self.store.setFocusedWindow(key: nil) {
                        didChange = true
                    }
                }
                for (pid, wins) in updatedWindows {
                    if self.store.syncSnapshot(forPID: pid, currentWindows: wins) {
                        didChange = true
                    }
                }
                if didChange {
                    self.onWindowsChanged?()
                }
            }
        }
    }
    
    // MARK: - Tier 3 (Chunked Full Sweep)
    
    public func scheduleReconcile(delay: TimeInterval = TaskbarConstants.Timing.frameRenderDebounce) {
        scheduleFullSweep(delay: delay)
    }
    
    public func scheduleFullSweep(delay: TimeInterval = TaskbarConstants.Timing.frameRenderDebounce) {
        pendingFullDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performFullSweep()
        }
        pendingFullDebounceWorkItem = workItem
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    private func performFullSweep() {
        guard AccessibilityPermission.isGranted() else {
            schedulePermissionCheck()
            return
        }
        stopPermissionCheck()
        
        let generation: UInt64 = sweepGenerationLock.withLock {
            _currentSweepGeneration &+= 1
            return _currentSweepGeneration
        }
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let allActivePIDs = Set(runningApps.map(\.processIdentifier))
        
        for app in runningApps {
            trackApp(app.processIdentifier)
        }
        
        let initialFocusedKey: WindowKey? = (frontmostPID != nil && AppTracker.isPIDBackedOff(frontmostPID!)) ? store.focusedWindowKey : nil
        
        AXThread.shared.async { [weak self] in
            guard let self = self, self.currentSweepGeneration == generation else { return }
            self.sweepNextChunk(
                remainingApps: runningApps,
                generation: generation,
                frontmostPID: frontmostPID,
                accumulatedWindows: [:],
                focusedKey: initialFocusedKey,
                allActivePIDs: allActivePIDs
            )
        }
    }
    
    nonisolated private func sweepNextChunk(
        remainingApps: [NSRunningApplication],
        generation: UInt64,
        frontmostPID: pid_t?,
        accumulatedWindows: [pid_t: [WindowInfo]],
        focusedKey: WindowKey?,
        allActivePIDs: Set<pid_t>
    ) {
        guard !remainingApps.isEmpty else {
            let newKeys = Set(accumulatedWindows.values.flatMap { $0 }.map(\.key))
            let preservedKeys = self.knownWindowKeys.filter {
                !accumulatedWindows.keys.contains($0.pid) && allActivePIDs.contains($0.pid)
            }
            self.knownWindowKeys = newKeys.union(preservedKeys)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.currentSweepGeneration == generation else { return }
                self.finishFullSweep(
                    updatedWindows: accumulatedWindows,
                    focusedKey: focusedKey,
                    allActivePIDs: allActivePIDs,
                    frontmostPID: frontmostPID
                )
            }
            return
        }
        
        let chunkSize = 2
        let currentBatch = Array(remainingApps.prefix(chunkSize))
        let nextRemaining = Array(remainingApps.dropFirst(chunkSize))
        
        AXThread.shared.async { [weak self] in
            guard let self = self, self.currentSweepGeneration == generation else { return }
            var batchWindows = accumulatedWindows
            var currentFocused = focusedKey
            
            for app in currentBatch {
                let pid = app.processIdentifier
                if AppTracker.isPIDBackedOff(pid) {
                    continue
                }
                let (windows, appFocused) = self.inspectApp(app: app, isFrontmost: pid == frontmostPID)
                if let windows = windows {
                    batchWindows[pid] = windows
                }
                if let f = appFocused {
                    currentFocused = f
                }
            }
            
            self.sweepNextChunk(
                remainingApps: nextRemaining,
                generation: generation,
                frontmostPID: frontmostPID,
                accumulatedWindows: batchWindows,
                focusedKey: currentFocused,
                allActivePIDs: allActivePIDs
            )
        }
    }
    
    @MainActor
    private func finishFullSweep(
        updatedWindows: [pid_t: [WindowInfo]],
        focusedKey: WindowKey?,
        allActivePIDs: Set<pid_t>,
        frontmostPID: pid_t?
    ) {
        var didChange = false
        
        let storedPIDs = Set(store.allWindows.map(\.pid))
        for stalePID in storedPIDs where !allActivePIDs.contains(stalePID) {
            store.removeWindows(forPID: stalePID)
            AppTracker.removeAllElements(forPID: stalePID)
            AppTracker.clearBackoff(for: stalePID)
            WorkAreaEnforcer.shared.removeApp(pid: stalePID)
            AXThread.shared.async { [weak self] in
                guard let self = self else { return }
                self.knownWindowKeys = self.knownWindowKeys.filter { $0.pid != stalePID }
                self.observers.removeValue(forKey: stalePID)?.invalidate()
            }
            didChange = true
        }
        
        store.setFrontmostPID(frontmostPID)
        let isFrontmostBackedOff = frontmostPID != nil && AppTracker.isPIDBackedOff(frontmostPID!)
        if let focusedKey = focusedKey {
            if store.setFocusedWindow(key: focusedKey) {
                didChange = true
            }
        } else if !isFrontmostBackedOff {
            if store.setFocusedWindow(key: nil) {
                didChange = true
            }
        }
        
        for (pid, wins) in updatedWindows {
            if store.syncSnapshot(forPID: pid, currentWindows: wins) {
                didChange = true
            }
        }
        
        if didChange {
            onWindowsChanged?()
        }
    }
    
    // MARK: - Inspection Helper
    
    nonisolated private func inspectApp(app: NSRunningApplication, isFrontmost: Bool) -> ([WindowInfo]?, WindowKey?) {
        let pid = app.processIdentifier
        if AppTracker.isPIDBackedOff(pid) {
            return (nil, nil)
        }
        
        let bundleID = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? "App"
        let isHidden = app.isHidden
        
        let appElement = AXUIElementCreateApplication(pid)
        appElement.setTimeout(TaskbarConstants.Timing.axTimeout)
        
        var focusedKey: WindowKey? = nil
        if isFrontmost {
            var focusedVal: AnyObject?
            let fRes = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedVal)
            if fRes == .cannotComplete {
                AppTracker.recordTimeout(for: pid)
                return (nil, nil)
            }
            if fRes == .success, let fWin = focusedVal, CFGetTypeID(fWin) == AXUIElementGetTypeID() {
                let focusedElement = (fWin as! AXUIElement)
                if let fWid = focusedElement.windowID {
                    let fKey = WindowKey(id: fWid, pid: pid)
                    focusedKey = fKey
                    AppTracker.cacheElement(focusedElement, for: fKey)
                }
            }
        }
        
        var windowsValue: AnyObject?
        let winsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        if winsResult == .cannotComplete {
            AppTracker.recordTimeout(for: pid)
            return (nil, nil)
        }
        guard winsResult == .success, let windowElements = windowsValue as? [AXUIElement] else {
            return ([], focusedKey)
        }
        
        var appWindows: [WindowInfo] = []
        var validWindowIDs: Set<CGWindowID> = []
        
        for win in windowElements {
            win.setTimeout(TaskbarConstants.Timing.axTimeout)
            
            guard let wid = win.windowID else { continue }
            validWindowIDs.insert(CGWindowID(wid))
            
            let batchStart = AppEnvironment.current.clock.now()
            let batch = win.fetchWindowAttributesBatch()
            let batchElapsed = AppEnvironment.current.clock.now() - batchStart
            if batch == nil && batchElapsed >= Double(TaskbarConstants.Timing.axTimeout) {
                AppTracker.recordTimeout(for: pid)
                return (nil, nil)
            }
            
            let role: String?
            let subrole: String?
            let title: String
            let frame: CGRect
            let isMin: Bool
            let isMain: Bool
            let isFullScreen: Bool
            
            if let batch = batch {
                guard let r = batch.role else { continue }
                role = r
                subrole = batch.subrole
                title = batch.title ?? appName
                frame = batch.frame ?? .zero
                isMin = batch.isMinimized
                isMain = batch.isMain
                isFullScreen = batch.isFullScreen
            } else {
                guard let r = win.role else { continue }
                role = r
                subrole = win.subrole
                title = win.title ?? appName
                frame = win.frame ?? .zero
                isMin = win.isMinimized
                isMain = win.isMain
                isFullScreen = win.isFullScreen
            }
            
            guard let validRole = role, WindowFilter.shouldInclude(
                role: validRole,
                subrole: subrole,
                frame: frame,
                bundleID: bundleID,
                isAppRegular: true,
                isMinimized: isMin
            ) else {
                continue
            }
            
            let key = WindowKey(id: wid, pid: pid)
            AppTracker.cacheElement(win, for: key)
            observers[pid]?.observeWindow(win)
            
            let info = WindowInfo(
                key: key,
                pid: pid,
                appName: appName,
                bundleID: bundleID,
                title: title,
                frame: frame,
                isMinimized: isMin,
                isAppHidden: isHidden,
                isMain: isMain,
                isFullScreen: isFullScreen
            )
            appWindows.append(info)
            
            if !knownWindowKeys.contains(key) {
                knownWindowKeys.insert(key)
                if !isMin && !isHidden {
                    WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: win, pid: pid, isResize: false)
                }
            }
            
            if isFrontmost && focusedKey == nil && isMain {
                focusedKey = key
            }
        }
        
        // Resilient fallback for Chromium / Electron applications where kAXFocusedWindowAttribute and isMain return no value
        if isFrontmost && focusedKey == nil && !appWindows.isEmpty {
            if let frontWID = WindowActions.frontmostWindowID(forPID: pid) {
                let fKey = WindowKey(id: UInt64(frontWID), pid: pid)
                if appWindows.contains(where: { $0.key == fKey }) {
                    focusedKey = fKey
                }
            }
        }
        
        observers[pid]?.pruneWindows(keeping: validWindowIDs)
        
        return (appWindows, focusedKey)
    }
    
    // MARK: - Lifecycle Teardown
    
    public func stopTracking() {
        stopPermissionCheck()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
        
        pendingDirtyDebounceWorkItem?.cancel()
        pendingDirtyDebounceWorkItem = nil
        pendingFullDebounceWorkItem?.cancel()
        pendingFullDebounceWorkItem = nil
        spaceSettleWorkItem?.cancel()
        spaceSettleWorkItem = nil
        
        AppTracker.clearElementCache()
        AppTracker.clearAllBackoffs()
        
        AXThread.shared.async { [self] in
            for observer in self.observers.values {
                observer.stop()
            }
            self.observers.removeAll()
            self.knownWindowKeys.removeAll()
            self.pendingPIDs.removeAll()
        }
    }
    
    deinit {
        permissionPollTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
    }
}
