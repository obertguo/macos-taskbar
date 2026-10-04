// Sources/TaskbarApp/UI/ScreenManager.swift

import AppKit
import TaskbarCore

@MainActor
public final class ScreenManager {
    private var panels: [CGDirectDisplayID: TaskbarPanel] = [:]
    private var settings: Settings
    private var currentTheme: ThemeDefinition
    public let store: WindowStore
    
    public init(settings: Settings, store: WindowStore) {
        self.settings = settings
        self.store = store
        self.currentTheme = ThemeDefinition.forStyle(settings.themeStyle)
        
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
        
        refreshPanels()
    }
    
    public func screenDescriptors() -> [ScreenDescriptor] {
        NSScreen.screens.map { screen in
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
            let isPrimary = (screen == NSScreen.screens.first)
            let frame = displayID != 0 ? CGDisplayBounds(displayID) : screen.frame
            return ScreenDescriptor(id: UInt32(displayID), frame: frame, isPrimary: isPrimary)
        }
    }
    
    public func updateSettings(_ newSettings: Settings) {
        self.settings = newSettings
        self.currentTheme = ThemeDefinition.forStyle(newSettings.themeStyle)
        
        WorkAreaEnforcer.shared.barHeight = CGFloat(newSettings.barHeight)
        WorkAreaEnforcer.shared.isEnabled = newSettings.enableAXNudger
        
        for panel in panels.values {
            panel.applyTheme(currentTheme)
            panel.updateButtonWidths(minWidth: newSettings.minButtonWidth, maxWidth: newSettings.maxButtonWidth)
        }
        
        refreshPanels()
    }
    
    public func updateMinButtonWidth(_ minWidth: Double) {
        settings.minButtonWidth = minWidth
        settings.save()
        
        for panel in panels.values {
            panel.updateButtonWidths(minWidth: minWidth, maxWidth: settings.maxButtonWidth)
        }
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
    
    @objc private func handleActiveSpaceChanged() {
        updateWindows()
    }
    
    /// Determines whether the active space on a physical display is currently showing a native full-screen app.
    private func isScreenInFullScreen(screen: NSScreen) -> Bool {
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
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
            if abs(winFrame.minX - screenBounds.minX) <= 2.0 &&
               abs(winFrame.minY - screenBounds.minY) <= 2.0 &&
               abs(winFrame.width - screenBounds.width) <= 2.0 &&
               abs(winFrame.height - screenBounds.height) <= 2.0 {
                return true
            }
        }
        return false
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
                    launcherAction: settings.launcherAction,
                    minButtonWidth: settings.minButtonWidth,
                    maxButtonWidth: settings.maxButtonWidth
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
        
        WorkAreaEnforcer.shared.updateScreens(screenDescriptors())
        updateWindows()
    }
    
    public func updateWindows() {
        let descriptors = screenDescriptors()
        let screens = NSScreen.screens
        
        for (displayID, panel) in panels {
            guard let screen = screens.first(where: {
                ((($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0) == displayID)
            }) else { continue }
            
            let screenWindows = store.windows(forScreenID: UInt32(displayID), screens: descriptors)
            let isFullScreen = isScreenInFullScreen(screen: screen)
            
            if isFullScreen {
                if panel.isVisible {
                    panel.orderOut(nil)
                }
            } else {
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                }
            }
            
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
}
