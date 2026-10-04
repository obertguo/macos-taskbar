// Tests/TaskbarCoreTests/ThemePresetsTests.swift

import XCTest
@testable import TaskbarCore

final class ThemePresetsTests: XCTestCase {
    
    func testAllBuiltInPresetsRegistered() {
        let registry = ThemeRegistry.shared
        let all = registry.allThemes
        
        let expectedIds = [
            ModernHybridTheme.id,
            RetroClassicTheme.id,
            WindowsXPLunaTheme.id,
            DarkMinimalTheme.id
        ]
        
        for expectedId in expectedIds {
            XCTAssertTrue(all.contains(where: { $0.id == expectedId }), "ThemeRegistry should contain preset \(expectedId)")
            let theme = registry.theme(for: expectedId)
            XCTAssertEqual(theme.id, expectedId)
            XCTAssertFalse(theme.isCustom)
        }
    }
    
    func testModernHybridPresetProperties() {
        let theme = ThemeDefinition.modernHybrid
        XCTAssertEqual(theme.id, "modern-hybrid")
        XCTAssertEqual(theme.style, .modernHybrid)
        XCTAssertTrue(theme.useTranslucency)
        XCTAssertFalse(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 4.0)
        XCTAssertFalse(theme.fontBold)
        XCTAssertEqual(theme.displayName, TaskbarStrings.Themes.modernHybrid)
    }
    
    func testRetroClassicPresetProperties() {
        let theme = ThemeDefinition.retroClassic
        XCTAssertEqual(theme.id, "retro-classic")
        XCTAssertEqual(theme.style, .retroClassic)
        XCTAssertFalse(theme.useTranslucency)
        XCTAssertTrue(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 0.0)
        XCTAssertTrue(theme.fontBold)
        XCTAssertEqual(theme.backgroundColor, .retroGray)
        XCTAssertEqual(theme.displayName, TaskbarStrings.Themes.retroClassic)
    }
    
    func testWindowsXPLunaPresetProperties() {
        let theme = ThemeDefinition.windowsXPLuna
        XCTAssertEqual(theme.id, "windows-xp-luna")
        XCTAssertEqual(theme.style, .windowsXPLuna)
        XCTAssertFalse(theme.useTranslucency)
        XCTAssertFalse(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 3.0)
        XCTAssertFalse(theme.fontBold)
        XCTAssertEqual(theme.displayName, TaskbarStrings.Themes.windowsXPLuna)
        
        // Verify green Start button tokens
        XCTAssertNotNil(theme.palette.startButtonNormal)
        XCTAssertNotNil(theme.palette.startButtonHover)
        XCTAssertNotNil(theme.palette.startButtonPressed)
        XCTAssertEqual(theme.palette.startButtonText, .white)
    }
    
    func testDarkMinimalPresetProperties() {
        let theme = ThemeDefinition.darkMinimal
        XCTAssertEqual(theme.id, "dark-minimal")
        XCTAssertEqual(theme.style, .darkMinimal)
        XCTAssertFalse(theme.useTranslucency)
        XCTAssertFalse(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 2.0)
        XCTAssertFalse(theme.fontBold)
        XCTAssertEqual(theme.displayName, TaskbarStrings.Themes.darkMinimal)
        
        // Verify OLED dark background and cyan accent
        XCTAssertEqual(theme.palette.backgroundColor.red, 18.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(theme.palette.buttonBorderPressed.blue, 212.0 / 255.0, accuracy: 0.001)
    }
    
    func testAllPresetsJSONRoundTrip() throws {
        let presets = [
            ThemeDefinition.modernHybrid,
            ThemeDefinition.retroClassic,
            ThemeDefinition.windowsXPLuna,
            ThemeDefinition.darkMinimal
        ]
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        
        for preset in presets {
            let data = try encoder.encode(preset)
            XCTAssertFalse(data.isEmpty, "Encoded data for \(preset.id) should not be empty")
            
            let decoded = try decoder.decode(ThemeDefinition.self, from: data)
            XCTAssertEqual(decoded.id, preset.id)
            XCTAssertEqual(decoded.displayName, preset.displayName)
            XCTAssertEqual(decoded.palette, preset.palette)
            XCTAssertEqual(decoded.metrics, preset.metrics)
            XCTAssertEqual(decoded.materials, preset.materials)
            XCTAssertEqual(decoded, preset)
        }
    }
    
    func testThemeForStyleFactory() {
        let styles: [ThemeStyle] = [.modernHybrid, .retroClassic, .windowsXPLuna, .darkMinimal]
        for style in styles {
            let theme = ThemeDefinition.forStyle(style, fontSize: 13.0, iconSize: 18.0)
            XCTAssertEqual(theme.style, style)
            XCTAssertEqual(theme.fontSize, 13.0)
            XCTAssertEqual(theme.iconSize, 18.0)
        }
    }
}
