// Sources/TaskbarKit/UI/Menu/StatusMenu.swift

import AppKit
import TaskbarCore

@MainActor
public final class StatusMenu {
    private let statusItem: NSStatusItem
    public var menu: NSMenu? { statusItem.menu }
    public let settingsStore: SettingsStore?
    private var currentStyle: ThemeStyle
    public private(set) var currentThemeId: String
    public private(set) var windowGroupingMode: WindowGroupingMode
    private var minButtonWidth: Double
    private var barHeight: Double
    private var fontSize: Double
    private var iconSize: Double
    private var isNudgerEnabled: Bool
    private var isDockHidden: Bool
    private var dockDelay: Double
    public var onThemeIdChanged: ((String) -> Void)?
    public var onWindowGroupingModeChanged: ((WindowGroupingMode) -> Void)?
    public var onReloadThemesRequested: (() -> Void)?
    public var onReloadThemes: (() -> Void)? {
        get { onReloadThemesRequested }
        set { onReloadThemesRequested = newValue }
    }
    public var onOpenThemesFolderRequested: (() -> Void)?
    public var onExportThemeRequested: (() -> Void)?
    public var onMinButtonWidthChanged: ((Double) -> Void)?
    public var onBarHeightChanged: ((Double) -> Void)?
    public var onFontSizeChanged: ((Double) -> Void)?
    public var onIconSizeChanged: ((Double) -> Void)?
    public var onLauncherTriggered: (() -> Void)?
    public var onNudgerToggled: ((Bool) -> Void)?
    public var onHideDockToggled: ((Bool) -> Void)?
    public var onDockDelayChanged: ((Double) -> Void)?
    public var onRestoreDockRequested: (() -> Void)?
    public var onQuitRequested: (() -> Void)?
    
    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let s = settingsStore.settings
        self.currentStyle = s.themeStyle
        self.currentThemeId = s.activeThemeId
        self.windowGroupingMode = s.windowGroupingMode
        self.minButtonWidth = s.minButtonWidth
        self.barHeight = s.barHeight
        self.fontSize = s.fontSize
        self.iconSize = s.iconSize
        self.isNudgerEnabled = s.enableAXNudger
        self.isDockHidden = s.hideSystemDock
        self.dockDelay = s.dockHideDelay
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        settingsStore.addObserver { [weak self] old, new in
            self?.handleSettingsChanged(old: old, new: new)
        }
        
