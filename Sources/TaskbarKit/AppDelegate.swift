// Sources/TaskbarApp/AppDelegate.swift

import AppKit
import TaskbarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: Settings!
    private var store: WindowStore!
    private var screenManager: ScreenManager?
    private var appTracker: AppTracker?
    private var statusMenu: StatusMenu?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Discover and register custom JSON themes on disk before loading settings
        ThemeFileLoader.shared.reloadCustomThemes()
        
        // Load persistent or default settings
        self.settings = Settings.load()
        
        // Initialize canonical window store
        let store = WindowStore()
        self.store = store
        
        // Check Accessibility permission on startup
        if !AccessibilityPermission.isGranted() {
            TaskbarLogger.lifecycle.info("Accessibility permission not granted yet. Prompting user...")
            AccessibilityPermission.promptIfNecessary()
        }
        
        // Hide macOS System Dock if enabled in settings
        if settings.hideSystemDock {
            DockController.shared.hideDock(delay: settings.dockHideDelay)
        }
        
        // Initialize multi-screen manager
        let screenManager = ScreenManager(settings: settings, store: store)
        self.screenManager = screenManager
        
        // Configure WorkAreaEnforcer for reserving taskbar space
        WorkAreaEnforcer.shared.configure(
            isEnabled: settings.enableAXNudger,
            barHeight: CGFloat(settings.barHeight),
            screens: screenManager.screenDescriptors()
        )
        
        // Initialize AppTracker for live window tracking
        let appTracker = AppTracker(store: store)
        appTracker.onWindowsChanged = { [weak self] in
            guard let self = self else { return }
            self.screenManager?.updateWindows()
        }
        self.appTracker = appTracker
        
        // Initialize menu bar status item
        let statusMenu = StatusMenu(
            currentStyle: settings.themeStyle,
            currentThemeId: settings.activeThemeId,
            minButtonWidth: settings.minButtonWidth,
            barHeight: settings.barHeight,
            fontSize: settings.fontSize,
            iconSize: settings.iconSize,
            isNudgerEnabled: settings.enableAXNudger,
            isDockHidden: settings.hideSystemDock,
            dockDelay: settings.dockHideDelay
        )
        statusMenu.onThemeIdChanged = { [weak self] themeId in
            guard let self = self else { return }
            self.settings.activeThemeId = themeId
            let theme = ThemeRegistry.shared.theme(for: themeId)
            if theme.isCustom {
                self.settings.fontSize = theme.metrics.fontSize
                self.settings.iconSize = theme.metrics.iconSize
                if let customBarHeight = theme.metrics.barHeight, customBarHeight > 0 {
                    self.settings.barHeight = customBarHeight
                    self.statusMenu?.updateBarHeight(customBarHeight)
                }
                if let customMinWidth = theme.metrics.minButtonWidth, customMinWidth > 0 {
                    self.settings.minButtonWidth = customMinWidth
                    self.statusMenu?.updateMinButtonWidth(customMinWidth)
                }
                self.statusMenu?.updateFontSize(theme.metrics.fontSize)
                self.statusMenu?.updateIconSize(theme.metrics.iconSize)
            }
            self.settings.save()
            self.screenManager?.updateTheme(themeId: themeId)
        }
        statusMenu.onReloadThemesRequested = { [weak self] in
            guard let self = self else { return }
            let count = ThemeFileLoader.shared.reloadCustomThemes().count
            TaskbarLogger.ui.info("Reloaded custom themes: \(count) theme(s) found.")
            let activeId = self.settings.activeThemeId
            let theme = ThemeRegistry.shared.theme(for: activeId)
            if theme.id != activeId && !ThemeRegistry.shared.isBuiltIn(themeId: activeId) {
                self.settings.activeThemeId = ThemeDefinition.modernHybrid.id
                self.settings.save()
            }
            self.screenManager?.updateTheme(themeId: self.settings.activeThemeId)
            self.statusMenu?.updateThemeId(self.settings.activeThemeId)
        }
        statusMenu.onOpenThemesFolderRequested = {
            let dir = ThemeFileLoader.shared.customThemesDirectory
            try? ThemeFileLoader.shared.createDirectoryIfNeeded()
            NSWorkspace.shared.open(dir)
        }
        statusMenu.onExportThemeRequested = { [weak self] in
            guard let self = self else { return }
            self.exportActiveTheme()
        }
        statusMenu.onMinButtonWidthChanged = { [weak self] minWidth in
            guard let self = self else { return }
            self.settings.minButtonWidth = minWidth
            self.settings.save()
            self.screenManager?.updateMinButtonWidth(minWidth)
        }
        statusMenu.onBarHeightChanged = { [weak self] newHeight in
            guard let self = self else { return }
            self.settings.barHeight = newHeight
            self.settings.save()
            self.screenManager?.updateBarHeight(newHeight)
            self.appTracker?.scheduleReconcile(delay: 0.05)
        }
        statusMenu.onFontSizeChanged = { [weak self] newSize in
            guard let self = self else { return }
            self.settings.fontSize = newSize
            self.settings.save()
            self.screenManager?.updateFontSize(newSize)
        }
        statusMenu.onIconSizeChanged = { [weak self] newSize in
            guard let self = self else { return }
            self.settings.iconSize = newSize
            self.settings.save()
            self.screenManager?.updateIconSize(newSize)
        }
        statusMenu.onNudgerToggled = { [weak self] enabled in
            guard let self = self else { return }
            self.settings.enableAXNudger = enabled
            self.settings.save()
            WorkAreaEnforcer.shared.isEnabled = enabled
            if enabled {
                self.appTracker?.scheduleReconcile(delay: 0.05)
            }
        }
        statusMenu.onHideDockToggled = { [weak self] hide in
            guard let self = self else { return }
            self.settings.hideSystemDock = hide
            self.settings.save()
            if hide {
                DockController.shared.hideDock(delay: self.settings.dockHideDelay)
            } else {
                DockController.shared.restoreDock()
            }
        }
        statusMenu.onDockDelayChanged = { [weak self] newDelay in
            guard let self = self else { return }
            self.settings.dockHideDelay = newDelay
            self.settings.save()
            if self.settings.hideSystemDock {
                DockController.shared.hideDock(delay: newDelay)
            }
        }
        statusMenu.onRestoreDockRequested = { [weak self] in
            guard let self = self else { return }
            self.settings.hideSystemDock = false
            self.settings.save()
            DockController.shared.restoreDock()
        }
        statusMenu.onLauncherTriggered = { [weak self] in
            guard let self = self else { return }
            Launcher.launch(self.settings.launcherAction)
        }
        statusMenu.onQuitRequested = {
            NSApplication.shared.terminate(nil)
        }
        self.statusMenu = statusMenu
        
        TaskbarLogger.lifecycle.info("Started successfully on \(NSScreen.screens.count) screen(s). Theme: \(self.settings.activeThemeId). Dock: \(self.settings.hideSystemDock ? "Hidden" : "Visible"). Tracking active.")
    }
    
    private func exportActiveTheme() {
        let currentTheme = settings.currentTheme
        let savePanel = NSSavePanel()
        savePanel.title = TaskbarStrings.Themes.exportCurrentTheme
        savePanel.nameFieldStringValue = "\(currentTheme.id).json"
        savePanel.canCreateDirectories = true
        if #available(macOS 11.0, *) {
            savePanel.allowedContentTypes = [.json]
        }
        
        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try ThemeFileLoader.shared.exportTheme(currentTheme, to: targetURL)
                TaskbarLogger.ui.info("Exported theme '\(currentTheme.id)' to \(targetURL.path)")
            } catch {
                TaskbarLogger.ui.error("Failed to export theme '\(currentTheme.id)': \(error.localizedDescription)")
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        // Guaranteed restoration of native macOS Dock on quit
        DockController.restoreDockSync()
        screenManager?.closeAll()
        TaskbarLogger.lifecycle.info("Terminated cleanly.")
    }
}
