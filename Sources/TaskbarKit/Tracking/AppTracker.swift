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
    
    nonisolated(unsafe) private var currentSweepGeneration: UInt64 = 0
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
        knownWindowKeys = knownWindowKeys.filter { $0.pid != pid }
        WorkAreaEnforcer.shared.removeApp(pid: pid)
        AXThread.shared.async { [weak self] in
            guard let self = self else { return }
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
                if elapsed > Double(TaskbarConstants.Timing.axTimeout) {
                    AppTracker.recordTimeout(for: event.pid)
                }
                
                let role = batch?.role ?? event.element.role
                let subrole = batch?.subrole ?? event.element.subrole
                let isMin = batch?.isMinimized ?? event.element.isMinimized
                let frame = batch?.frame ?? event.element.frame ?? .zero
                let isMain = batch?.isMain ?? event.element.isMain
                let isFullScreen = batch?.isFullScreen ?? event.element.isFullScreen
                
                let app = NSRunningApplication(processIdentifier: event.pid)
                let appName = app?.localizedName ?? "App"
                let bundleID = app?.bundleIdentifier ?? ""
                let isAppHidden = app?.isHidden ?? false
                let title = batch?.title ?? event.element.title ?? appName
                
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
                    self.store.addOrUpdateWindow(info)
                    if isMain && !isMin {
                        self.store.setFocusedWindow(key: key)
                    }
                    self.onWindowsChanged?()
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
                    let batch = event.element.fetchWindowAttributesBatch()
                    let role = batch?.role ?? event.element.role
                    let subrole = batch?.subrole ?? event.element.subrole
                    let frame = batch?.frame ?? event.element.frame ?? .zero
                    let isMin = batch?.isMinimized ?? event.element.isMinimized
                    let isMain = batch?.isMain ?? event.element.isMain
                    let isFullScreen = batch?.isFullScreen ?? event.element.isFullScreen
                    
                    let app = NSRunningApplication(processIdentifier: event.pid)
                    let appName = app?.localizedName ?? "App"
                    let bundleID = app?.bundleIdentifier ?? ""
                    let isHidden = app?.isHidden ?? false
                    let title = batch?.title ?? event.element.title ?? appName
                    
                    if let role = role, WindowFilter.shouldInclude(
                        role: role,
                        subrole: subrole,
                        frame: frame,
                        bundleID: bundleID,
                        isAppRegular: true,
                        isMinimized: isMin
                    ) {
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
                            self.onWindowsChanged?()
                        }
                    }
                }
            } else if name == (kAXUIElementDestroyedNotification as String) {
                if let winID = event.resolvedWindowID ?? event.element.windowID {
                    let key = WindowKey(id: winID, pid: event.pid)
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
                updatedWindows[pid] = windows
                if let f = appFocused {
                    focusedKey = f
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var didChange = false
                if let focusedKey = focusedKey {
                    if self.store.setFocusedWindow(key: focusedKey) {
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
        
        currentSweepGeneration &+= 1
        let generation = currentSweepGeneration
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let allActivePIDs = Set(runningApps.map(\.processIdentifier))
        
        for app in runningApps {
            trackApp(app.processIdentifier)
        }
        
        sweepNextChunk(
            remainingApps: runningApps,
            generation: generation,
            frontmostPID: frontmostPID,
            accumulatedWindows: [:],
            focusedKey: nil,
            allActivePIDs: allActivePIDs
        )
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
                batchWindows[pid] = windows
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
            knownWindowKeys = knownWindowKeys.filter { $0.pid != stalePID }
            WorkAreaEnforcer.shared.removeApp(pid: stalePID)
            AXThread.shared.async { [weak self] in
                self?.observers.removeValue(forKey: stalePID)?.invalidate()
            }
            didChange = true
        }
        
        store.setFrontmostPID(frontmostPID)
        if store.setFocusedWindow(key: focusedKey) {
            didChange = true
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
    
    nonisolated private func inspectApp(app: NSRunningApplication, isFrontmost: Bool) -> ([WindowInfo], WindowKey?) {
        let pid = app.processIdentifier
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
                return ([], nil)
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
            return ([], focusedKey)
        }
        guard winsResult == .success, let windowElements = windowsValue as? [AXUIElement] else {
            return ([], focusedKey)
        }
        
        var appWindows: [WindowInfo] = []
        
        for win in windowElements {
            win.setTimeout(TaskbarConstants.Timing.axTimeout)
            
            observers[pid]?.observeWindow(win)
            
            let batch = win.fetchWindowAttributesBatch()
            let role = batch?.role ?? win.role
            guard let role = role else { continue }
            let subrole = batch?.subrole ?? win.subrole
            let frame = batch?.frame ?? win.frame ?? .zero
            let isMin = batch?.isMinimized ?? win.isMinimized
            let isMain = batch?.isMain ?? win.isMain
            let isFullScreen = batch?.isFullScreen ?? win.isFullScreen
            
            if WindowFilter.shouldInclude(
                role: role,
                subrole: subrole,
                frame: frame,
                bundleID: bundleID,
                isAppRegular: true,
                isMinimized: isMin
            ) {
                guard let wid = win.windowID else { continue }
                let key = WindowKey(id: wid, pid: pid)
                AppTracker.cacheElement(win, for: key)
                
                let title = batch?.title ?? win.title ?? appName
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
        }
        
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
        
        AXThread.shared.async { [weak self] in
            guard let self = self else { return }
            for observer in self.observers.values {
                observer.invalidate()
            }
            self.observers.removeAll()
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
