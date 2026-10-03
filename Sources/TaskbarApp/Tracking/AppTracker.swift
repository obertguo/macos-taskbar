// Sources/TaskbarApp/Tracking/AppTracker.swift

import AppKit
import ApplicationServices
import TaskbarCore

@MainActor
public final class AppTracker {
    public let store: WindowStore
    public var onWindowsChanged: (() -> Void)?
    
    private var observers: [pid_t: AXAppObserver] = [:]
    private var isRefreshing = false
    private var pendingDebounceWorkItem: DispatchWorkItem?
    
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
    }
    
    public func startTrackingAllRunningApps() {
        guard AccessibilityPermission.isGranted() else { return }
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in runningApps {
            trackApp(app.processIdentifier)
        }
        
        scheduleReconcile(delay: 0.0)
    }
    
    private func trackApp(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        
        AXThread.shared.async { [weak self] in
            let observer = AXAppObserver(pid: pid) { [weak self] in
                DispatchQueue.main.async {
                    self?.scheduleReconcile(delay: 0.016)
                }
            }
            
            if let obs = observer {
                DispatchQueue.main.async {
                    self?.observers[pid] = obs
                }
            }
        }
    }
    
    private func untrackApp(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            observer.invalidate()
        }
        store.removeWindows(forPID: pid)
        onWindowsChanged?()
    }
    
    @objc private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        trackApp(app.processIdentifier)
        scheduleReconcile(delay: 0.05)
    }
    
    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        untrackApp(app.processIdentifier)
    }
    
    @objc private func handleAppActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        store.setFrontmostPID(app.processIdentifier)
        scheduleReconcile(delay: 0.016)
    }
    
    @objc private func handleAppHidden(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        store.setAppHidden(pid: app.processIdentifier, isHidden: true)
        onWindowsChanged?()
    }
    
    @objc private func handleAppUnhidden(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        store.setAppHidden(pid: app.processIdentifier, isHidden: false)
        scheduleReconcile(delay: 0.016)
    }
    
    @objc private func handleActiveSpaceChanged(_ notification: Notification) {
        scheduleReconcile(delay: 0.05)
        scheduleReconcile(delay: 0.15)
    }
    
    public func scheduleReconcile(delay: TimeInterval = 0.016) {
        pendingDebounceWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcileWindows()
        }
        pendingDebounceWorkItem = workItem
        
        if delay <= 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    private func reconcileWindows() {
        guard !isRefreshing, AccessibilityPermission.isGranted() else { return }
        isRefreshing = true
        
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let frontmostPID = frontmostApp?.processIdentifier
        let activeObservers = self.observers
        
        AXThread.shared.async { [weak self, store = self.store] in
            var updatedWindows: [pid_t: [WindowInfo]] = [:]
            var currentFocusedKey: WindowKey? = nil
            
            for app in runningApps {
                let pid = app.processIdentifier
                let bundleID = app.bundleIdentifier ?? ""
                let appName = app.localizedName ?? "App"
                let isHidden = app.isHidden
                let observer = activeObservers[pid]
                
                let appElement = AXUIElementCreateApplication(pid)
                appElement.setTimeout(0.3)
                
                if pid == frontmostPID, let focusedWin = appElement.focusedWindow {
                    currentFocusedKey = WindowKey(id: focusedWin.windowID, pid: pid)
                }
                
                let windowElements = appElement.windows
                var appWindows: [WindowInfo] = []
                
                for win in windowElements {
                    win.setTimeout(0.3)
                    
                    // Attach per-window AX notifications
                    observer?.observeWindow(win)
                    
                    guard let role = win.role else { continue }
                    let subrole = win.subrole
                    let frame = win.frame ?? .zero
                    let isMin = win.isMinimized
                    let isMain = win.isMain
                    
                    if WindowFilter.shouldInclude(
                        role: role,
                        subrole: subrole,
                        frame: frame,
                        bundleID: bundleID,
                        isAppRegular: true,
                        isMinimized: isMin
                    ) {
                        let title = win.title ?? appName
                        let key = WindowKey(id: win.windowID, pid: pid)
                        
                        let info = WindowInfo(
                            key: key,
                            pid: pid,
                            appName: appName,
                            bundleID: bundleID,
                            title: title,
                            frame: frame,
                            isMinimized: isMin,
                            isAppHidden: isHidden,
                            isMain: isMain
                        )
                        appWindows.append(info)
                        
                        // Check if maximized window needs work area clamping
                        if !isMin && !isHidden {
                            WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: win, pid: pid, isResize: false)
                        }
                        
                        // Fallback focused window detection (if appElement.focusedWindow returned nil, e.g. in Chrome)
                        if pid == frontmostPID && currentFocusedKey == nil && isMain {
                            currentFocusedKey = key
                        }
                    }
                }
                
                updatedWindows[pid] = appWindows
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                store.setFrontmostPID(frontmostPID)
                store.setFocusedWindow(key: currentFocusedKey)
                
                for (pid, wins) in updatedWindows {
                    store.syncSnapshot(forPID: pid, currentWindows: wins)
                }
                
                self.isRefreshing = false
                self.onWindowsChanged?()
            }
        }
    }
}
