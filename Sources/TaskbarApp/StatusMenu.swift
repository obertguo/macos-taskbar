// Sources/TaskbarApp/StatusMenu.swift

import AppKit
import TaskbarCore

@MainActor
public final class StatusMenu {
    private let statusItem: NSStatusItem
    private var currentStyle: ThemeStyle
    private var isNudgerEnabled: Bool
    
    public var onThemeChanged: ((ThemeStyle) -> Void)?
    public var onLauncherTriggered: (() -> Void)?
    public var onNudgerToggled: ((Bool) -> Void)?
    public var onQuitRequested: (() -> Void)?
    
    public init(currentStyle: ThemeStyle, isNudgerEnabled: Bool = true) {
        self.currentStyle = currentStyle
        self.isNudgerEnabled = isNudgerEnabled
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        setupMenu()
    }
    
    public func updateStyle(_ style: ThemeStyle) {
        self.currentStyle = style
        setupMenu()
    }
    
    public func updateNudgerState(_ enabled: Bool) {
        self.isNudgerEnabled = enabled
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
    
    @objc private func handleOpenLauncher() {
        onLauncherTriggered?()
    }
    
    @objc private func handleToggleNudger() {
        isNudgerEnabled.toggle()
        setupMenu()
        onNudgerToggled?(isNudgerEnabled)
    }
    
    @objc private func handleQuit() {
        onQuitRequested?()
    }
}
