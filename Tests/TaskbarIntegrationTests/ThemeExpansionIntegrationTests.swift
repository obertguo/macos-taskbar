// Tests/TaskbarIntegrationTests/ThemeExpansionIntegrationTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("Theme Expansion Integration Suite")
@MainActor
struct ThemeExpansionIntegrationTests {
    
    @Test("Switching themes propagates Windows XP Luna and Dark Minimal across all display panels")
    func testScreenManagerThemeSwitching() {
        let settings = Settings(activeThemeId: ModernHybridTheme.id)
        let store = WindowStore()
        let manager = ScreenManager(settings: settings, store: store)
        defer { manager.closeAll() }
        
        let initialPanels = manager.allPanels
        #expect(!initialPanels.isEmpty)
        for panel in initialPanels {
            #expect(panel.taskbarView.theme.id == ModernHybridTheme.id)
        }
        
        // Switch to Windows XP Luna
        manager.updateTheme(themeId: WindowsXPLunaTheme.id)
        for panel in manager.allPanels {
            #expect(panel.taskbarView.theme.id == WindowsXPLunaTheme.id)
            #expect(panel.taskbarView.theme.palette.backgroundColor == WindowsXPLunaTheme.definition.palette.backgroundColor)
        }
        
        // Switch to Dark Minimal
        manager.updateTheme(themeId: DarkMinimalTheme.id)
        for panel in manager.allPanels {
            #expect(panel.taskbarView.theme.id == DarkMinimalTheme.id)
            #expect(panel.taskbarView.theme.palette.backgroundColor == DarkMinimalTheme.definition.palette.backgroundColor)
        }
    }
    
    @Test("ThemeFileLoader discovers valid custom JSON and handles corrupted JSON safely")
    func testThemeFileLoaderCustomThemeLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("taskbar_theme_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let loader = ThemeFileLoader(directory: tempDir)
        
        // 1. Write a valid custom theme JSON
        let validTheme = ThemeDefinition(
            id: "custom-neon-matrix",
            displayName: "Neon Matrix",
            isCustom: true,
            palette: ThemePalette(
                backgroundColor: RGBAColor(red: 0.0, green: 0.1, blue: 0.0, alpha: 0.95),
                topBorderColor: RGBAColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 0.5),
                textNormal: RGBAColor(red: 0.0, green: 1.0, blue: 0.2, alpha: 1.0),
                textPressed: RGBAColor(red: 0.0, green: 1.0, blue: 0.5, alpha: 1.0),
                buttonNormal: RGBAColor(red: 0.0, green: 0.2, blue: 0.0, alpha: 0.8),
                buttonHover: RGBAColor(red: 0.0, green: 0.3, blue: 0.0, alpha: 0.9),
                buttonPressed: RGBAColor(red: 0.0, green: 0.4, blue: 0.0, alpha: 1.0),
                buttonBorderNormal: RGBAColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.7),
                buttonBorderPressed: RGBAColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
            ),
            metrics: ModernHybridTheme.definition.metrics,
            materials: ModernHybridTheme.definition.materials
        )
        try loader.exportThemeToCustomDirectory(validTheme)
        
        // 2. Write an invalid / corrupted JSON file
        let corruptFileURL = tempDir.appendingPathComponent("corrupted_theme.json")
        try "{\"id\": \"corrupt\", \"palette\": { invalid json ... }".write(to: corruptFileURL, atomically: true, encoding: .utf8)
        
        // 3. Write a non-JSON file that should be ignored
        let ignoredFileURL = tempDir.appendingPathComponent("notes.txt")
        try "Just some notes".write(to: ignoredFileURL, atomically: true, encoding: .utf8)
        
        // Discover themes
        let discovered = loader.discoverCustomThemes()
        #expect(discovered.count == 1)
        #expect(discovered.first?.id == "custom-neon-matrix")
        #expect(discovered.first?.isCustom == true)
        
        // 4. Reload into ThemeRegistry and apply to ScreenManager
        loader.reloadCustomThemes()
        defer { ThemeRegistry.shared.unregisterAllCustomThemes() }
        
        let settings = Settings(activeThemeId: "custom-neon-matrix")
        let store = WindowStore()
        let manager = ScreenManager(settings: settings, store: store)
        defer { manager.closeAll() }
        
        for panel in manager.allPanels {
            #expect(panel.taskbarView.theme.id == "custom-neon-matrix")
            #expect(panel.taskbarView.theme.displayName == "Neon Matrix")
        }
    }
}
