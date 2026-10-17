// Sources/TaskbarKit/UI/Menu/StatusMenu.swift

import AppKit
import TaskbarCore

@MainActor
public final class StatusMenu {
    private let statusItem: NSStatusItem
    public var menu: NSMenu? { statusItem.menu }
    public let settingsStore: SettingsStore
    public var currentThemeId: String { settingsStore.settings.activeThemeId }
    public var windowGroupingMode: WindowGroupingMode { settingsStore.settings.windowGroupingMode }
    
    public var onThemeIdChanged: ((String) -> Void)?
    public var onWindowGroupingModeChanged: ((WindowGroupingMode) -> Void)?
    public var onReloadThemesRequested: (() -> Void)?
    public var onReloadThemes: (() -> Void)? {
        get { onReloadThemesRequested }
        set { onReloadThemesRequested = newValue }
    }
    public var onOpenThemesFolderRequested: (() -> Void)?
    public var onExportThemeRequested: (() -> Void)?
    public var onLauncherTriggered: (() -> Void)?
    public var onQuitRequested: (() -> Void)?
    
    public init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        settingsStore.addObserver { [weak self] _, _ in
            self?.setupMenu()
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
        var initial = Settings.default
        initial.themeStyle = currentStyle
        initial.activeThemeId = currentThemeId ?? ThemeDefinition.forStyle(currentStyle).id
        initial.windowGroupingMode = windowGroupingMode
        initial.minButtonWidth = minButtonWidth
        initial.barHeight = barHeight
        initial.fontSize = fontSize
        initial.iconSize = iconSize
        initial.enableAXNudger = isNudgerEnabled
        initial.hideSystemDock = isDockHidden
        initial.dockHideDelay = dockDelay
        
        let store = SettingsStore(
            persistence: InMemorySettingsPersistence(initial: initial),
            initialSettings: initial
        )
        self.settingsStore = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        store.addObserver { [weak self] _, _ in
            self?.setupMenu()
        }
        
        setupMenu()
    }
    
    deinit {
        MainActor.assumeIsolated {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
    
    public func updateWindowGroupingMode(_ mode: WindowGroupingMode) {
        settingsStore.update { $0.windowGroupingMode = mode }
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
            item.state = (abs(preset.height - settingsStore.settings.barHeight) < 1.0) ? .on : .off
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
            item.state = (abs(preset.width - settingsStore.settings.minButtonWidth) < 1.0) ? .on : .off
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
            item.state = (abs(preset.size - settingsStore.settings.fontSize) < 0.5) ? .on : .off
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
            item.state = (abs(preset.size - settingsStore.settings.iconSize) < 0.5) ? .on : .off
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
        nudgerItem.state = settingsStore.settings.enableAXNudger ? .on : .off
        menu.addItem(nudgerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // macOS System Dock controls
        let hideDockItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.hideSystemDock,
            action: #selector(handleToggleHideDock),
            keyEquivalent: ""
        )
        hideDockItem.target = self
        hideDockItem.state = settingsStore.settings.hideSystemDock ? .on : .off
        menu.addItem(hideDockItem)
        
        let dockDelaySubmenu = NSMenu(title: TaskbarStrings.StatusMenu.dockDelayMenu)
        for preset in TaskbarConstants.Dock.dockDelayPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(handleDockDelaySelection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.delay
            item.state = (abs(preset.delay - settingsStore.settings.dockHideDelay) < 0.1) ? .on : .off
            item.isEnabled = settingsStore.settings.hideSystemDock
            dockDelaySubmenu.addItem(item)
        }
        let dockDelayParentItem = NSMenuItem(title: TaskbarStrings.StatusMenu.dockDelayMenu, action: nil, keyEquivalent: "")
        dockDelayParentItem.submenu = dockDelaySubmenu
        dockDelayParentItem.isEnabled = settingsStore.settings.hideSystemDock
        menu.addItem(dockDelayParentItem)
        
        let restoreDockItem = NSMenuItem(
            title: TaskbarStrings.StatusMenu.restoreSystemDock,
            action: #selector(handleRestoreDock),
            keyEquivalent: ""
        )
        restoreDockItem.target = self
        restoreDockItem.isEnabled = settingsStore.settings.hideSystemDock
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
            settingsStore.update { $0.activeThemeId = themeId }
            onThemeIdChanged?(themeId)
        } else if let style = sender.representedObject as? ThemeStyle {
            let theme = ThemeDefinition.forStyle(style)
            settingsStore.update {
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
            settingsStore.update { $0.windowGroupingMode = mode }
            onWindowGroupingModeChanged?(mode)
        }
    }
    
    @objc private func handleWidthSelection(_ sender: NSMenuItem) {
        if let width = sender.representedObject as? Double {
            settingsStore.update { $0.minButtonWidth = width }
        }
    }
    
    @objc private func handleHeightSelection(_ sender: NSMenuItem) {
        if let height = sender.representedObject as? Double {
            settingsStore.update { $0.barHeight = height }
        }
    }
    
    @objc private func handleFontSizeSelection(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? Double {
            settingsStore.update { $0.fontSize = size }
        }
    }
    
    @objc private func handleIconSizeSelection(_ sender: NSMenuItem) {
        if let size = sender.representedObject as? Double {
            settingsStore.update { $0.iconSize = size }
        }
    }
    
    @objc private func handleOpenLauncher() {
        onLauncherTriggered?()
    }
    
    @objc private func handleToggleNudger() {
        settingsStore.update { $0.enableAXNudger.toggle() }
    }
    
    @objc private func handleToggleHideDock() {
        settingsStore.update { $0.hideSystemDock.toggle() }
    }
    
    @objc private func handleDockDelaySelection(_ sender: NSMenuItem) {
        if let delay = sender.representedObject as? Double {
            settingsStore.update { $0.dockHideDelay = delay }
        }
    }
    
    @objc private func handleRestoreDock() {
        settingsStore.update { $0.hideSystemDock = false }
    }
    
    @objc private func handleQuit() {
        onQuitRequested?()
    }
}
