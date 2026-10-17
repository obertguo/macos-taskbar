// Sources/TaskbarKit/AppDelegate.swift

import AppKit
import TaskbarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsStore: SettingsStore!
    private var store: WindowStore!
    private var screenManager: ScreenManager?
    private var appTracker: AppTracker?
    private var statusMenu: StatusMenu?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Discover and register custom JSON themes on disk before loading settings
        ThemeFileLoader.shared.reloadCustomThemes()
        
        // Initialize settings store with persistence
        self.settingsStore = SettingsStore(persistence: UserDefaultsSettingsPersistence())
        let settings = settingsStore.settings
        
        // Initialize canonical window store
        let store = WindowStore()
        self.store = store
        
        // Check Accessibility permission on startup
        if !AccessibilityPermission.isGranted() {
            TaskbarLogger.lifecycle.info("Accessibility permission not granted yet. Prompting user...")
            AccessibilityPermission.promptIfNecessary()
        }
        
        // Reconcile macOS System Dock state with crash recovery
        DockController.shared.reconcileOnLaunch(
            shouldHideDock: settings.hideSystemDock,
            delay: settings.dockHideDelay
        )
        
        // Configure WorkAreaEnforcer for reserving taskbar space before panels or tracking initialize
        WorkAreaEnforcer.shared.configure(
            isEnabled: settings.enableAXNudger,
            barHeight: CGFloat(settings.barHeight),
            screens: []
        )
        
        // Initialize multi-screen manager
        let screenManager = ScreenManager(settingsStore: settingsStore, store: store)
        self.screenManager = screenManager
        
        // Update WorkAreaEnforcer with initialized screen descriptors
        WorkAreaEnforcer.shared.updateScreens(screenManager.screenDescriptors())
        
        // Initialize AppTracker for live window tracking
        let appTracker = AppTracker(store: store)
        appTracker.onWindowsChanged = { [weak self] in
            self?.screenManager?.updateWindows()
        }
        self.appTracker = appTracker
        
        // Initialize menu bar status item
        let statusMenu = StatusMenu(settingsStore: settingsStore)
        self.statusMenu = statusMenu
        
        // Observe settingsStore for dock restore/hide and autohide delay changes
        setupSettingsSubscriptions()
        
        // Wire action callbacks on statusMenu
        statusMenu.onReloadThemesRequested = { [weak self] in
            ThemeFileLoader.shared.reloadCustomThemes()
            guard let self = self else { return }
            let theme = ThemeRegistry.shared.theme(for: self.settingsStore.settings.activeThemeId)
            let resolvedTheme = self.settingsStore.settings.applyingThemeOverrides(to: theme)
            self.screenManager?.applyTheme(resolvedTheme)
            self.statusMenu?.refresh()
        }
        statusMenu.onOpenThemesFolderRequested = { [weak self] in
            self?.openThemesFolder()
        }
        statusMenu.onExportThemeRequested = { [weak self] in
            self?.exportActiveTheme()
        }
        statusMenu.onLauncherTriggered = { [weak self] in
            guard let self = self else { return }
            Launcher.launch(self.settingsStore.settings.launcherAction)
        }
        statusMenu.onQuitRequested = {
            NSApplication.shared.terminate(nil)
        }
        
        TaskbarLogger.lifecycle.info("Started successfully on \(NSScreen.screens.count) screen(s). Theme: \(self.settingsStore.settings.activeThemeId). Dock: \(self.settingsStore.settings.hideSystemDock ? "Hidden" : "Visible"). Tracking active.")
    }
    
    private func openThemesFolder() {
        let dir = ThemeFileLoader.shared.customThemesDirectory
        try? ThemeFileLoader.shared.createDirectoryIfNeeded()
        NSWorkspace.shared.open(dir)
    }
    
    private func exportActiveTheme() {
        let currentTheme = settingsStore.currentTheme
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
    
    private func setupSettingsSubscriptions() {
        settingsStore.addObserver { old, new in
            if old.hideSystemDock != new.hideSystemDock || old.dockHideDelay != new.dockHideDelay {
                if new.hideSystemDock {
                    DockController.shared.hideDock(delay: new.dockHideDelay)
                } else {
                    DockController.shared.restoreDock()
                }
            }
        }
    }
}

extension ScreenManager {
    public func applyTheme(_ theme: ThemeDefinition) {
        for panel in allPanels {
            panel.applyTheme(theme)
        }
    }
}
