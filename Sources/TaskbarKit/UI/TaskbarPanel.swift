// Sources/TaskbarApp/UI/TaskbarPanel.swift

import AppKit
import TaskbarCore

public final class TaskbarPanel: NSPanel {
    public let screenID: CGDirectDisplayID
    public let taskbarView: TaskbarView
    
    public init(
        screen: NSScreen,
        height: CGFloat,
        theme: ThemeDefinition,
        launcherAction: LauncherAction,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        maxButtonWidth: Double = TaskbarConstants.Layout.defaultMaxButtonWidth,
        buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing,
        titleVisibilityThreshold: Double = TaskbarConstants.Layout.defaultTitleVisibilityThreshold,
        pinnedApps: [PinnedApp] = [],
        store: WindowStore? = nil
    ) {
        // Resolve display ID
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        self.screenID = displayID
        
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: height
        )
        
        self.taskbarView = TaskbarView(
            theme: theme,
            launcherAction: launcherAction,
            minButtonWidth: minButtonWidth,
            maxButtonWidth: maxButtonWidth,
            buttonSpacing: buttonSpacing,
            titleVisibilityThreshold: titleVisibilityThreshold,
            pinnedApps: pinnedApps,
            store: store
        )
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.contentView = taskbarView
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        
        // Participate in all regular desktop spaces, but exclude from native full-screen presentation
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
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
        taskbarView.needsLayout = true
    }
    
    public func applyTheme(_ theme: ThemeDefinition) {
        self.isOpaque = !theme.useTranslucency
        self.backgroundColor = theme.useTranslucency ? .clear : NSColor(rgba: theme.backgroundColor)
        taskbarView.theme = theme
    }
    
    public var currentMaterial: NSVisualEffectView.Material {
        taskbarView.currentMaterial
    }
    
    public var currentBlendingMode: NSVisualEffectView.BlendingMode {
        taskbarView.currentBlendingMode
    }
    
    public func updateButtonWidths(minWidth: Double, maxWidth: Double) {
        taskbarView.minButtonWidth = minWidth
        taskbarView.maxButtonWidth = maxWidth
    }
    
    public func updateButtonLayout(
        minWidth: Double,
        maxWidth: Double,
        spacing: Double,
        titleThreshold: Double
    ) {
        taskbarView.minButtonWidth = minWidth
        taskbarView.maxButtonWidth = maxWidth
        taskbarView.buttonSpacing = spacing
        taskbarView.titleVisibilityThreshold = titleThreshold
    }
    
    public func updatePinnedApps(_ apps: [PinnedApp], runningBundleIDs: Set<String>? = nil) {
        taskbarView.updatePinnedApps(apps, runningBundleIDs: runningBundleIDs)
    }
}
