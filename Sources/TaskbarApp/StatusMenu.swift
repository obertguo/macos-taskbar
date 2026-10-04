// Sources/TaskbarApp/StatusMenu.swift

import AppKit
import TaskbarCore

@MainActor
public final class StatusMenu {
    private let statusItem: NSStatusItem
    private var currentStyle: ThemeStyle
    private var minButtonWidth: Double
    private var barHeight: Double
    private var isNudgerEnabled: Bool
    private var isDockHidden: Bool
    
    public var onThemeChanged: ((ThemeStyle) -> Void)?
    public var onMinButtonWidthChanged: ((Double) -> Void)?
    public var onBarHeightChanged: ((Double) -> Void)?
    public var onLauncherTriggered: (() -> Void)?
    public var onNudgerToggled: ((Bool) -> Void)?
    public var onHideDockToggled: ((Bool) -> Void)?
    public var onRestoreDockRequested: (() -> Void)?
    public var onQuitRequested: (() -> Void)?
    
    public init(
        currentStyle: ThemeStyle,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        barHeight: Double = TaskbarConstants.Layout.defaultBarHeight,
        isNudgerEnabled: Bool = true,
        isDockHidden: Bool = true
    ) {
        self.currentStyle = currentStyle
        self.minButtonWidth = minButtonWidth
        self.barHeight = barHeight
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
    
    public func updateBarHeight(_ height: Double) {
        self.barHeight = height
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
            if let image = NSImage(
                systemSymbolName: TaskbarStrings.StatusMenu.statusBarSymbol,
                accessibilityDescription: BuildConfiguration.appName
            ) {
                button.image = image
            } else {
                button.title = TaskbarStrings.StatusMenu.statusBarFallbackGlyph
            }
        }
        
        let menu = NSMenu()
        
        let headerTitle = TaskbarStrings.StatusMenu.appHeader(
            name: BuildConfiguration.appName,
            version: BuildConfiguration.appVersion
        )
        let headerItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        // Theme Menu
        let themeSubmenu = NSMenu(title: TaskbarStrings.StatusMenu.themeMenu)
        for style in ThemeStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(handleThemeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            item.state = (style == currentStyle) ? .on : .off
            themeSubmenu.addItem(item)
        }
        
        let themeParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.themeMenu, action: nil, keyEquivalent: "")
        themeParentItem.submenu = themeSubmenu
        menu.addItem(themeParentItem)
        
        // Button Width / Overflow Threshold Menu
        let widthSubmenu = NSMenu(title: TaskbarStrings.StatusMenu.buttonWidthMenu)
        for preset in TaskbarConstants.Layout.buttonWidthPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(handleWidthSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.width
            item.state = (abs(preset.width - minButtonWidth) < 1.0) ? .on : .off
            widthSubmenu.addItem(item)
        }
        let widthParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.buttonWidthMenu, action: nil, keyEquivalent: "")
        widthParentItem.submenu = widthSubmenu
        menu.addItem(widthParentItem)
        
        // Taskbar Height Menu
        let heightSubmenu = NSMenu(title: TaskbarStrings.StatusMenu.barHeightMenu)
        for preset in TaskbarConstants.Layout.barHeightPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(handleHeightSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.height
            item.state = (abs(preset.height - barHeight) < 1.0) ? .on : .off
            heightSubmenu.addItem(item)
        }
        let heightParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.barHeightMenu, action: nil, keyEquivalent: "")
        heightParentItem.submenu = heightSubmenu
        menu.addItem(heightParentItem)
        
        // Start Launcher item
        let startItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.openStartLauncher,
            action: #selector(handleOpenLauncher),
            keyEquivalent: "s"
        )
        startItem.target = self
        menu.addItem(startItem)
        
        // WorkArea Nudger Toggle
        let nudgerItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.nudgeMaximizedWindows,
            action: #selector(handleToggleNudger),
            keyEquivalent: ""
        )
        nudgerItem.target = self
        nudgerItem.state = isNudgerEnabled ? .on : .off
        menu.addItem(nudgerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // macOS System Dock controls
        let hideDockItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.hideSystemDock,
            action: #selector(handleToggleHideDock),
            keyEquivalent: ""
        )
        hideDockItem.target = self
        hideDockItem.state = isDockHidden ? .on : .off
        menu.addItem(hideDockItem)
        
        let restoreDockItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.restoreSystemDock,
            action: #selector(handleRestoreDock),
            keyEquivalent: ""
        )
        restoreDockItem.target = self
        menu.addItem(restoreDockItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.quitApp(name: BuildConfiguration.appName),
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
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
    
    @objc private func handleHeightSelection(_ sender: NSMenuItem) {
        if let height = sender.representedObject as? Double {
            barHeight = height
            setupMenu()
            onBarHeightChanged?(height)
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
