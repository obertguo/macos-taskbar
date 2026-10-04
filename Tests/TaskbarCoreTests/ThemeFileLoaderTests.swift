// Tests/TaskbarCoreTests/ThemeFileLoaderTests.swift

import XCTest
@testable import TaskbarCore

final class ThemeFileLoaderTests: XCTestCase {
    private var tempDirectory: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskbarThemesTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        if let dir = tempDirectory, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        ThemeRegistry.shared.unregisterAllCustomThemes()
        try super.tearDownWithError()
    }
    
    func testDiscoverThemesFromEmptyDirectory() {
        let loader = ThemeFileLoader(directory: tempDirectory)
        let themes = loader.discoverCustomThemes()
        XCTAssertTrue(themes.isEmpty, "Empty directory should produce zero themes")
    }
    
    func testDiscoverValidCustomThemeJSON() throws {
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
        
        XCTAssertEqual(themes.count, 1)
        guard let theme = themes.first else { return }
        XCTAssertEqual(theme.id, "dracula-pro")
        XCTAssertEqual(theme.displayName, "Dracula Pro")
        XCTAssertTrue(theme.isCustom)
        XCTAssertEqual(theme.buttonCornerRadius, 5.0)
        XCTAssertFalse(theme.useTranslucency)
        XCTAssertEqual(theme.palette.backgroundColor.red, 0.16, accuracy: 0.001)
    }
    
    func testDiscoverThemeOmittingIsCustomDefaultsToTrue() throws {
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
        
        XCTAssertEqual(themes.count, 1)
        guard let theme = themes.first else { return }
        XCTAssertEqual(theme.id, "nord-frost")
        XCTAssertEqual(theme.displayName, "Nord Frost")
        XCTAssertTrue(theme.isCustom, "Custom theme omitted in JSON should default isCustom to true")
        XCTAssertEqual(theme.palette.backgroundColor.alpha, 1.0, "Omitted alpha should default to 1.0")
        XCTAssertEqual(theme.buttonCornerRadius, 4.0, "Omitted metrics should adopt standard defaults")
        XCTAssertTrue(theme.useTranslucency, "Omitted materials should default useTranslucency to true")
    }
    
    func testDiscoverThemesIgnoresNonJSONFiles() throws {
        let txtURL = tempDirectory.appendingPathComponent("notes.txt")
        try "Some notes".write(to: txtURL, atomically: true, encoding: .utf8)
        
        let dsStoreURL = tempDirectory.appendingPathComponent(".DS_Store")
        try Data([0, 1, 2, 3]).write(to: dsStoreURL)
        
        let loader = ThemeFileLoader(directory: tempDirectory)
        let themes = loader.discoverCustomThemes()
        XCTAssertTrue(themes.isEmpty, "Non-JSON files must be strictly ignored")
    }
    
    func testDiscoverThemesSkipsBuiltInCollision() throws {
        let collisionJSON = """
        {
            "id": "modern-hybrid",
            "displayName": "Fake Modern Hybrid",
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
        let fileURL = tempDirectory.appendingPathComponent("collision.json")
        try collisionJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        
        let loader = ThemeFileLoader(directory: tempDirectory)
        let themes = loader.discoverCustomThemes()
        XCTAssertTrue(themes.isEmpty, "Collision with built-in preset ID must be skipped")
    }
    
    func testDiscoverThemesHandlesCorruptedJSONGracefully() throws {
        let corruptURL = tempDirectory.appendingPathComponent("broken.json")
        try "{\"invalid\": [not valid json".write(to: corruptURL, atomically: true, encoding: .utf8)
        
        let loader = ThemeFileLoader(directory: tempDirectory)
        let themes = loader.discoverCustomThemes()
        XCTAssertTrue(themes.isEmpty, "Corrupt files should not throw or crash")
    }
    
    func testExportThemeAndRoundTrip() throws {
        let preset = ThemeDefinition.windowsXPLuna
        let destinationURL = tempDirectory.appendingPathComponent("exported-luna.json")
        
        let loader = ThemeFileLoader(directory: tempDirectory)
        try loader.exportTheme(preset, to: destinationURL)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        let data = try Data(contentsOf: destinationURL)
        let decoded = try JSONDecoder().decode(ThemeDefinition.self, from: data)
        
        XCTAssertEqual(decoded.id, preset.id)
        XCTAssertEqual(decoded.palette, preset.palette)
        XCTAssertEqual(decoded.metrics, preset.metrics)
        XCTAssertEqual(decoded.materials, preset.materials)
    }
    
    func testReloadCustomThemesRegistersAndUnregistersWithThemeRegistry() throws {
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
        XCTAssertEqual(discovered.count, 1)
        
        let registeredTheme = ThemeRegistry.shared.theme(for: "solarized-custom")
        XCTAssertEqual(registeredTheme.id, "solarized-custom")
        XCTAssertTrue(registeredTheme.isCustom)
        XCTAssertTrue(ThemeRegistry.shared.customThemes.contains(where: { $0.id == "solarized-custom" }))
        
        // Remove file from disk and reload -> should be removed from registry
        try FileManager.default.removeItem(at: fileURL)
        let reloaded = loader.reloadCustomThemes()
        XCTAssertEqual(reloaded.count, 0)
        XCTAssertFalse(ThemeRegistry.shared.customThemes.contains(where: { $0.id == "solarized-custom" }))
    }
}
