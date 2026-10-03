// Sources/TaskbarApp/UI/TaskbarPanel.swift

import AppKit
import TaskbarCore

public final class TaskbarPanel: NSPanel {
    public let screenID: CGDirectDisplayID
    public let taskbarView: TaskbarView
    
    public init(screen: NSScreen, height: CGFloat, theme: ThemeDefinition, launcherAction: LauncherAction) {
        // Resolve display ID
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        self.screenID = displayID
        
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: height
        )
        
        self.taskbarView = TaskbarView(theme: theme, launcherAction: launcherAction)
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.contentView = taskbarView
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        
        // Move across regular user desktop spaces, but strictly exclude native full-screen presentation spaces
        self.collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle, .fullScreenNone]
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.hasShadow = false
        self.isOpaque = !theme.useTranslucency
        self.backgroundColor = theme.useTranslucency ? .clear : NSColor(rgba: theme.backgroundColor)
    }
    
    // Never steal key or main focus from foreground apps
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
    
    public func updateLayout(for screen: NSScreen, height: CGFloat) {
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: height
        )
        setFrame(frame, display: true)
    }
    
    public func applyTheme(_ theme: ThemeDefinition) {
        self.isOpaque = !theme.useTranslucency
        self.backgroundColor = theme.useTranslucency ? .clear : NSColor(rgba: theme.backgroundColor)
        taskbarView.theme = theme
    }
}
