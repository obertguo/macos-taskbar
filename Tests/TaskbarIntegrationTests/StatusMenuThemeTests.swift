// Tests/TaskbarIntegrationTests/StatusMenuThemeTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("StatusMenu Theme Integration Suite")
@MainActor
struct StatusMenuThemeTests {
    
    @Test("StatusMenu theme submenu contains built-in presets and action items")
    func testStatusMenuThemeSubmenuStructure() {
        let statusMenu = StatusMenu(currentThemeId: ModernHybridTheme.id)
        
        guard let statusItem = Mirror(reflecting: statusMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menu = statusItem.menu,
              let themeItem = menu.items.first(where: { $0.title == TaskbarStrings.StatusMenu.themeMenu }),
              let themeSubmenu = themeItem.submenu else {
            Issue.record("Failed to inspect StatusMenu theme submenu")
            return
        }
        
        let titles = themeSubmenu.items.map { $0.title }
        
        // Verify built-ins
        #expect(titles.contains(TaskbarStrings.Themes.modernHybrid))
        #expect(titles.contains(TaskbarStrings.Themes.retroClassic))
        #expect(titles.contains(TaskbarStrings.Themes.windowsXPLuna))
        #expect(titles.contains(TaskbarStrings.Themes.darkMinimal))
        
        // Verify action items
        #expect(titles.contains(TaskbarStrings.Themes.reloadThemes))
        #expect(titles.contains(TaskbarStrings.Themes.openThemesFolder))
        #expect(titles.contains(TaskbarStrings.Themes.exportCurrentTheme))
        
        // Verify empty state when no custom themes are installed
        #expect(titles.contains(TaskbarStrings.Themes.noCustomThemesFound))
    }
    
    @Test("StatusMenu refreshes dynamically when custom themes are registered")
    func testStatusMenuDynamicCustomThemes() {
        // Register a temporary custom theme
        let customTheme = ThemeDefinition(
            id: "test-cyberpunk",
            displayName: "Cyberpunk Neon",
            isCustom: true,
            palette: ModernHybridTheme.definition.palette,
            metrics: ModernHybridTheme.definition.metrics,
            materials: ModernHybridTheme.definition.materials
        )
        ThemeRegistry.shared.registerCustomThemes([customTheme])
        defer {
            ThemeRegistry.shared.unregisterAllCustomThemes()
        }
        
        let statusMenu = StatusMenu(currentThemeId: "test-cyberpunk")
        
        guard let statusItem = Mirror(reflecting: statusMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menu = statusItem.menu,
              let themeItem = menu.items.first(where: { $0.title == TaskbarStrings.StatusMenu.themeMenu }),
              let themeSubmenu = themeItem.submenu else {
            Issue.record("Failed to inspect StatusMenu theme submenu")
            return
        }
        
        let titles = themeSubmenu.items.map { $0.title }
        #expect(titles.contains("Cyberpunk Neon"))
        #expect(!titles.contains(TaskbarStrings.Themes.noCustomThemesFound))
        
        // Verify custom theme item state is .on
        let customMenuItem = themeSubmenu.items.first(where: { $0.title == "Cyberpunk Neon" })
        #expect(customMenuItem?.state == .on)
    }
    
    @Test("StatusMenu invokes reload callback on action trigger")
    func testStatusMenuReloadCallback() {
        let statusMenu = StatusMenu()
        var reloadCalled = false
        statusMenu.onReloadThemesRequested = {
            reloadCalled = true
        }
        
        guard let statusItem = Mirror(reflecting: statusMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menu = statusItem.menu,
              let themeItem = menu.items.first(where: { $0.title == TaskbarStrings.StatusMenu.themeMenu }),
              let themeSubmenu = themeItem.submenu,
              let reloadItem = themeSubmenu.items.first(where: { $0.title == TaskbarStrings.Themes.reloadThemes }),
              let action = reloadItem.action,
              let target = reloadItem.target else {
            Issue.record("Failed to find reload theme menu item")
            return
        }
        
        _ = (target as AnyObject).perform(action, with: reloadItem)
        #expect(reloadCalled == true)
    }
}
