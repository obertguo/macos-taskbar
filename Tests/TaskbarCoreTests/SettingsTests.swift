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
        XCTAssertEqual(defaults.launcherAction, .spotlight)
        XCTAssertTrue(defaults.enableAXNudger)
        XCTAssertTrue(defaults.hideSystemDock)
    }
    
    func testSettingsEncodingDecoding() throws {
        let original = Settings(
            themeStyle: .retroClassic,
            barHeight: 34.0,
            maxButtonWidth: 180.0,
            minButtonWidth: 32.0,
            buttonSpacing: 3.0,
            titleVisibilityThreshold: 45.0,
            launcherAction: .raycast,
            enableAXNudger: false,
            hideSystemDock: false
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    func testUserDefaultsPersistence() {
        let testDefaults = UserDefaults(suiteName: "test_settings_suite")!
        testDefaults.removePersistentDomain(forName: "test_settings_suite")
        
        var settings = Settings.load(from: testDefaults)
        XCTAssertEqual(settings, Settings.default)
        
        settings.themeStyle = .retroClassic
        settings.barHeight = 36.0
        settings.save(to: testDefaults)
        
        let reloaded = Settings.load(from: testDefaults)
        XCTAssertEqual(reloaded.themeStyle, .retroClassic)
        XCTAssertEqual(reloaded.barHeight, 36.0)
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
    }
}
