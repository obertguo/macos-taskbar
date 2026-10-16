// Sources/TaskbarKit/UI/Management/ScreenManager.swift

import AppKit
import TaskbarCore

@MainActor
public final class ScreenManager {
    private var panels: [CGDirectDisplayID: TaskbarPanel] = [:]
    private var cachedFullScreenDisplayIDs: Set<CGDirectDisplayID> = []
    public let settingsStore: SettingsStore
    public var settings: Settings { settingsStore.settings }
    public var currentTheme: ThemeDefinition { settingsStore.currentTheme }
    public let store: WindowStore
    
    public init(settingsStore: SettingsStore, store: WindowStore) {
        self.settingsStore = settingsStore
        self.store = store
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
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
    
    public func updateBarHeight(_ barHeight: Double) {
        settingsStore.update { $0.barHeight = barHeight }
    }
    
    public func updateMinButtonWidth(_ minWidth: Double) {
        settingsStore.update { $0.minButtonWidth = minWidth }
    }
    
    public func updateFontSize(_ fontSize: Double) {
        settingsStore.update { $0.fontSize = fontSize }
    }
    
    public func updateIconSize(_ iconSize: Double) {
        settingsStore.update { $0.iconSize = iconSize }
    }
    
    public func updateTheme(themeId: String) {
        let theme = ThemeRegistry.shared.theme(for: themeId)
        settingsStore.update { settings in
            settings.activeThemeId = themeId
            if theme.isCustom {
                settings.fontSize = theme.metrics.fontSize
                settings.iconSize = theme.metrics.iconSize
                if let customBarHeight = theme.metrics.barHeight, customBarHeight > 0 {
                    settings.barHeight = customBarHeight
                }
                if let customMinWidth = theme.metrics.minButtonWidth, customMinWidth > 0 {
                    settings.minButtonWidth = customMinWidth
                }
                if let customMaxWidth = theme.metrics.maxButtonWidth, customMaxWidth > 0 {
                    settings.maxButtonWidth = customMaxWidth
                }
                if let customSpacing = theme.metrics.buttonSpacing, customSpacing >= 0 {
                    settings.buttonSpacing = customSpacing
                }
            }
        }
    }
    
    public func updateThemeStyle(_ style: ThemeStyle) {
        updateTheme(themeId: ThemeDefinition.forStyle(style).id)
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
    
    public func refreshPinnedAppsAcrossPanels() {
        let runningBundleIDs = Set(store.allWindows.map { $0.bundleID })
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
    }
    
    @objc private func handleScreenParametersChanged() {
        var fs = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let displayID = screen.displayID ?? 0
            if displayID != 0 && isScreenInFullScreen(screen: screen) {
                fs.insert(displayID)
            }
        }
        self.cachedFullScreenDisplayIDs = fs
        refreshPanels()
    }
    
    /// Determines whether the active space on a physical display is currently showing a native full-screen app.
    private func isScreenInFullScreen(screen: NSScreen) -> Bool {
        let displayID = screen.displayID ?? 0
        let screenBounds = displayID != 0 ? CGDisplayBounds(displayID) : screen.frame
        
        let onScreenWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
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
        let runningBundleIDs = Set(store.allWindows.map { $0.bundleID })
        
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
        let runningBundleIDs = Set(store.allWindows.map { $0.bundleID })
        
        var windowsByScreen: [UInt32: [WindowInfo]] = [:]
        for win in store.allWindows {
            let assignedScreen = ScreenAssignment.assignScreen(for: win.frame, across: descriptors) ?? descriptors.first(where: { $0.isPrimary })?.id ?? descriptors.first?.id ?? 0
            windowsByScreen[assignedScreen, default: []].append(win)
        }
        
        for (displayID, panel) in panels {
            guard screens.contains(where: {
                $0.displayID == displayID
            }) else { continue }
            
            let screenWindows = windowsByScreen[UInt32(displayID)] ?? []
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
            
            panel.taskbarView.updatePinnedApps(
                settings.pinnedApps,
                runningBundleIDs: runningBundleIDs
            )
            panel.taskbarView.updateWindows(
                windows: screenWindows,
                focusedKey: store.focusedWindowKey,
                frontmostPID: store.frontmostPID
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
