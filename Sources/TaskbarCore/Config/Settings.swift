// Sources/TaskbarCore/Config/Settings.swift

import Foundation

public enum ThemeStyle: String, Codable, Sendable, CaseIterable {
    case modernHybrid
    case retroClassic
    
    public var displayName: String {
        switch self {
        case .modernHybrid: return TaskbarStrings.Themes.modernHybrid
        case .retroClassic: return TaskbarStrings.Themes.retroClassic
        }
    }
}

public enum LauncherAction: Codable, Sendable, Equatable {
    case spotlight
    case raycast
    case customPath(String)
}

public struct Settings: Codable, Sendable, Equatable {
    public var activeThemeId: String
    
    public var themeStyle: ThemeStyle {
        get {
            if activeThemeId == ThemeDefinition.retroClassic.id {
                return .retroClassic
            }
            return .modernHybrid
        }
        set {
            switch newValue {
            case .modernHybrid: activeThemeId = ThemeDefinition.modernHybrid.id
            case .retroClassic: activeThemeId = ThemeDefinition.retroClassic.id
            }
        }
    }
    
    public var currentTheme: ThemeDefinition {
        ThemeRegistry.shared.theme(for: activeThemeId)
    }
    
    public var barHeight: Double
    public var maxButtonWidth: Double
    public var minButtonWidth: Double
    public var buttonSpacing: Double
    public var titleVisibilityThreshold: Double
    public var fontSize: Double
    public var iconSize: Double
    public var launcherAction: LauncherAction
    public var enableAXNudger: Bool
    public var hideSystemDock: Bool
    public var dockHideDelay: Double
    
    public static let `default` = Settings(
        activeThemeId: ThemeDefinition.modernHybrid.id,
        barHeight: TaskbarConstants.Layout.defaultBarHeight,
        maxButtonWidth: TaskbarConstants.Layout.defaultMaxButtonWidth,
        minButtonWidth: TaskbarConstants.Layout.defaultMinButtonWidth,
        buttonSpacing: TaskbarConstants.Layout.defaultButtonSpacing,
        titleVisibilityThreshold: TaskbarConstants.Layout.defaultTitleVisibilityThreshold,
        fontSize: TaskbarConstants.Layout.defaultFontSize,
        iconSize: TaskbarConstants.Layout.defaultIconSize,
        launcherAction: .spotlight,
        enableAXNudger: true,
        hideSystemDock: true,
        dockHideDelay: TaskbarConstants.Dock.defaultAutohideDelaySeconds
    )
    
    public init(
        activeThemeId: String = ThemeDefinition.modernHybrid.id,
        barHeight: Double = TaskbarConstants.Layout.defaultBarHeight,
        maxButtonWidth: Double = TaskbarConstants.Layout.defaultMaxButtonWidth,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing,
        titleVisibilityThreshold: Double = TaskbarConstants.Layout.defaultTitleVisibilityThreshold,
        fontSize: Double = TaskbarConstants.Layout.defaultFontSize,
        iconSize: Double = TaskbarConstants.Layout.defaultIconSize,
        launcherAction: LauncherAction = .spotlight,
        enableAXNudger: Bool = true,
        hideSystemDock: Bool = true,
        dockHideDelay: Double = TaskbarConstants.Dock.defaultAutohideDelaySeconds
    ) {
        self.activeThemeId = activeThemeId
        self.barHeight = barHeight
        self.maxButtonWidth = maxButtonWidth
        self.minButtonWidth = minButtonWidth
        self.buttonSpacing = buttonSpacing
        self.titleVisibilityThreshold = titleVisibilityThreshold
        self.fontSize = fontSize
        self.iconSize = iconSize
        self.launcherAction = launcherAction
        self.enableAXNudger = enableAXNudger
        self.hideSystemDock = hideSystemDock
        self.dockHideDelay = dockHideDelay
    }
    
