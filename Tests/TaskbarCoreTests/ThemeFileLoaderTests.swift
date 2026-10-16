// Tests/TaskbarCoreTests/ThemeFileLoaderTests.swift

import Foundation
import Testing
@testable import TaskbarCore

@Suite("Theme File Loader Tests", .serialized)
struct ThemeFileLoaderTests {
    
    private func withTempDirectory(_ testBody: (URL) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskbarThemesTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            ThemeRegistry.shared.unregisterAllCustomThemes()
        }
        try testBody(tempDir)
    }
    
    @Test("Discover themes from empty directory returns empty array")
    func testDiscoverThemesFromEmptyDirectory() throws {
        try withTempDirectory { tempDirectory in
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            #expect(themes.isEmpty, "Empty directory should produce zero themes")
        }
    }
    
    @Test("Discover valid custom theme JSON")
    func testDiscoverValidCustomThemeJSON() throws {
        try withTempDirectory { tempDirectory in
            let json = """
            {
                "id": "dracula-pro",
                "displayName": "Dracula Pro",
                "isCustom": true,
                "palette": {
                    "backgroundColor": { "red": 0.16, "green": 0.16, "blue": 0.21, "alpha": 1.0 },
                    "textNormal": { "red": 0.95, "green": 0.95, "blue": 0.95, "alpha": 1.0 },
                    "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0, "alpha": 1.0 },
                    "buttonNormal": { "red": 0.25, "green": 0.26, "blue": 0.35, "alpha": 1.0 },
                    "buttonHover": { "red": 0.31, "green": 0.32, "blue": 0.43, "alpha": 1.0 },
                    "buttonPressed": { "red": 0.38, "green": 0.39, "blue": 0.52, "alpha": 1.0 },
                    "buttonBorderNormal": { "red": 0.2, "green": 0.2, "blue": 0.27, "alpha": 1.0 },
                    "buttonBorderPressed": { "red": 0.74, "green": 0.46, "blue": 0.79, "alpha": 1.0 }
                },
                "metrics": {
                    "buttonCornerRadius": 5.0,
                    "is3DBeveled": false,
                    "fontBold": false,
                    "fontSize": 12.0,
                    "iconSize": 16.0
                },
                "materials": {
                    "useTranslucency": false
                }
            }
            """
            let fileURL = tempDirectory.appendingPathComponent("dracula.json")
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            
            #expect(themes.count == 1)
            guard let theme = themes.first else { return }
            #expect(theme.id == "dracula-pro")
            #expect(theme.displayName == "Dracula Pro")
            #expect(theme.isCustom)
            #expect(theme.buttonCornerRadius == 5.0)
            #expect(!theme.useTranslucency)
            #expect(abs(theme.palette.backgroundColor.red - 0.16) < 0.001)
        }
    }
    
    @Test("Discover theme omitting isCustom defaults to true")
    func testDiscoverThemeOmittingIsCustomDefaultsToTrue() throws {
        try withTempDirectory { tempDirectory in
            let json = """
            {
                "id": "nord-frost",
                "displayName": "Nord Frost",
                "palette": {
                    "backgroundColor": { "red": 0.18, "green": 0.20, "blue": 0.25 },
                    "textNormal": { "red": 0.92, "green": 0.94, "blue": 0.96 },
                    "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                    "buttonNormal": { "red": 0.24, "green": 0.27, "blue": 0.33 },
                    "buttonHover": { "red": 0.29, "green": 0.34, "blue": 0.42 },
                    "buttonPressed": { "red": 0.35, "green": 0.41, "blue": 0.50 },
                    "buttonBorderNormal": { "red": 0.30, "green": 0.34, "blue": 0.42 },
                    "buttonBorderPressed": { "red": 0.53, "green": 0.75, "blue": 0.82 }
                }
            }
            """
            let fileURL = tempDirectory.appendingPathComponent("nord.json")
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            
            #expect(themes.count == 1)
            guard let theme = themes.first else { return }
            #expect(theme.id == "nord-frost")
            #expect(theme.displayName == "Nord Frost")
            #expect(theme.isCustom, "Custom theme omitted in JSON should default isCustom to true")
            #expect(theme.palette.backgroundColor.alpha == 1.0, "Omitted alpha should default to 1.0")
            #expect(theme.buttonCornerRadius == 4.0, "Omitted metrics should adopt standard defaults")
            #expect(theme.useTranslucency, "Omitted materials should default useTranslucency to true")
        }
    }
    
    @Test("Discover themes ignores non-JSON files")
    func testDiscoverThemesIgnoresNonJSONFiles() throws {
        try withTempDirectory { tempDirectory in
            let txtURL = tempDirectory.appendingPathComponent("notes.txt")
            try "Some notes".write(to: txtURL, atomically: true, encoding: .utf8)
            
            let dsStoreURL = tempDirectory.appendingPathComponent(".DS_Store")
            try Data([0, 1, 2, 3]).write(to: dsStoreURL)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            #expect(themes.isEmpty, "Non-JSON files must be strictly ignored")
        }
    }
    
    @Test("Discover themes skips built-in collision")
    func testDiscoverThemesSkipsBuiltInCollision() throws {
        try withTempDirectory { tempDirectory in
            let collisionIDs = ["modern-hybrid", "retro-classic", "modern", "classic", "windows-xp-luna", "dark-minimal"]
            for (idx, builtInId) in collisionIDs.enumerated() {
                let collisionJSON = """
                {
                    "id": "\(builtInId)",
                    "displayName": "Fake \(builtInId)",
                    "palette": {
                        "backgroundColor": { "red": 0.0, "green": 0.0, "blue": 0.0 },
                        "textNormal": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                        "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                        "buttonNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                        "buttonHover": { "red": 0.3, "green": 0.3, "blue": 0.3 },
                        "buttonPressed": { "red": 0.4, "green": 0.4, "blue": 0.4 },
                        "buttonBorderNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                        "buttonBorderPressed": { "red": 0.5, "green": 0.5, "blue": 0.5 }
                    }
                }
                """
                let fileURL = tempDirectory.appendingPathComponent("collision_\(idx).json")
                try collisionJSON.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            #expect(themes.isEmpty, "Collision with built-in preset IDs must be skipped")
        }
    }
    
    @Test("Discover themes skips files with empty or whitespace-only id")
    func testDiscoverThemesSkipsEmptyId() throws {
        try withTempDirectory { tempDirectory in
            let emptyIdJSON = """
            {
                "id": "   ",
                "displayName": "Valid Display Name",
                "palette": {
                    "backgroundColor": { "red": 0.0, "green": 0.0, "blue": 0.0 },
                    "textNormal": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                    "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                    "buttonNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                    "buttonHover": { "red": 0.3, "green": 0.3, "blue": 0.3 },
                    "buttonPressed": { "red": 0.4, "green": 0.4, "blue": 0.4 },
                    "buttonBorderNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                    "buttonBorderPressed": { "red": 0.5, "green": 0.5, "blue": 0.5 }
                }
            }
            """
            let fileURL = tempDirectory.appendingPathComponent("empty_id.json")
            try emptyIdJSON.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            #expect(themes.isEmpty, "Custom theme with empty id must be skipped")
        }
    }
    
    @Test("Discover themes skips files with empty or whitespace-only displayName")
    func testDiscoverThemesSkipsEmptyDisplayName() throws {
        try withTempDirectory { tempDirectory in
            let emptyNameJSON = """
            {
                "id": "valid-theme-id",
                "displayName": "   \n\t ",
                "palette": {
                    "backgroundColor": { "red": 0.0, "green": 0.0, "blue": 0.0 },
                    "textNormal": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                    "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                    "buttonNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                    "buttonHover": { "red": 0.3, "green": 0.3, "blue": 0.3 },
                    "buttonPressed": { "red": 0.4, "green": 0.4, "blue": 0.4 },
                    "buttonBorderNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                    "buttonBorderPressed": { "red": 0.5, "green": 0.5, "blue": 0.5 }
                }
            }
            """
            let fileURL = tempDirectory.appendingPathComponent("empty_name.json")
            try emptyNameJSON.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            #expect(themes.isEmpty, "Custom theme with empty displayName must be skipped")
        }
    }
    
    @Test("Discover themes handles corrupted JSON gracefully")
    func testDiscoverThemesHandlesCorruptedJSONGracefully() throws {
        try withTempDirectory { tempDirectory in
            let corruptURL = tempDirectory.appendingPathComponent("broken.json")
            try "{\"invalid\": [not valid json".write(to: corruptURL, atomically: true, encoding: .utf8)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            #expect(themes.isEmpty, "Corrupt files should not throw or crash")
        }
    }
    
    @Test("Export theme and round trip")
    func testExportThemeAndRoundTrip() throws {
        try withTempDirectory { tempDirectory in
            let preset = ThemeDefinition.windowsXPLuna
            let destinationURL = tempDirectory.appendingPathComponent("exported-luna.json")
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            try loader.exportTheme(preset, to: destinationURL)
            
            #expect(FileManager.default.fileExists(atPath: destinationURL.path))
            let data = try Data(contentsOf: destinationURL)
            let decoded = try JSONDecoder().decode(ThemeDefinition.self, from: data)
            
            #expect(decoded.id == preset.id)
            #expect(decoded.palette == preset.palette)
            #expect(decoded.metrics == preset.metrics)
            #expect(decoded.materials == preset.materials)
        }
    }
    
    @Test("Reload custom themes registers and unregisters with ThemeRegistry")
    func testReloadCustomThemesRegistersAndUnregistersWithThemeRegistry() throws {
        try withTempDirectory { tempDirectory in
            let json = """
            {
                "id": "solarized-custom",
                "displayName": "Solarized Custom",
                "palette": {
                    "backgroundColor": { "red": 0.0, "green": 0.17, "blue": 0.21 },
                    "textNormal": { "red": 0.51, "green": 0.58, "blue": 0.59 },
                    "textPressed": { "red": 0.58, "green": 0.63, "blue": 0.63 },
                    "buttonNormal": { "red": 0.03, "green": 0.21, "blue": 0.26 },
                    "buttonHover": { "red": 0.07, "green": 0.26, "blue": 0.32 },
                    "buttonPressed": { "red": 0.11, "green": 0.31, "blue": 0.38 },
                    "buttonBorderNormal": { "red": 0.35, "green": 0.43, "blue": 0.46 },
                    "buttonBorderPressed": { "red": 0.15, "green": 0.55, "blue": 0.82 }
                }
            }
            """
            let fileURL = tempDirectory.appendingPathComponent("solarized.json")
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let discovered = loader.reloadCustomThemes()
            #expect(discovered.count == 1)
            
            let registeredTheme = ThemeRegistry.shared.theme(for: "solarized-custom")
            #expect(registeredTheme.id == "solarized-custom")
            #expect(registeredTheme.isCustom)
            #expect(ThemeRegistry.shared.customThemes.contains(where: { $0.id == "solarized-custom" }))
            
            // Remove file from disk and reload -> should be removed from registry
            try FileManager.default.removeItem(at: fileURL)
            let reloaded = loader.reloadCustomThemes()
            #expect(reloaded.count == 0)
            #expect(!ThemeRegistry.shared.customThemes.contains(where: { $0.id == "solarized-custom" }))
        }
    }
    
    @Test("Discover custom theme with material and blending mode")
    func testDiscoverCustomThemeWithMaterialAndBlendingMode() throws {
        try withTempDirectory { tempDirectory in
            let json = """
            {
                "id": "translucent-hud",
                "displayName": "Translucent HUD",
                "isCustom": true,
                "palette": {
                    "backgroundColor": { "red": 0.0, "green": 0.0, "blue": 0.0, "alpha": 0.0 },
                    "textNormal": { "red": 1.0, "green": 1.0, "blue": 1.0, "alpha": 1.0 },
                    "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0, "alpha": 1.0 },
                    "buttonNormal": { "red": 0.2, "green": 0.2, "blue": 0.2, "alpha": 0.5 },
                    "buttonHover": { "red": 0.3, "green": 0.3, "blue": 0.3, "alpha": 0.6 },
                    "buttonPressed": { "red": 0.4, "green": 0.4, "blue": 0.4, "alpha": 0.7 },
                    "buttonBorderNormal": { "red": 0.5, "green": 0.5, "blue": 0.5, "alpha": 0.5 },
                    "buttonBorderPressed": { "red": 0.0, "green": 0.5, "blue": 1.0, "alpha": 0.8 }
                },
                "materials": {
                    "useTranslucency": true,
                    "material": "hudWindow",
                    "blendingMode": "withinWindow"
                }
            }
            """
            let fileURL = tempDirectory.appendingPathComponent("translucent-hud.json")
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let loader = ThemeFileLoader(directory: tempDirectory)
            let themes = loader.discoverCustomThemes()
            
            #expect(themes.count == 1)
            guard let theme = themes.first else { return }
            #expect(theme.id == "translucent-hud")
            #expect(theme.useTranslucency)
            #expect(theme.material == "hudWindow")
            #expect(theme.blendingMode == "withinWindow")
            #expect(theme.materials.material == "hudWindow")
            #expect(theme.materials.blendingMode == "withinWindow")
        }
    }
}
