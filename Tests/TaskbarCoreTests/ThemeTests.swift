// Tests/TaskbarCoreTests/ThemeTests.swift

import XCTest
@testable import TaskbarCore

final class ThemeTests: XCTestCase {
    func testModernHybridTheme() {
        let theme = ThemeDefinition.forStyle(.modernHybrid)
        XCTAssertEqual(theme.style, .modernHybrid)
        XCTAssertEqual(theme.id, "modern-hybrid")
        XCTAssertTrue(theme.useTranslucency)
        XCTAssertFalse(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 4.0)
        XCTAssertEqual(theme.fontSize, TaskbarConstants.Layout.defaultFontSize)
        XCTAssertEqual(theme.iconSize, TaskbarConstants.Layout.defaultIconSize)
    }
    
    func testRetroClassicTheme() {
        let theme = ThemeDefinition.forStyle(.retroClassic, fontSize: 13.0, iconSize: 20.0)
        XCTAssertEqual(theme.style, .retroClassic)
        XCTAssertEqual(theme.id, "retro-classic")
        XCTAssertFalse(theme.useTranslucency)
        XCTAssertTrue(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 0.0)
        XCTAssertEqual(theme.backgroundColor, RetroClassicTheme.gray)
        XCTAssertEqual(theme.fontSize, 13.0)
        XCTAssertEqual(theme.iconSize, 20.0)
    }
    
    func testThemeJSONSerializationRoundTrip() throws {
        let original = ThemeDefinition.modernHybrid
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(original)
        XCTAssertFalse(jsonData.isEmpty)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ThemeDefinition.self, from: jsonData)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.palette, original.palette)
        XCTAssertEqual(decoded.metrics, original.metrics)
        XCTAssertEqual(decoded.materials, original.materials)
        XCTAssertEqual(decoded, original)
    }
    
    func testThemeRegistryBuiltIns() {
        let registry = ThemeRegistry.shared
        XCTAssertEqual(registry.theme(for: "modern-hybrid").id, "modern-hybrid")
        XCTAssertEqual(registry.theme(for: "retro-classic").id, "retro-classic")
        XCTAssertEqual(registry.theme(for: "non-existent-id").id, "modern-hybrid") // Fallback
        
        let all = registry.allThemes
        XCTAssertTrue(all.contains(where: { $0.id == "modern-hybrid" }))
        XCTAssertTrue(all.contains(where: { $0.id == "retro-classic" }))
    }
    
    func testThemeRegistryImportCustomJSON() throws {
        let customJSON = """
        {
          "id": "nord-frost",
          "displayName": "Nord Frost",
          "isCustom": true,
          "palette": {
            "backgroundColor": { "red": 0.18, "green": 0.20, "blue": 0.25, "alpha": 0.95 },
            "topBorderColor": { "red": 0.24, "green": 0.27, "blue": 0.33, "alpha": 1.0 },
            "textNormal": { "red": 0.93, "green": 0.94, "blue": 0.96, "alpha": 1.0 },
            "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0, "alpha": 1.0 },
            "buttonNormal": { "red": 0.24, "green": 0.27, "blue": 0.33, "alpha": 0.8 },
            "buttonHover": { "red": 0.30, "green": 0.34, "blue": 0.42, "alpha": 0.9 },
            "buttonPressed": { "red": 0.34, "green": 0.38, "blue": 0.46, "alpha": 1.0 },
            "buttonBorderNormal": { "red": 0.24, "green": 0.27, "blue": 0.33, "alpha": 1.0 },
            "buttonBorderPressed": { "red": 0.35, "green": 0.70, "blue": 0.90, "alpha": 1.0 }
          },
          "metrics": {
            "buttonCornerRadius": 6.0,
            "is3DBeveled": false,
            "fontBold": false,
            "fontSize": 12.0,
            "iconSize": 16.0
          },
          "materials": {
            "useTranslucency": true
          }
        }
        """
        
        guard let data = customJSON.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let registry = ThemeRegistry.shared
        let imported = try registry.importTheme(from: data)
        
        XCTAssertEqual(imported.id, "nord-frost")
        XCTAssertEqual(imported.displayName, "Nord Frost")
        XCTAssertTrue(imported.isCustom)
        XCTAssertEqual(imported.buttonCornerRadius, 6.0)
        XCTAssertEqual(registry.theme(for: "nord-frost").id, "nord-frost")
        
        // Clean up
        registry.unregister(themeId: "nord-frost")
        XCTAssertEqual(registry.theme(for: "nord-frost").id, "modern-hybrid")
    }
}
