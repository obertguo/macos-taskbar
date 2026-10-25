// Sources/TaskbarKit/UI/Management/ScreenManager.swift

import AppKit
import TaskbarCore

@MainActor
public final class ScreenManager {
    private var panels: [CGDirectDisplayID: TaskbarPanel] = [:]
    private var cachedFullScreenDisplayIDs: Set<CGDirectDisplayID> = []
    private var workspaceRunningBundleIDs: Set<String> = []
    public let settingsStore: SettingsStore
    public var settings: Settings { settingsStore.settings }
    public var currentTheme: ThemeDefinition { settingsStore.currentTheme }
    public let store: WindowStore
    
    public init(settingsStore: SettingsStore, store: WindowStore) {
        self.settingsStore = settingsStore
        self.store = store
        self.workspaceRunningBundleIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.bundleIdentifier }
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationLifecycleChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationLifecycleChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        settingsStore.addObserver { [weak self] oldSettings, newSettings in
            self?.handleSettingsChanged(old: oldSettings, new: newSettings)
        }
        
        refreshPanels()
    }
    
    public convenience init(settings: Settings, store: WindowStore) {
        let settingsStore = SettingsStore(
            persistence: InMemorySettingsPersistence(initial: settings),
            initialSettings: settings
        )
        self.init(settingsStore: settingsStore, store: store)
    }
    
    private func handleSettingsChanged(old: Settings, new: Settings) {
        var shouldRefreshPanels = false
        if old.barHeight != new.barHeight {
            WorkAreaEnforcer.shared.barHeight = CGFloat(new.barHeight)
            shouldRefreshPanels = true
        }
        if old.enableAXNudger != new.enableAXNudger {
            WorkAreaEnforcer.shared.isEnabled = new.enableAXNudger
        }
        for panel in panels.values {
            panel.apply(settings: new, theme: currentTheme)
        }
        if shouldRefreshPanels {
            refreshPanels()
        }
        if old.windowGroupingMode != new.windowGroupingMode {
            updateWindows()
        }
    }
    
    public func screenDescriptors() -> [ScreenDescriptor] {
        NSScreen.screens.map { screen in
            let displayID = screen.displayID ?? 0
            let isPrimary = (screen == NSScreen.screens.first)
            let frame = displayID != 0 ? CGDisplayBounds(displayID) : screen.frame
            return ScreenDescriptor(id: UInt32(displayID), frame: frame, isPrimary: isPrimary)
        }
    }
    
    public func updateSettings(_ newSettings: Settings) {
        settingsStore.update { $0 = newSettings }
    }
    
    public func updateTheme(themeId: String) {
        settingsStore.update { $0.activeThemeId = themeId }
    }
    
    public func updateGroupingMode(_ mode: WindowGroupingMode) {
        settingsStore.update { $0.windowGroupingMode = mode }
    }
    
    public func pinApp(bundleIdentifier: String, displayName: String, customPath: String? = nil) {
        guard !settings.isPinned(bundleIdentifier: bundleIdentifier) else { return }
        settingsStore.update { settings in
            _ = settings.pinApp(bundleIdentifier: bundleIdentifier, displayName: displayName, customPath: customPath)
        }
        refreshPinnedAppsAcrossPanels()
        NotificationCenter.default.post(name: .taskbarPinnedAppsDidChange, object: nil)
    }
    
    public func unpinApp(bundleIdentifier: String) {
        guard settings.isPinned(bundleIdentifier: bundleIdentifier) else { return }
        settingsStore.update { settings in
            _ = settings.unpinApp(bundleIdentifier: bundleIdentifier)
        }
        refreshPinnedAppsAcrossPanels()
        NotificationCenter.default.post(name: .taskbarPinnedAppsDidChange, object: nil)
    }
    
    public func reorderPinnedApps(_ newOrder: [PinnedApp]) {
        settingsStore.update { settings in
            settings.pinnedApps = newOrder
        }
        refreshPinnedAppsAcrossPanels()
        NotificationCenter.default.post(name: .taskbarPinnedAppsDidChange, object: nil)
    }
    
    private func computeRunningBundleIDs() -> Set<String> {
        var ids = Set(store.allWindows.map { $0.bundleID })
        ids.formUnion(workspaceRunningBundleIDs)
        return ids
    }
    
    public func refreshPinnedAppsAcrossPanels() {
        let runningBundleIDs = computeRunningBundleIDs()
        for panel in panels.values {
            panel.updatePinnedApps(settings.pinnedApps, runningBundleIDs: runningBundleIDs)
        }
    }
    
    public var allPanels: [TaskbarPanel] {
        Array(panels.values)
    }
    
    private func configurePanelCallbacks(_ panel: TaskbarPanel) {
        panel.taskbarView.store = store
        panel.taskbarView.onPinRequested = { [weak self] bundleID, appName in
            self?.pinApp(bundleIdentifier: bundleID, displayName: appName)
        }
        panel.taskbarView.onUnpinRequested = { [weak self] bundleID in
            self?.unpinApp(bundleIdentifier: bundleID)
        }
        panel.taskbarView.onPinnedReorderRequested = { [weak self] newPinnedApps in
            self?.reorderPinnedApps(newPinnedApps)
        }
        panel.taskbarView.onFocusRequested = { [weak self] key in
            guard let self = self else { return }
            self.store.setFrontmostPID(key.pid)
            self.store.setFocusedWindow(key: key)
            self.updateWindows()
        }
    }
    
    @objc private func handleActiveSpaceChanged() {
        refreshFullScreenDetection()
        updateWindows()
        
        // Re-evaluate fullscreen detection after the macOS space transition settles (~150ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + TaskbarConstants.Timing.spaceChangeSettleDelay) { [weak self] in
            guard let self = self else { return }
            self.refreshFullScreenDetection()
            self.updateWindows()
        }
    }
    
    @objc private func handleApplicationLifecycleChanged() {
        self.workspaceRunningBundleIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.bundleIdentifier }
        )
        updateWindows()
    }
    
    @objc private func handleScreenParametersChanged() {
        refreshFullScreenDetection()
        refreshPanels()
    }
    
    private func refreshFullScreenDetection() {
        let onScreenWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var fs = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let displayID = screen.displayID ?? 0
            if displayID != 0 && isScreenInFullScreen(screen: screen, onScreenWindows: onScreenWindows) {
                fs.insert(displayID)
            }
        }
        self.cachedFullScreenDisplayIDs = fs
    }
    
    /// Determines whether the active space on a physical display is currently showing a native full-screen app.
    private func isScreenInFullScreen(screen: NSScreen, onScreenWindows: [[String: Any]]) -> Bool {
        let displayID = screen.displayID ?? 0
        let screenBounds = displayID != 0 ? CGDisplayBounds(displayID) : screen.frame
        
        for w in onScreenWindows {
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue } // Normal application layer
            guard let boundsDict = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            
            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            let width = boundsDict["Width"] ?? 0
            let height = boundsDict["Height"] ?? 0
            let winFrame = CGRect(x: x, y: y, width: width, height: height)
            
            // Native full-screen windows cover the entire physical screen display bounds
            let tol = TaskbarConstants.WorkArea.fullScreenDisplayTolerance
            if abs(winFrame.minX - screenBounds.minX) <= tol &&
               abs(winFrame.minY - screenBounds.minY) <= tol &&
               abs(winFrame.width - screenBounds.width) <= tol &&
               abs(winFrame.height - screenBounds.height) <= tol {
                return true
            }
        }
        return false
    }
    
    public func refreshPanels() {
        let screens = NSScreen.screens
        var activeDisplayIDs = Set<CGDirectDisplayID>()
        let runningBundleIDs = computeRunningBundleIDs()
        
        for screen in screens {
            let displayID = screen.displayID ?? 0
            activeDisplayIDs.insert(displayID)
            
            let height = CGFloat(settings.barHeight)
            if let existingPanel = panels[displayID] {
                existingPanel.updateLayout(for: screen, height: height)
                existingPanel.updatePinnedApps(settings.pinnedApps, runningBundleIDs: runningBundleIDs)
                existingPanel.updateGroupingMode(settings.windowGroupingMode)
                existingPanel.orderFrontRegardless()
            } else {
                let panel = TaskbarPanel(
                    screen: screen,
                    height: height,
                    theme: currentTheme,
                    launcherAction: settings.launcherAction,
                    minButtonWidth: settings.minButtonWidth,
                    maxButtonWidth: settings.maxButtonWidth,
                    buttonSpacing: settings.buttonSpacing,
                    titleVisibilityThreshold: settings.titleVisibilityThreshold,
                    groupingMode: settings.windowGroupingMode,
                    pinnedApps: settings.pinnedApps,
                    store: store
                )
                configurePanelCallbacks(panel)
                panels[displayID] = panel
                panel.orderFrontRegardless()
            }
        }
        
        // Remove panels for disconnected screens
        for (displayID, panel) in panels {
            if !activeDisplayIDs.contains(displayID) {
                panel.close()
                panels.removeValue(forKey: displayID)
            }
        }
        
        WorkAreaEnforcer.shared.updateScreens(screenDescriptors())
        updateWindows()
    }
    
    public func updateWindows() {
        let descriptors = screenDescriptors()
        let screens = NSScreen.screens
        let runningBundleIDs = computeRunningBundleIDs()
        
        for (displayID, panel) in panels {
            guard screens.contains(where: {
                $0.displayID == displayID
            }) else { continue }
            
            let screenWindows = store.windows(forScreenID: UInt32(displayID), screens: descriptors)
            let isFullScreen = screenWindows.contains { $0.isFullScreen } || cachedFullScreenDisplayIDs.contains(displayID)
            
            if isFullScreen {
                if panel.isVisible {
                    panel.orderOut(nil)
                }
            } else {
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                }
            }
            
            if panel.taskbarView.currentPinnedApps != settings.pinnedApps {
                panel.taskbarView.updatePinnedApps(
                    settings.pinnedApps,
                    runningBundleIDs: runningBundleIDs
                )
            }
            panel.taskbarView.updateWindows(
                windows: screenWindows,
                focusedKey: store.focusedWindowKey,
                frontmostPID: store.frontmostPID,
                runningBundleIDs: runningBundleIDs
            )
        }
    }
    
    public func closeAll() {
        for panel in panels.values {
            panel.close()
        }
        panels.removeAll()
    }
    
    public func stop() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        closeAll()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
