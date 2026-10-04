// Sources/TaskbarCore/Config/Settings.swift

import Foundation

public enum ThemeStyle: String, Codable, Sendable, CaseIterable {
    case modernHybrid
    case retroClassic
    
    public var displayName: String {
        switch self {
        case .modernHybrid: return "Modern Hybrid"
        case .retroClassic: return "Retro Classic"
        }
    }
}

public enum LauncherAction: Codable, Sendable, Equatable {
    case spotlight
    case raycast
    case customPath(String)
}

public struct Settings: Codable, Sendable, Equatable {
    public var themeStyle: ThemeStyle
    public var barHeight: Double
    public var maxButtonWidth: Double
    public var minButtonWidth: Double
    public var launcherAction: LauncherAction
    public var enableAXNudger: Bool
    public var hideSystemDock: Bool
    
    public static let `default` = Settings(
        themeStyle: .modernHybrid,
        barHeight: 30.0,
        maxButtonWidth: 160.0,
        minButtonWidth: 80.0,
        launcherAction: .spotlight,
        enableAXNudger: true,
        hideSystemDock: true
    )
    
    public init(
        themeStyle: ThemeStyle = .modernHybrid,
        barHeight: Double = 30.0,
        maxButtonWidth: Double = 160.0,
        minButtonWidth: Double = 80.0,
        launcherAction: LauncherAction = .spotlight,
        enableAXNudger: Bool = true,
        hideSystemDock: Bool = true
    ) {
        self.themeStyle = themeStyle
        self.barHeight = barHeight
        self.maxButtonWidth = maxButtonWidth
        self.minButtonWidth = minButtonWidth
        self.launcherAction = launcherAction
        self.enableAXNudger = enableAXNudger
        self.hideSystemDock = hideSystemDock
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
