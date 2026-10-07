// Tests/TaskbarCoreTests/SettingsTests.swift

import XCTest
@testable import TaskbarCore

final class SettingsTests: XCTestCase {
    func testDefaultSettings() {
        let defaults = Settings.default
        XCTAssertEqual(defaults.themeStyle, .modernHybrid)
        XCTAssertEqual(defaults.barHeight, TaskbarConstants.Layout.defaultBarHeight)
        XCTAssertEqual(defaults.maxButtonWidth, TaskbarConstants.Layout.defaultMaxButtonWidth)
        XCTAssertEqual(defaults.minButtonWidth, TaskbarConstants.Layout.defaultMinButtonWidth)
        XCTAssertEqual(defaults.buttonSpacing, TaskbarConstants.Layout.defaultButtonSpacing)
        XCTAssertEqual(defaults.titleVisibilityThreshold, TaskbarConstants.Layout.defaultTitleVisibilityThreshold)
        XCTAssertEqual(defaults.fontSize, TaskbarConstants.Layout.defaultFontSize)
        XCTAssertEqual(defaults.iconSize, TaskbarConstants.Layout.defaultIconSize)
        XCTAssertEqual(defaults.launcherAction, .spotlight)
        XCTAssertTrue(defaults.enableAXNudger)
        XCTAssertTrue(defaults.hideSystemDock)
        XCTAssertEqual(defaults.dockHideDelay, TaskbarConstants.Dock.defaultAutohideDelaySeconds)
        XCTAssertEqual(defaults.pinnedApps, PinnedApp.defaultPinnedApps)
        XCTAssertEqual(defaults.windowGroupingMode, .always)
    }
    
    func testSettingsEncodingDecoding() throws {
        let original = Settings(
            themeStyle: .retroClassic,
            barHeight: 34.0,
            maxButtonWidth: 180.0,
            minButtonWidth: 32.0,
            buttonSpacing: 3.0,
            titleVisibilityThreshold: 45.0,
            fontSize: 12.0,
            iconSize: 20.0,
            launcherAction: .raycast,
            enableAXNudger: false,
            hideSystemDock: true,
            dockHideDelay: 1.5,
            pinnedApps: [
                PinnedApp(bundleIdentifier: "com.apple.Maps", displayName: "Maps")
            ]
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    func testBackwardCompatibleDecodingWithoutDockHideDelay() throws {
        // Simulates persisted settings from older versions lacking dockHideDelay key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "dockHideDelay")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        XCTAssertEqual(decoded.dockHideDelay, TaskbarConstants.Dock.defaultAutohideDelaySeconds)
    }
    
    func testBackwardCompatibleDecodingWithoutPinnedApps() throws {
        // Simulates persisted settings from older versions lacking pinnedApps key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "pinnedApps")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        XCTAssertEqual(decoded.pinnedApps, PinnedApp.defaultPinnedApps)
    }
    
    func testBackwardCompatibleDecodingWithoutWindowGroupingMode() throws {
        // Simulates persisted settings from older versions lacking windowGroupingMode key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "windowGroupingMode")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        XCTAssertEqual(decoded.windowGroupingMode, .always)
    }
    
    func testUserDefaultsPersistence() {
        let testDefaults = UserDefaults(suiteName: "test_settings_suite")!
        testDefaults.removePersistentDomain(forName: "test_settings_suite")
        
        var settings = Settings.load(from: testDefaults)
        XCTAssertEqual(settings, Settings.default)
        
        settings.themeStyle = .retroClassic
        settings.barHeight = 36.0
        settings.fontSize = 13.0
        settings.iconSize = 18.0
        settings.dockHideDelay = 1.0
        settings.save(to: testDefaults)
        
        let reloaded = Settings.load(from: testDefaults)
        XCTAssertEqual(reloaded.themeStyle, .retroClassic)
        XCTAssertEqual(reloaded.barHeight, 36.0)
        XCTAssertEqual(reloaded.fontSize, 13.0)
        XCTAssertEqual(reloaded.iconSize, 18.0)
        XCTAssertEqual(reloaded.dockHideDelay, 1.0)
    }
    
    func testTaskbarStringsAndPresets() {
        XCTAssertEqual(TaskbarStrings.StartButton.title, "Start")
        XCTAssertEqual(TaskbarStrings.Overflow.buttonGlyph, "»")
        XCTAssertEqual(ThemeStyle.modernHybrid.displayName, TaskbarStrings.Themes.modernHybrid)
        XCTAssertEqual(ThemeStyle.retroClassic.displayName, TaskbarStrings.Themes.retroClassic)
        
        // Ensure barHeightPresets contains the defaultBarHeight
        let heights = TaskbarConstants.Layout.barHeightPresets.map { $0.height }
        XCTAssertTrue(heights.contains(TaskbarConstants.Layout.defaultBarHeight))
        
        // Ensure buttonWidthPresets contains the defaultMinButtonWidth
        let widths = TaskbarConstants.Layout.buttonWidthPresets.map { $0.width }
        XCTAssertTrue(widths.contains(TaskbarConstants.Layout.defaultMinButtonWidth))
        
        // Ensure fontSizePresets contains the defaultFontSize
        let fontSizes = TaskbarConstants.Layout.fontSizePresets.map { $0.size }
        XCTAssertTrue(fontSizes.contains(TaskbarConstants.Layout.defaultFontSize))
        
        // Ensure iconSizePresets contains the defaultIconSize
        let iconSizes = TaskbarConstants.Layout.iconSizePresets.map { $0.size }
        XCTAssertTrue(iconSizes.contains(TaskbarConstants.Layout.defaultIconSize))
        
        // Ensure dockDelayPresets contains defaultAutohideDelaySeconds
        let dockDelays = TaskbarConstants.Dock.dockDelayPresets.map { $0.delay }
        XCTAssertTrue(dockDelays.contains(TaskbarConstants.Dock.defaultAutohideDelaySeconds))
    }
}