    public init(
        themeStyle: ThemeStyle,
        barHeight: Double = TaskbarConstants.Layout.defaultBarHeight,
        maxButtonWidth: Double = TaskbarConstants.Layout.defaultMaxButtonWidth,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing,
        titleVisibilityThreshold: Double = TaskbarConstants.Layout.defaultTitleVisibilityThreshold,
        fontSize: Double = TaskbarConstants.Layout.defaultFontSize,
        iconSize: Double = TaskbarConstants.Layout.defaultIconSize,
        launcherAction: LauncherAction = .spotlight,
        enableAXNudger: Bool = true,
        hideSystemDock: Bool = true,
        dockHideDelay: Double = TaskbarConstants.Dock.defaultAutohideDelaySeconds
    ) {
        self.init(
            activeThemeId: (themeStyle == .retroClassic) ? ThemeDefinition.retroClassic.id : ThemeDefinition.modernHybrid.id,
            barHeight: barHeight,
            maxButtonWidth: maxButtonWidth,
            minButtonWidth: minButtonWidth,
            buttonSpacing: buttonSpacing,
            titleVisibilityThreshold: titleVisibilityThreshold,
            fontSize: fontSize,
            iconSize: iconSize,
            launcherAction: launcherAction,
            enableAXNudger: enableAXNudger,
            hideSystemDock: hideSystemDock,
            dockHideDelay: dockHideDelay
        )
    }
    
    private enum CodingKeys: String, CodingKey {
        case activeThemeId, themeStyle, barHeight, maxButtonWidth, minButtonWidth
        case buttonSpacing, titleVisibilityThreshold, fontSize, iconSize
        case launcherAction, enableAXNudger, hideSystemDock, dockHideDelay
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let themeId = try container.decodeIfPresent(String.self, forKey: .activeThemeId) {
            self.activeThemeId = themeId
        } else if let style = try container.decodeIfPresent(ThemeStyle.self, forKey: .themeStyle) {
            self.activeThemeId = (style == .retroClassic) ? ThemeDefinition.retroClassic.id : ThemeDefinition.modernHybrid.id
        } else {
            self.activeThemeId = ThemeDefinition.modernHybrid.id
        }
        self.barHeight = try container.decodeIfPresent(Double.self, forKey: .barHeight) ?? TaskbarConstants.Layout.defaultBarHeight
        self.maxButtonWidth = try container.decodeIfPresent(Double.self, forKey: .maxButtonWidth) ?? TaskbarConstants.Layout.defaultMaxButtonWidth
        self.minButtonWidth = try container.decodeIfPresent(Double.self, forKey: .minButtonWidth) ?? TaskbarConstants.Layout.defaultMinButtonWidth
        self.buttonSpacing = try container.decodeIfPresent(Double.self, forKey: .buttonSpacing) ?? TaskbarConstants.Layout.defaultButtonSpacing
        self.titleVisibilityThreshold = try container.decodeIfPresent(Double.self, forKey: .titleVisibilityThreshold) ?? TaskbarConstants.Layout.defaultTitleVisibilityThreshold
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? TaskbarConstants.Layout.defaultFontSize
        self.iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? TaskbarConstants.Layout.defaultIconSize
        self.launcherAction = try container.decodeIfPresent(LauncherAction.self, forKey: .launcherAction) ?? .spotlight
        self.enableAXNudger = try container.decodeIfPresent(Bool.self, forKey: .enableAXNudger) ?? true
        self.hideSystemDock = try container.decodeIfPresent(Bool.self, forKey: .hideSystemDock) ?? true
        self.dockHideDelay = try container.decodeIfPresent(Double.self, forKey: .dockHideDelay) ?? TaskbarConstants.Dock.defaultAutohideDelaySeconds
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeThemeId, forKey: .activeThemeId)
        try container.encode(themeStyle, forKey: .themeStyle)
        try container.encode(barHeight, forKey: .barHeight)
        try container.encode(maxButtonWidth, forKey: .maxButtonWidth)
        try container.encode(minButtonWidth, forKey: .minButtonWidth)
        try container.encode(buttonSpacing, forKey: .buttonSpacing)
        try container.encode(titleVisibilityThreshold, forKey: .titleVisibilityThreshold)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(iconSize, forKey: .iconSize)
        try container.encode(launcherAction, forKey: .launcherAction)
        try container.encode(enableAXNudger, forKey: .enableAXNudger)
        try container.encode(hideSystemDock, forKey: .hideSystemDock)
        try container.encode(dockHideDelay, forKey: .dockHideDelay)
    }
    
    private static let userDefaultsKey = "com.taskbar.settings"
    
    public static func load(from defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .default
        }
        return settings
    }
    
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
