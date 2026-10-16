// Sources/TaskbarCore/Config/Theme/ThemeFileLoader.swift

import Foundation

/// Discovers, validates, imports, and exports custom theme JSON definitions from disk.
/// Default location: `~/.config/taskbar/themes/`
public final class ThemeFileLoader: Sendable {
    public static let shared = ThemeFileLoader()
    
    public let customThemesDirectory: URL
    
    public init(directory: URL? = nil) {
        self.customThemesDirectory = directory ?? Self.defaultThemesDirectory()
    }
    
    /// Resolves the canonical user theme directory (~/.config/taskbar/themes/), falling back to ~/Library/Application Support/Taskbar/Themes/.
    public static func defaultThemesDirectory() -> URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configURL = homeDir.appendingPathComponent(".config/taskbar/themes", isDirectory: true)
        return configURL
    }
    
    /// Creates the custom themes directory if it does not already exist.
    public func createDirectoryIfNeeded() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: customThemesDirectory.path) {
            try fileManager.createDirectory(at: customThemesDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Scans the themes directory for `*.json` files and parses them into `ThemeDefinition` instances.
    /// Corrupted files or built-in ID collisions are safely logged and skipped without throwing.
    public func discoverCustomThemes() -> [ThemeDefinition] {
        try? createDirectoryIfNeeded()
        
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: customThemesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            TaskbarLogger.ui.info("No accessible themes directory at \(self.customThemesDirectory.path)")
            return []
        }
        
        let jsonFiles = urls.filter { $0.pathExtension.lowercased() == "json" }
        var loadedThemes: [ThemeDefinition] = []
        let decoder = JSONDecoder()
        
        for fileURL in jsonFiles {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try decoder.decode(ThemeDefinition.self, from: data)
                
                let themeId = decoded.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = decoded.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !themeId.isEmpty, !displayName.isEmpty else {
                    TaskbarLogger.ui.warning("Skipping theme in '\(fileURL.lastPathComponent)' because its 'id' or 'displayName' is empty.")
                    continue
                }
                
                // Disallow overriding built-in preset IDs to prevent corruption of default presets
                if ThemeRegistry.shared.isBuiltIn(themeId: themeId) {
                    TaskbarLogger.ui.warning("Skipping custom theme in '\(fileURL.lastPathComponent)' because ID '\(themeId)' collides with a built-in preset.")
                    continue
                }
                
                // Ensure custom theme is always marked as custom
                let customTheme = decoded.asCustom(true)
                loadedThemes.append(customTheme)
                TaskbarLogger.ui.info("Loaded custom theme '\(customTheme.displayName)' (\(customTheme.id)) from \(fileURL.lastPathComponent)")
            } catch {
                TaskbarLogger.ui.error("Failed to parse custom theme file '\(fileURL.lastPathComponent)': \(error.localizedDescription)")
            }
        }
        
        return loadedThemes.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
    
    /// Scans the themes directory and registers all discovered custom themes with the central `ThemeRegistry`.
    /// Existing custom themes deleted from disk are cleanly removed from the registry.
    @discardableResult
    public func reloadCustomThemes() -> [ThemeDefinition] {
        let themes = discoverCustomThemes()
        ThemeRegistry.shared.registerCustomThemes(themes)
        return themes
    }
    
    /// Exports a given `ThemeDefinition` as a pretty-printed JSON file to the specified destination URL.
    public func exportTheme(_ theme: ThemeDefinition, to destinationURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(theme)
        try data.write(to: destinationURL, options: .atomic)
    }
    
    /// Convenience method to export a `ThemeDefinition` directly into the custom themes directory.
    @discardableResult
    public func exportThemeToCustomDirectory(_ theme: ThemeDefinition, fileName: String? = nil) throws -> URL {
        try createDirectoryIfNeeded()
        let name = fileName ?? "\(theme.id).json"
        let destinationURL = customThemesDirectory.appendingPathComponent(name)
        try exportTheme(theme, to: destinationURL)
        return destinationURL
    }
}
