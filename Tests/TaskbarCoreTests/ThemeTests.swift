// Tests/TaskbarCoreTests/ThemeTests.swift

import Foundation
import Testing
@testable import TaskbarCore

@Suite("Theme Tests", .serialized)
struct ThemeTests {
    
    @Test("Modern Hybrid Theme properties")
    func testModernHybridTheme() {
        let theme = ThemeDefinition.forStyle(.modernHybrid)
        #expect(theme.style == .modernHybrid)
        #expect(theme.id == "modern-hybrid")
        #expect(theme.useTranslucency)
        #expect(!theme.is3DBeveled)
        #expect(theme.buttonCornerRadius == 4.0)
        #expect(theme.fontSize == TaskbarConstants.Layout.defaultFontSize)
        #expect(theme.iconSize == TaskbarConstants.Layout.defaultIconSize)
    }
    
    @Test("Retro Classic Theme properties")
    func testRetroClassicTheme() {
        let theme = ThemeDefinition.forStyle(.retroClassic, fontSize: 13.0, iconSize: 20.0)
        #expect(theme.style == .retroClassic)
        #expect(theme.id == "retro-classic")
        #expect(!theme.useTranslucency)
        #expect(theme.is3DBeveled)
        #expect(theme.buttonCornerRadius == 0.0)
        #expect(abs(theme.backgroundColor.red - (192.0 / 255.0)) < 0.001)
        #expect(abs(theme.backgroundColor.green - (192.0 / 255.0)) < 0.001)
        #expect(abs(theme.backgroundColor.blue - (192.0 / 255.0)) < 0.001)
        #expect(theme.fontSize == 13.0)
        #expect(theme.iconSize == 20.0)
    }
    
