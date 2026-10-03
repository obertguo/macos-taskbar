// Sources/TaskbarApp/AppDelegate.swift

import AppKit
import TaskbarCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: Settings!
    private var screenManager: ScreenManager?
    private var statusMenu: StatusMenu?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Load persistent or default settings
        self.settings = Settings.load()
        
        // Initialize multi-screen manager
        let screenManager = ScreenManager(settings: settings)
        self.screenManager = screenManager
        
        // Initialize menu bar status item
        let statusMenu = StatusMenu(currentStyle: settings.themeStyle)
        statusMenu.onThemeChanged = { [weak self] newStyle in
            guard let self = self else { return }
            self.settings.themeStyle = newStyle
            self.settings.save()
            self.screenManager?.updateThemeStyle(newStyle)
        }
        statusMenu.onLauncherTriggered = { [weak self] in
            guard let self = self else { return }
            Launcher.launch(self.settings.launcherAction)
        }
        statusMenu.onQuitRequested = {
            NSApplication.shared.terminate(nil)
        }
        self.statusMenu = statusMenu
        
        print("[\(BuildConfiguration.appName)] Started successfully on \(NSScreen.screens.count) screen(s). Theme: \(settings.themeStyle.displayName).")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        screenManager?.closeAll()
        print("[\(BuildConfiguration.appName)] Terminated cleanly.")
    }
}
