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
        self.currentTheme = ThemeRegistry.shared.theme(for: settings.activeThemeId).withCustomMetrics(
            fontSize: settings.fontSize,
            iconSize: settings.iconSize
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
        self.currentTheme = ThemeRegistry.shared.theme(for: newSettings.activeThemeId).withCustomMetrics(
            fontSize: newSettings.fontSize,
            iconSize: newSettings.iconSize
        )
        
        WorkAreaEnforcer.shared.barHeight = CGFloat(newSettings.barHeight)
        WorkAreaEnforcer.shared.isEnabled = newSettings.enableAXNudger
        
        for panel in panels.values {
            panel.applyTheme(currentTheme)
            panel.updateButtonLayout(
                minWidth: newSettings.minButtonWidth,
                maxWidth: newSettings.maxButtonWidth,
                spacing: newSettings.buttonSpacing,
                titleThreshold: newSettings.titleVisibilityThreshold
            )
        }
        
        refreshPanels()
    }
    
    public func updateBarHeight(_ barHeight: Double) {
        settings.barHeight = barHeight
        settings.save()
        WorkAreaEnforcer.shared.barHeight = CGFloat(barHeight)
        refreshPanels()
    }
    
    public func updateMinButtonWidth(_ minWidth: Double) {
        settings.minButtonWidth = minWidth
        settings.save()
        
        for panel in panels.values {
            panel.updateButtonWidths(minWidth: minWidth, maxWidth: settings.maxButtonWidth)
        }
    }
    
    public func updateFontSize(_ fontSize: Double) {
        settings.fontSize = fontSize
        settings.save()
        currentTheme = currentTheme.withCustomMetrics(
            fontSize: fontSize,
            iconSize: settings.iconSize
        )
        for panel in panels.values {
            panel.applyTheme(currentTheme)
        }
    }
    
    public func updateIconSize(_ iconSize: Double) {
        settings.iconSize = iconSize
        settings.save()
        currentTheme = currentTheme.withCustomMetrics(
            fontSize: settings.fontSize,
            iconSize: iconSize
        )
        for panel in panels.values {
            panel.applyTheme(currentTheme)
        }
    }
    
    public func updateTheme(themeId: String) {
        settings.activeThemeId = themeId
        settings.save()
        currentTheme = ThemeRegistry.shared.theme(for: themeId).withCustomMetrics(
            fontSize: settings.fontSize,
            iconSize: settings.iconSize
        )
        for panel in panels.values {
            panel.applyTheme(currentTheme)
        }
    }
    
    public func updateThemeStyle(_ style: ThemeStyle) {
        updateTheme(themeId: ThemeDefinition.forStyle(style).id)
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
                    maxButtonWidth: settings.maxButtonWidth,
                    buttonSpacing: settings.buttonSpacing,
                    titleVisibilityThreshold: settings.titleVisibilityThreshold
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