    @Test("Theme JSON serialization roundtrip")
    func testThemeJSONSerializationRoundTrip() throws {
        let original = ThemeDefinition.modernHybrid
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(original)
        #expect(!jsonData.isEmpty)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ThemeDefinition.self, from: jsonData)
        
        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.palette == original.palette)
        #expect(decoded.metrics == original.metrics)
        #expect(decoded.materials == original.materials)
        #expect(decoded == original)
    }
    
    @Test("ThemeRegistry built-in registrations and fallback")
    func testThemeRegistryBuiltIns() {
        let registry = ThemeRegistry.shared
        #expect(registry.theme(for: "modern-hybrid").id == "modern-hybrid")
        #expect(registry.theme(for: "retro-classic").id == "retro-classic")
        #expect(registry.theme(for: "non-existent-id").id == "modern-hybrid") // Fallback
        
        let all = registry.allThemes
        #expect(all.contains(where: { $0.id == "modern-hybrid" }))
        #expect(all.contains(where: { $0.id == "retro-classic" }))
    }
    
    @Test("ThemeRegistry import custom JSON")
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
        
        let data = try #require(customJSON.data(using: .utf8))
        let registry = ThemeRegistry.shared
        defer {
            registry.unregister(themeId: "nord-frost")
        }
        
        let imported = try registry.importTheme(from: data)
        #expect(imported.id == "nord-frost")
        #expect(imported.displayName == "Nord Frost")
        #expect(imported.isCustom)
        #expect(imported.buttonCornerRadius == 6.0)
        #expect(registry.theme(for: "nord-frost").id == "nord-frost")
        
        // Clean up
        registry.unregister(themeId: "nord-frost")
        #expect(registry.theme(for: "nord-frost").id == "modern-hybrid")
    }
    
    @Test(
        "Importing theme with built-in IDs throws cannotOverwriteBuiltIn",
        arguments: ["modern", "classic", "windows-xp-luna", "dark-minimal", "modern-hybrid", "retro-classic"]
    )
    func testImportThemeCannotOverwriteBuiltIn(builtInId: String) throws {
        let json = """
        {
            "id": "\(builtInId)",
            "displayName": "Overwritten Built-in Theme",
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
        let data = try #require(json.data(using: .utf8))
        let registry = ThemeRegistry.shared
        
        #expect(throws: ThemeRegistryError.cannotOverwriteBuiltIn(builtInId)) {
            try registry.importTheme(from: data)
        }
    }
    
    @Test("Imported custom theme always forces isCustom == true even if omitted or false in JSON")
    func testImportThemeForcesIsCustom() throws {
        let registry = ThemeRegistry.shared
        defer {
            registry.unregister(themeId: "force-custom-false")
            registry.unregister(themeId: "force-custom-omitted")
        }
        
        let jsonWithFalse = """
        {
            "id": "force-custom-false",
            "displayName": "Force Custom False",
            "isCustom": false,
            "palette": {
                "backgroundColor": { "red": 0.1, "green": 0.1, "blue": 0.1 },
                "textNormal": { "red": 0.9, "green": 0.9, "blue": 0.9 },
                "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                "buttonNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                "buttonHover": { "red": 0.3, "green": 0.3, "blue": 0.3 },
                "buttonPressed": { "red": 0.4, "green": 0.4, "blue": 0.4 },
                "buttonBorderNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                "buttonBorderPressed": { "red": 0.5, "green": 0.5, "blue": 0.5 }
            }
        }
        """
        let dataWithFalse = try #require(jsonWithFalse.data(using: .utf8))
        let importedThemeFalse = try registry.importTheme(from: dataWithFalse)
        #expect(importedThemeFalse.isCustom == true)
        #expect(registry.theme(for: "force-custom-false").isCustom == true)
        
        let jsonOmitted = """
        {
            "id": "force-custom-omitted",
            "displayName": "Force Custom Omitted",
            "palette": {
                "backgroundColor": { "red": 0.1, "green": 0.1, "blue": 0.1 },
                "textNormal": { "red": 0.9, "green": 0.9, "blue": 0.9 },
                "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0 },
                "buttonNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                "buttonHover": { "red": 0.3, "green": 0.3, "blue": 0.3 },
                "buttonPressed": { "red": 0.4, "green": 0.4, "blue": 0.4 },
                "buttonBorderNormal": { "red": 0.2, "green": 0.2, "blue": 0.2 },
                "buttonBorderPressed": { "red": 0.5, "green": 0.5, "blue": 0.5 }
            }
        }
        """
        let dataOmitted = try #require(jsonOmitted.data(using: .utf8))
        let importedThemeOmitted = try registry.importTheme(from: dataOmitted)
        #expect(importedThemeOmitted.isCustom == true)
        #expect(registry.theme(for: "force-custom-omitted").isCustom == true)
    }
    
    @Test("Importing theme with empty or whitespace-only ID throws emptyThemeId")
    func testImportThemeEmptyId() throws {
        let registry = ThemeRegistry.shared
        let emptyIdJSON = """
        {
            "id": "   ",
            "displayName": "Empty ID Theme",
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
        let data = try #require(emptyIdJSON.data(using: .utf8))
        #expect(throws: ThemeRegistryError.emptyThemeId) {
            try registry.importTheme(from: data)
        }
    }
    
    @Test("ThemeRegistryError errorDescription provides descriptive messages")
    func testThemeRegistryErrorDescriptions() {
        let err1 = ThemeRegistryError.cannotOverwriteBuiltIn("modern")
        #expect(err1.errorDescription == "Cannot overwrite built-in theme 'modern'.")
        
        let err2 = ThemeRegistryError.emptyThemeId
        #expect(err2.errorDescription == "Theme ID cannot be empty.")
    }
    
    @Test("ThemeMaterials decoding with material and blending mode")
    func testThemeMaterialsDecodingWithMaterialAndBlendingMode() throws {
        let json = """
        {
            "useTranslucency": true,
            "material": "hudWindow",
            "blendingMode": "withinWindow"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let materials = try JSONDecoder().decode(ThemeMaterials.self, from: data)
        #expect(materials.useTranslucency)
        #expect(materials.material == "hudWindow")
        #expect(materials.blendingMode == "withinWindow")
        
        // Roundtrip encode / decode
        let encoded = try JSONEncoder().encode(materials)
        let roundtrip = try JSONDecoder().decode(ThemeMaterials.self, from: encoded)
        #expect(roundtrip == materials)
        #expect(roundtrip.material == "hudWindow")
        #expect(roundtrip.blendingMode == "withinWindow")
    }
}
