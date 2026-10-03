// Sources/TaskbarApp/UI/ScreenManager.swift

import AppKit
import TaskbarCore

@MainActor
public final class ScreenManager {
    private var panels: [CGDirectDisplayID: TaskbarPanel] = [:]
    private var settings: Settings
    private var currentTheme: ThemeDefinition
    
    public init(settings: Settings) {
        self.settings = settings
        self.currentTheme = ThemeDefinition.forStyle(settings.themeStyle)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        refreshPanels()
    }
    
    public func updateSettings(_ newSettings: Settings) {
        self.settings = newSettings
        self.currentTheme = ThemeDefinition.forStyle(newSettings.themeStyle)
        
        for panel in panels.values {
            panel.applyTheme(currentTheme)
        }
        
        refreshPanels()
    }
    
    public func updateThemeStyle(_ style: ThemeStyle) {
        settings.themeStyle = style
        settings.save()
        currentTheme = ThemeDefinition.forStyle(style)
        
        for panel in panels.values {
            panel.applyTheme(currentTheme)
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        refreshPanels()
    }
    
    public func refreshPanels() {
        let screens = NSScreen.screens
        var activeDisplayIDs = Set<CGDirectDisplayID>()
        
        for screen in screens {
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
            activeDisplayIDs.insert(displayID)
            
            let height = CGFloat(settings.barHeight)
            if let existingPanel = panels[displayID] {
                existingPanel.updateLayout(for: screen, height: height)
                existingPanel.orderFrontRegardless()
            } else {
                let panel = TaskbarPanel(
                    screen: screen,
                    height: height,
                    theme: currentTheme,
                    launcherAction: settings.launcherAction
                )
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
    }
    
    public func closeAll() {
        for panel in panels.values {
            panel.close()
        }
        panels.removeAll()
    }
}
