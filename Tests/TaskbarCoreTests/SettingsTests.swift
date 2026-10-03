// Tests/TaskbarCoreTests/SettingsTests.swift

import XCTest
@testable import TaskbarCore

final class SettingsTests: XCTestCase {
    func testDefaultSettings() {
        let defaults = Settings.default
        XCTAssertEqual(defaults.themeStyle, .modernHybrid)
        XCTAssertEqual(defaults.barHeight, 30.0)
        XCTAssertEqual(defaults.maxButtonWidth, 160.0)
        XCTAssertEqual(defaults.minButtonWidth, 28.0)
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
}
