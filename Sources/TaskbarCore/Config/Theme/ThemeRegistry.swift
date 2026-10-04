// Sources/TaskbarCore/Config/Theme/ThemeRegistry.swift

import Foundation

/// Central registry managing built-in theme presets and user-imported custom JSON themes.
public final class ThemeRegistry: @unchecked Sendable {
    public static let shared = ThemeRegistry()
    
    private let lock = NSLock()
    private var themes: [String: ThemeDefinition] = [:]
    
    public init() {
        registerBuiltIns()
    }
    
    private func registerBuiltIns() {
        register(theme: ThemeDefinition.modernHybrid)
        register(theme: ThemeDefinition.retroClassic)
        register(theme: ThemeDefinition.windowsXPLuna)
        register(theme: ThemeDefinition.darkMinimal)
    }
    
    public func register(theme: ThemeDefinition) {
        lock.withLock {
            themes[theme.id] = theme
        }
    }
    
    public func unregister(themeId: String) {
        lock.withLock {
            // Prevent unregistering built-ins
            if let existing = themes[themeId], existing.isCustom {
                themes.removeValue(forKey: themeId)
            }
        }
    }
    
    public func theme(for id: String) -> ThemeDefinition {
        lock.withLock {
            themes[id] ?? ThemeDefinition.modernHybrid
        }
    }
    
    public var allThemes: [ThemeDefinition] {
        lock.withLock {
            let list = Array(themes.values)
            let builtIns = list.filter { !$0.isCustom }.sorted { $0.displayName < $1.displayName }
            let custom = list.filter { $0.isCustom }.sorted { $0.displayName < $1.displayName }
            return builtIns + custom
        }
    }
    
    public func importTheme(from data: Data) throws -> ThemeDefinition {
        let decoder = JSONDecoder()
        let theme = try decoder.decode(ThemeDefinition.self, from: data)
        register(theme: theme)
        return theme
    }
    
    public func exportTheme(_ theme: ThemeDefinition) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(theme)
    }
}
