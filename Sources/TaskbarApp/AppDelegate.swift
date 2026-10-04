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
        statusMenu.onThemeChanged = { [weak self] newStyle in
            guard let self = self else { return }
            self.settings.themeStyle = newStyle
            self.settings.save()
            self.screenManager?.updateThemeStyle(newStyle)
        }
        statusMenu.onThemeIdChanged = { [weak self] themeId in
            guard let self = self else { return }
            self.settings.activeThemeId = themeId
            self.settings.save()
            self.screenManager?.updateTheme(themeId: themeId)
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
    
    public func applicationWillTerminate(_ notification: Notification) {
        // Guaranteed restoration of native macOS Dock on quit
        DockController.restoreDockSync()
        screenManager?.closeAll()
        TaskbarLogger.lifecycle.info("Terminated cleanly.")
    }
}
