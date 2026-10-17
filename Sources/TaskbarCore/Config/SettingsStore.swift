// Sources/TaskbarCore/Config/SettingsStore.swift

import Foundation

@MainActor
public final class SettingsStore {
    public private(set) var settings: Settings
    public private(set) var currentTheme: ThemeDefinition
    public let persistence: SettingsPersistence
    private var observers: [(Settings, Settings) -> Void] = []
    
    public init(
        persistence: SettingsPersistence = UserDefaultsSettingsPersistence(),
        initialSettings: Settings? = nil
    ) {
        self.persistence = persistence
        let loaded = initialSettings ?? persistence.load()
        self.settings = loaded
        let baseTheme = ThemeRegistry.shared.theme(for: loaded.activeThemeId)
        self.currentTheme = loaded.applyingThemeOverrides(to: baseTheme)
    }
    
    public func addObserver(_ observer: @escaping (_ old: Settings, _ new: Settings) -> Void) {
        observers.append(observer)
    }
    
    public func update(_ transform: (inout Settings) -> Void) {
        let oldSettings = settings
        var nextSettings = oldSettings
        transform(&nextSettings)
        
        guard nextSettings != oldSettings else { return }
        
        if nextSettings.activeThemeId != oldSettings.activeThemeId {
            let baseTheme = ThemeRegistry.shared.theme(for: nextSettings.activeThemeId)
            nextSettings.updateWithCustomThemeMetrics(from: baseTheme)
        }
        
        let baseTheme = ThemeRegistry.shared.theme(for: nextSettings.activeThemeId)
        self.currentTheme = nextSettings.applyingThemeOverrides(to: baseTheme)
        self.settings = nextSettings
        
        persistence.save(nextSettings)
        
        for observer in observers {
            observer(oldSettings, nextSettings)
        }
    }
    
    public func reloadActiveTheme() {
        let oldSettings = settings
        var nextSettings = settings
        let baseTheme = ThemeRegistry.shared.theme(for: nextSettings.activeThemeId)
        nextSettings.activeThemeId = baseTheme.id
        nextSettings.updateWithCustomThemeMetrics(from: baseTheme)
        
        self.currentTheme = nextSettings.applyingThemeOverrides(to: baseTheme)
        self.settings = nextSettings
        
        persistence.save(nextSettings)
        
        for observer in observers {
            observer(oldSettings, nextSettings)
        }
    }
}
