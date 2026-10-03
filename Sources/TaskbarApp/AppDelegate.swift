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
            print("[\(BuildConfiguration.appName)] Accessibility permission not granted yet. Prompting user...")
            AccessibilityPermission.promptIfNecessary()
        }
        
        // Hide macOS System Dock if enabled in settings
        if settings.hideSystemDock {
            DockController.shared.hideDock()
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
            isNudgerEnabled: settings.enableAXNudger,
            isDockHidden: settings.hideSystemDock
        )
        statusMenu.onThemeChanged = { [weak self] newStyle in
            guard let self = self else { return }
            self.settings.themeStyle = newStyle
            self.settings.save()
            self.screenManager?.updateThemeStyle(newStyle)
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
                DockController.shared.hideDock()
            } else {
                DockController.shared.restoreDock()
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
        
        print("[\(BuildConfiguration.appName)] Started successfully on \(NSScreen.screens.count) screen(s). Theme: \(settings.themeStyle.displayName). Dock: \(settings.hideSystemDock ? "Hidden" : "Visible"). Tracking active.")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        // Guaranteed restoration of native macOS Dock on quit
        DockController.restoreDockSync()
        screenManager?.closeAll()
        print("[\(BuildConfiguration.appName)] Terminated cleanly.")
    }
}
