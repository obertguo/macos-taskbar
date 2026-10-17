// Sources/TaskbarCore/Config/Theme/ThemeRegistry.swift

import Foundation

public enum ThemeRegistryError: Error, LocalizedError, Equatable {
    case cannotOverwriteBuiltIn(String)
    case emptyThemeId
    
    public var errorDescription: String? {
        switch self {
        case .cannotOverwriteBuiltIn(let id):
            return "Cannot overwrite built-in theme '\(id)'."
        case .emptyThemeId:
            return "Theme ID cannot be empty."
        }
    }
}

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
    
    public func isBuiltIn(themeId: String) -> Bool {
        return [
            ModernHybridTheme.id,
            RetroClassicTheme.id,
            WindowsXPLunaTheme.id,
            DarkMinimalTheme.id,
            "modern",
            "classic"
        ].contains(themeId)
    }
    
    private func internalBuiltInThemes() -> [ThemeDefinition] {
        return [
            themes[ModernHybridTheme.id] ?? ThemeDefinition.modernHybrid,
            themes[RetroClassicTheme.id] ?? ThemeDefinition.retroClassic,
            themes[WindowsXPLunaTheme.id] ?? ThemeDefinition.windowsXPLuna,
            themes[DarkMinimalTheme.id] ?? ThemeDefinition.darkMinimal
        ]
    }
    
    private func internalCustomThemes() -> [ThemeDefinition] {
        return themes.values
            .filter { $0.isCustom }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    public var builtInThemes: [ThemeDefinition] {
        lock.withLock {
            internalBuiltInThemes()
        }
    }
    
    public var customThemes: [ThemeDefinition] {
        lock.withLock {
            internalCustomThemes()
        }
    }
    
    public func registerCustomThemes(_ newCustomThemes: [ThemeDefinition]) {
        lock.withLock {
            themes = themes.filter { !$0.value.isCustom }
            for theme in newCustomThemes {
                themes[theme.id] = theme
            }
        }
    }
    
    public func unregisterAllCustomThemes() {
        lock.withLock {
            themes = themes.filter { !$0.value.isCustom }
        }
    }
    
    public var allThemes: [ThemeDefinition] {
        lock.withLock {
            internalBuiltInThemes() + internalCustomThemes()
        }
    }
    
    public func importTheme(from data: Data) throws -> ThemeDefinition {
        let decoder = JSONDecoder()
        let theme = try decoder.decode(ThemeDefinition.self, from: data)
        let trimmedId = theme.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw ThemeRegistryError.emptyThemeId
        }
        guard !isBuiltIn(themeId: trimmedId) else {
            throw ThemeRegistryError.cannotOverwriteBuiltIn(trimmedId)
        }
        let trimmedDisplayName = theme.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let customTheme = theme.asCustom(true, id: trimmedId, displayName: trimmedDisplayName)
        register(theme: customTheme)
        return customTheme
    }
    
    public func exportTheme(_ theme: ThemeDefinition) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(theme)
    }
}
