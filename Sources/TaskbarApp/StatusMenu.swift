// Sources/TaskbarApp/StatusMenu.swift

import AppKit
import TaskbarCore

@MainActor
public final class StatusMenu {
    private let statusItem: NSStatusItem
    private var currentStyle: ThemeStyle
    private var minButtonWidth: Double
    private var isNudgerEnabled: Bool
    private var isDockHidden: Bool
    
    public var onThemeChanged: ((ThemeStyle) -> Void)?
    public var onMinButtonWidthChanged: ((Double) -> Void)?
    public var onLauncherTriggered: (() -> Void)?
    public var onNudgerToggled: ((Bool) -> Void)?
    public var onHideDockToggled: ((Bool) -> Void)?
    public var onRestoreDockRequested: (() -> Void)?
    public var onQuitRequested: (() -> Void)?
    
    public init(
        currentStyle: ThemeStyle,
        minButtonWidth: Double = 80.0,
        isNudgerEnabled: Bool = true,
        isDockHidden: Bool = true
    ) {
        self.currentStyle = currentStyle
        self.minButtonWidth = minButtonWidth
        self.isNudgerEnabled = isNudgerEnabled
        self.isDockHidden = isDockHidden
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        setupMenu()
    }
    
    public func updateStyle(_ style: ThemeStyle) {
        self.currentStyle = style
        setupMenu()
    }
    
    public func updateMinButtonWidth(_ width: Double) {
        self.minButtonWidth = width
        setupMenu()
    }
    
    public func updateNudgerState(_ enabled: Bool) {
        self.isNudgerEnabled = enabled
        setupMenu()
    }
    
    public func updateDockHiddenState(_ hidden: Bool) {
        self.isDockHidden = hidden
        setupMenu()
    }
    
    private func setupMenu() {
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: BuildConfiguration.appName) {
                button.image = image
            } else {
                button.title = "⊞"
            }
        }
        
        let menu = NSMenu()
        
        let headerItem = NSMenuItem(title: "\(BuildConfiguration.appName) v\(BuildConfiguration.appVersion)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        // Theme Menu
        let themeSubmenu = NSMenu(title: "Theme")
        for style in ThemeStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(handleThemeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            item.state = (style == currentStyle) ? .on : .off
            themeSubmenu.addItem(item)
        }
        
        let themeParentItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeParentItem.submenu = themeSubmenu
        menu.addItem(themeParentItem)
        
        // Button Width / Overflow Threshold Menu
        let widthSubmenu = NSMenu(title: "Button Width")
        let presets: [(title: String, width: Double)] = [
            ("80 pt (Default - Balanced)", 80.0),
            ("100 pt (Roomy - Early overflow)", 100.0),
            ("120 pt (Spacious)", 120.0),
            ("60 pt (Compact)", 60.0),
            ("28 pt (Ultra-compact - Icon only)", 28.0)
        ]
        for preset in presets {
            let item = NSMenuItem(title: preset.title, action: #selector(handleWidthSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.width
            item.state = (abs(preset.width - minButtonWidth) < 1.0) ? .on : .off
            widthSubmenu.addItem(item)
        }
        let widthParentItem = NSMenuItem(title: "Button Width", action: nil, keyEquivalent: "")
        widthParentItem.submenu = widthSubmenu
        menu.addItem(widthParentItem)
        
        // Start Launcher item
        let startItem = NSMenuItem(title: "Open Start Launcher", action: #selector(handleOpenLauncher), keyEquivalent: "s")
        startItem.target = self
        menu.addItem(startItem)
        
        // WorkArea Nudger Toggle
        let nudgerItem = NSMenuItem(title: "Nudge Maximized Windows", action: #selector(handleToggleNudger), keyEquivalent: "")
        nudgerItem.target = self
        nudgerItem.state = isNudgerEnabled ? .on : .off
        menu.addItem(nudgerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // macOS System Dock controls
        let hideDockItem = NSMenuItem(title: "Hide macOS System Dock", action: #selector(handleToggleHideDock), keyEquivalent: "")
        hideDockItem.target = self
        hideDockItem.state = isDockHidden ? .on : .off
        menu.addItem(hideDockItem)
        
        let restoreDockItem = NSMenuItem(title: "Restore System Dock Now", action: #selector(handleRestoreDock), keyEquivalent: "")
        restoreDockItem.target = self
        menu.addItem(restoreDockItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit \(BuildConfiguration.appName)", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func handleThemeSelection(_ sender: NSMenuItem) {
        if let style = sender.representedObject as? ThemeStyle {
            currentStyle = style
            setupMenu()
            onThemeChanged?(style)
        }
    }
    
    @objc private func handleWidthSelection(_ sender: NSMenuItem) {
        if let width = sender.representedObject as? Double {
            minButtonWidth = width
            setupMenu()
            onMinButtonWidthChanged?(width)
        }
    }
    
    @objc private func handleOpenLauncher() {
        onLauncherTriggered?()
    }
    
    @objc private func handleToggleNudger() {
        isNudgerEnabled.toggle()
        setupMenu()
        onNudgerToggled?(isNudgerEnabled)
    }
    
    @objc private func handleToggleHideHideDock() {
        // Alias
        handleToggleHideDock()
    }
    
    @objc private func handleToggleHideDock() {
        isDockHidden.toggle()
        setupMenu()
        onHideDockToggled?(isDockHidden)
    }
    
    @objc private func handleRestoreDock() {
        isDockHidden = false
        setupMenu()
        onRestoreDockRequested?()
    }
    
    @objc private func handleQuit() {
        onQuitRequested?()
    }
}