        setupMenu()
    }
    
    public init(
        currentStyle: ThemeStyle = .modernHybrid,
        currentThemeId: String? = nil,
        windowGroupingMode: WindowGroupingMode = .always,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        barHeight: Double = TaskbarConstants.Layout.defaultBarHeight,
        fontSize: Double = TaskbarConstants.Layout.defaultFontSize,
        iconSize: Double = TaskbarConstants.Layout.defaultIconSize,
        isNudgerEnabled: Bool = true,
        isDockHidden: Bool = true,
        dockDelay: Double = TaskbarConstants.Dock.defaultAutohideDelaySeconds
    ) {
        self.settingsStore = nil
        self.currentStyle = currentStyle
        self.currentThemeId = currentThemeId ?? ThemeDefinition.forStyle(currentStyle).id
        self.windowGroupingMode = windowGroupingMode
        self.minButtonWidth = minButtonWidth
        self.barHeight = barHeight
        self.fontSize = fontSize
        self.iconSize = iconSize
        self.isNudgerEnabled = isNudgerEnabled
        self.isDockHidden = isDockHidden
        self.dockDelay = dockDelay
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        setupMenu()
    }
    
    deinit {
        MainActor.assumeIsolated {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
    
    private func handleSettingsChanged(old: Settings, new: Settings) {
        self.currentStyle = new.themeStyle
        self.currentThemeId = new.activeThemeId
        self.windowGroupingMode = new.windowGroupingMode
        self.minButtonWidth = new.minButtonWidth
        self.barHeight = new.barHeight
        self.fontSize = new.fontSize
        self.iconSize = new.iconSize
        self.isNudgerEnabled = new.enableAXNudger
        self.isDockHidden = new.hideSystemDock
        self.dockDelay = new.dockHideDelay
        setupMenu()
    }
    
    public func updateStyle(_ style: ThemeStyle) {
        self.currentStyle = style
        self.currentThemeId = ThemeDefinition.forStyle(style).id
        setupMenu()
    }
    
    public func updateThemeId(_ themeId: String) {
        self.currentThemeId = themeId
        self.currentStyle = ThemeRegistry.shared.theme(for: themeId).style
        setupMenu()
    }
    
    public func updateWindowGroupingMode(_ mode: WindowGroupingMode) {
        self.windowGroupingMode = mode
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
    
    public func updateFontSize(_ size: Double) {
        self.fontSize = size
        setupMenu()
    }
    
    public func updateIconSize(_ size: Double) {
        self.iconSize = size
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
    
    public func updateDockDelay(_ delay: Double) {
        self.dockDelay = delay
        setupMenu()
    }
    
    public func refresh() {
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
        
        // 1. Built-in Presets
        for theme in ThemeRegistry.shared.builtInThemes {
            let item = NSMenuItem(title: theme.displayName, action: #selector(handleThemeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.id
            item.state = (theme.id == currentThemeId) ? .on : .off
            themeSubmenu.addItem(item)
        }
        
        // 2. Custom Themes Section
        themeSubmenu.addItem(NSMenuItem.separator())
        let customThemes = ThemeRegistry.shared.customThemes
        if customThemes.isEmpty {
            let emptyItem = NSMenuItem(title: TaskbarStrings.Themes.noCustomThemesFound, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            themeSubmenu.addItem(emptyItem)
        } else {
            for theme in customThemes {
                let item = NSMenuItem(title: theme.displayName, action: #selector(handleThemeSelection(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = theme.id
                item.state = (theme.id == currentThemeId) ? .on : .off
                themeSubmenu.addItem(item)
            }
        }
        
        // 3. Theme Disk Actions
        themeSubmenu.addItem(NSMenuItem.separator())
        
        let reloadThemesItem = NSMenuItem(
            title: TaskbarStrings.Themes.reloadThemes,
            action: #selector(handleReloadThemes),
            keyEquivalent: "r"
        )
        reloadThemesItem.target = self
        themeSubmenu.addItem(reloadThemesItem)
        
        let openThemesFolderItem = NSMenuItem(
            title: TaskbarStrings.Themes.openThemesFolder,
            action: #selector(handleOpenThemesFolder),
            keyEquivalent: ""
        )
        openThemesFolderItem.target = self
        themeSubmenu.addItem(openThemesFolderItem)
        
        let exportThemeItem = NSMenuItem(
            title: TaskbarStrings.Themes.exportCurrentTheme,
            action: #selector(handleExportCurrentTheme),
            keyEquivalent: ""
        )
        exportThemeItem.target = self
        themeSubmenu.addItem(exportThemeItem)
        
        let themeParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.themeMenu, action: nil, keyEquivalent: "")
        themeParentItem.submenu = themeSubmenu
        menu.addItem(themeParentItem)
        
        // Window Grouping Menu
        let groupingSubmenu = NSMenu(title: TaskbarStrings.WindowGrouping.menuTitle)
        let groupingModes: [(WindowGroupingMode, String)] = [
            (.always, TaskbarStrings.WindowGrouping.modeAlways),
            (.whenCrowded, TaskbarStrings.WindowGrouping.modeWhenCrowded),
            (.never, TaskbarStrings.WindowGrouping.modeNever)
        ]
        for (mode, title) in groupingModes {
            let item = NSMenuItem(title: title, action: #selector(handleGroupingModeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = (mode == windowGroupingMode) ? .on : .off
            groupingSubmenu.addItem(item)
        }
        let groupingParentItem = NSMenuItem(title: TaskbarStrings.WindowGrouping.menuTitle, action: nil, keyEquivalent: "")
        groupingParentItem.submenu = groupingSubmenu
        menu.addItem(groupingParentItem)
        
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
        
        // Font Size Menu
        let fontSubmenu = NSMenu(title: TaskbarStrings.StatusMenu.fontSizeMenu)
        for preset in TaskbarConstants.Layout.fontSizePresets {
            let item = NSMenuItem(title: preset.title, action: #selector(handleFontSizeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.size
            item.state = (abs(preset.size - fontSize) < 0.5) ? .on : .off
            fontSubmenu.addItem(item)
        }
        let fontParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.fontSizeMenu, action: nil, keyEquivalent: "")
        fontParentItem.submenu = fontSubmenu
        menu.addItem(fontParentItem)
        
        // Icon Size Menu
        let iconSubmenu = NSMenu(title: TaskbarStrings.StatusMenu.iconSizeMenu)
        for preset in TaskbarConstants.Layout.iconSizePresets {
            let item = NSMenuItem(title: preset.title, action: #selector(handleIconSizeSelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.size
            item.state = (abs(preset.size - iconSize) < 0.5) ? .on : .off
            iconSubmenu.addItem(item)
        }
        let iconParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.iconSizeMenu, action: nil, keyEquivalent: "")
        iconParentItem.submenu = iconSubmenu
        menu.addItem(iconParentItem)
        
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
        
        let dockDelaySubmenu = NSMenu(title: TaskbarStrings.StatusMenu.dockDelayMenu)
        for preset in TaskbarConstants.Dock.dockDelayPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(handleDockDelaySelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.delay
            item.state = (abs(preset.delay - dockDelay) < 0.1) ? .on : .off
            item.isEnabled = isDockHidden
            dockDelaySubmenu.addItem(item)
        }
        let dockDelayParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.dockDelayMenu, action: nil, keyEquivalent: "")
        dockDelayParentItem.submenu = dockDelaySubmenu
        dockDelayParentItem.isEnabled = isDockHidden
        menu.addItem(dockDelayParentItem)
        
        let restoreDockItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.restoreSystemDock,
            action: #selector(handleRestoreDock),
            keyEquivalent: ""
        )
        restoreDockItem.target = self
        restoreDockItem.isEnabled = isDockHidden
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
        if let themeId = sender.representedObject as? String {
            self.currentThemeId = themeId
            let theme = ThemeRegistry.shared.theme(for: themeId)
            self.currentStyle = theme.style
            setupMenu()
            settingsStore?.update { $0.activeThemeId = themeId }
            onThemeIdChanged?(themeId)
        } else if let style = sender.representedObject as? ThemeStyle {
            self.currentStyle = style
            let theme = ThemeDefinition.forStyle(style)
            self.currentThemeId = theme.id
            setupMenu()
            settingsStore?.update {
                $0.themeStyle = style
                $0.activeThemeId = theme.id
            }
            onThemeIdChanged?(theme.id)
        }
    }
    
    @objc private func handleReloadThemes() {
        onReloadThemesRequested?()
    }
    
    @objc private func handleOpenThemesFolder() {
        onOpenThemesFolderRequested?()
    }
    
    @objc private func handleExportCurrentTheme() {
        onExportThemeRequested?()
    }
    
    @objc private func handleGroupingModeSelection(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? WindowGroupingMode {
            self.windowGroupingMode = mode
            setupMenu()
            settingsStore?.update { $0.windowGroupingMode = mode }
            onWindowGroupingModeChanged?(mode)
        }
    }
    
    @objc private func handleWidthSelection(_ sender: NSMenuItem) {
        if let width = sender.representedObject as? Double {
            minButtonWidth = width
            setupMenu()
            settingsStore?.update { $0.minButtonWidth = width }
            onMinButtonWidthChanged?(width)
        }
    }
    
    @objc private func handleHeightSelection(_ sender: NSMenuItem) {
        if let height = sender.representedObject as? Double {
            barHeight = height
            setupMenu()
            settingsStore?.update { $0.barHeight = height }
            onBarHeightChanged?(height)
        }
    }
    
    @objc private func handleFontSizeSelection(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? Double {
            fontSize = size
            setupMenu()
            settingsStore?.update { $0.fontSize = size }
            onFontSizeChanged?(size)
        }
    }
    
    @objc private func handleIconSizeSelection(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? Double {
            iconSize = size
            setupMenu()
            settingsStore?.update { $0.iconSize = size }
            onIconSizeChanged?(size)
        }
    }
    
    @objc private func handleOpenLauncher() {
        onLauncherTriggered?()
    }
    
    @objc private func handleToggleNudger() {
        isNudgerEnabled.toggle()
        setupMenu()
        settingsStore?.update { $0.enableAXNudger = self.isNudgerEnabled }
        onNudgerToggled?(isNudgerEnabled)
    }
    
    @objc private func handleToggleHideDock() {
        isDockHidden.toggle()
        setupMenu()
        settingsStore?.update { $0.hideSystemDock = self.isDockHidden }
        onHideDockToggled?(isDockHidden)
    }
    
    @objc private func handleDockDelaySelection(_ sender: NSMenuItem) {
        if let delay = sender.representedObject as? Double {
            dockDelay = delay
            setupMenu()
            settingsStore?.update { $0.dockHideDelay = delay }
        }
    }
    
    @objc private func handleRestoreDock() {
        isDockHidden = false
        setupMenu()
        settingsStore?.update { $0.hideSystemDock = false }
    }
    
    @objc private func handleQuit() {
        onQuitRequested?()
    }
}
