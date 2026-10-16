// Tests/TaskbarCoreTests/ThemePresetsTests.swift

import Foundation
import Testing
@testable import TaskbarCore

@Suite("Theme Presets Tests")
struct ThemePresetsTests {
    
    @Test("All built-in presets are registered with registry")
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
            #expect(all.contains(where: { $0.id == expectedId }), "ThemeRegistry should contain preset \(expectedId)")
            let theme = registry.theme(for: expectedId)
            #expect(theme.id == expectedId)
            #expect(!theme.isCustom)
        }
    }
    
    @Test("Modern Hybrid preset properties")
    func testModernHybridPresetProperties() {
        let theme = ThemeDefinition.modernHybrid
        #expect(theme.id == "modern-hybrid")
        #expect(theme.style == .modernHybrid)
        #expect(theme.useTranslucency)
        #expect(!theme.is3DBeveled)
        #expect(theme.buttonCornerRadius == 4.0)
        #expect(!theme.fontBold)
        #expect(theme.displayName == TaskbarStrings.Themes.modernHybrid)
    }
    
    @Test("Retro Classic preset properties")
    func testRetroClassicPresetProperties() {
        let theme = ThemeDefinition.retroClassic
        #expect(theme.id == "retro-classic")
        #expect(theme.style == .retroClassic)
        #expect(!theme.useTranslucency)
        #expect(theme.is3DBeveled)
        #expect(theme.buttonCornerRadius == 0.0)
        #expect(theme.fontBold)
        #expect(abs(theme.backgroundColor.red - (192.0 / 255.0)) < 0.001)
        #expect(abs(theme.backgroundColor.green - (192.0 / 255.0)) < 0.001)
        #expect(abs(theme.backgroundColor.blue - (192.0 / 255.0)) < 0.001)
        #expect(theme.displayName == TaskbarStrings.Themes.retroClassic)
    }
    
    @Test("Windows XP Luna preset properties")
    func testWindowsXPLunaPresetProperties() {
        let theme = ThemeDefinition.windowsXPLuna
        #expect(theme.id == "windows-xp-luna")
        #expect(theme.style == .windowsXPLuna)
        #expect(!theme.useTranslucency)
        #expect(!theme.is3DBeveled)
        #expect(theme.buttonCornerRadius == 3.0)
        #expect(!theme.fontBold)
        #expect(theme.displayName == TaskbarStrings.Themes.windowsXPLuna)
        
        // Verify green Start button tokens
        #expect(theme.palette.startButtonNormal != nil)
        #expect(theme.palette.startButtonHover != nil)
        #expect(theme.palette.startButtonPressed != nil)
        #expect(theme.palette.startButtonText == .white)
    }
    
    @Test("Dark Minimal preset properties")
    func testDarkMinimalPresetProperties() {
        let theme = ThemeDefinition.darkMinimal
        #expect(theme.id == "dark-minimal")
        #expect(theme.style == .darkMinimal)
        #expect(!theme.useTranslucency)
        #expect(!theme.is3DBeveled)
        #expect(theme.buttonCornerRadius == 2.0)
        #expect(!theme.fontBold)
        #expect(theme.displayName == TaskbarStrings.Themes.darkMinimal)
        
        // Verify OLED dark background and cyan accent
        #expect(abs(theme.palette.backgroundColor.red - (18.0 / 255.0)) < 0.001)
        #expect(abs(theme.palette.buttonBorderPressed.blue - (212.0 / 255.0)) < 0.001)
    }
    
    @Test("All presets JSON serialization roundtrip")
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
            #expect(!data.isEmpty, "Encoded data for \(preset.id) should not be empty")
            
            let decoded = try decoder.decode(ThemeDefinition.self, from: data)
            #expect(decoded.id == preset.id)
            #expect(decoded.displayName == preset.displayName)
            #expect(decoded.palette == preset.palette)
            #expect(decoded.metrics == preset.metrics)
            #expect(decoded.materials == preset.materials)
            #expect(decoded == preset)
        }
    }
    
    @Test("Theme forStyle factory method")
    func testThemeForStyleFactory() {
        let styles: [ThemeStyle] = [.modernHybrid, .retroClassic, .windowsXPLuna, .darkMinimal]
        for style in styles {
            let theme = ThemeDefinition.forStyle(style, fontSize: 13.0, iconSize: 18.0)
            #expect(theme.style == style)
            #expect(theme.fontSize == 13.0)
            #expect(theme.iconSize == 18.0)
        }
    }
}
