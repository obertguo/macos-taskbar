// Tests/TaskbarCoreTests/PinnedAppTests.swift

import XCTest
@testable import TaskbarCore

final class PinnedAppTests: XCTestCase {
    
    func testPinnedAppInitialization() {
        let fixedID = UUID()
        let app = PinnedApp(
            id: fixedID,
            bundleIdentifier: "com.apple.calculator",
            displayName: "Calculator",
            customPath: "/Applications/Calculator.app"
        )
        
        XCTAssertEqual(app.id, fixedID)
        XCTAssertEqual(app.bundleIdentifier, "com.apple.calculator")
        XCTAssertEqual(app.displayName, "Calculator")
        XCTAssertEqual(app.customPath, "/Applications/Calculator.app")
    }
    
    func testPinnedAppSerializationRoundTrip() throws {
        let original = PinnedApp(
            bundleIdentifier: "com.google.Chrome",
            displayName: "Google Chrome",
            customPath: "/Applications/Google Chrome.app"
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(original)
        
        let decoded = try JSONDecoder().decode(PinnedApp.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.bundleIdentifier, decoded.bundleIdentifier)
        XCTAssertEqual(original.displayName, decoded.displayName)
        XCTAssertEqual(original.customPath, decoded.customPath)
    }
    
    func testPinnedAppResilientDecoding() throws {
        // Minimal JSON with only bundleIdentifier provided
        let json = """
        {
            "bundleIdentifier": "com.apple.Notes"
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(PinnedApp.self, from: json)
        XCTAssertEqual(decoded.bundleIdentifier, "com.apple.Notes")
        XCTAssertEqual(decoded.displayName, "com.apple.Notes") // Fallback to bundleID
        XCTAssertNil(decoded.customPath)
        XCTAssertFalse(decoded.id.uuidString.isEmpty) // UUID automatically assigned
    }
    
    func testDefaultPinnedApps() {
        let defaults = PinnedApp.defaultPinnedApps
        XCTAssertEqual(defaults.count, 3)
        XCTAssertEqual(defaults[0].bundleIdentifier, "com.apple.finder")
        XCTAssertEqual(defaults[0].displayName, "Finder")
        XCTAssertEqual(defaults[1].bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(defaults[1].displayName, "Safari")
        XCTAssertEqual(defaults[2].bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(defaults[2].displayName, "Terminal")
    }
    
    func testPinAppAndDuplicatePrevention() {
        var settings = Settings.default
        let initialCount = settings.pinnedApps.count
        
        // Pin new app
        let pinned = settings.pinApp(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit")
        XCTAssertTrue(pinned)
        XCTAssertEqual(settings.pinnedApps.count, initialCount + 1)
        XCTAssertTrue(settings.isPinned(bundleIdentifier: "com.apple.TextEdit"))
        
        // Attempt duplicate pin
        let duplicate = settings.pinApp(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit Again")
        XCTAssertFalse(duplicate)
        XCTAssertEqual(settings.pinnedApps.count, initialCount + 1)
    }
    
    func testPinAppModelDirectly() {
        var settings = Settings.default
        let custom = PinnedApp(bundleIdentifier: "com.github.GitHubClient", displayName: "GitHub Desktop")
        
        let added = settings.pinApp(custom)
        XCTAssertTrue(added)
        XCTAssertTrue(settings.isPinned(bundleIdentifier: "com.github.GitHubClient"))
        
        let duplicate = settings.pinApp(custom)
        XCTAssertFalse(duplicate)
    }
    
    func testUnpinApp() {
        var settings = Settings.default
        XCTAssertTrue(settings.isPinned(bundleIdentifier: "com.apple.finder"))
        
        let removed = settings.unpinApp(bundleIdentifier: "com.apple.finder")
        XCTAssertTrue(removed)
        XCTAssertFalse(settings.isPinned(bundleIdentifier: "com.apple.finder"))
        
        // Unpin non-existent app
        let removedAgain = settings.unpinApp(bundleIdentifier: "com.nonexistent.app")
        XCTAssertFalse(removedAgain)
    }
    
    func testMovePinnedApp() {
        var settings = Settings.default
        let originalFirst = settings.pinnedApps[0].bundleIdentifier
        let originalSecond = settings.pinnedApps[1].bundleIdentifier
        
        // Swap first and second
        let moved = settings.movePinnedApp(fromIndex: 0, toIndex: 1)
        XCTAssertTrue(moved)
        XCTAssertEqual(settings.pinnedApps[0].bundleIdentifier, originalSecond)
        XCTAssertEqual(settings.pinnedApps[1].bundleIdentifier, originalFirst)
        
        // Out of bounds checks
        XCTAssertFalse(settings.movePinnedApp(fromIndex: -1, toIndex: 1))
        XCTAssertFalse(settings.movePinnedApp(fromIndex: 0, toIndex: 99))
        XCTAssertFalse(settings.movePinnedApp(fromIndex: 2, toIndex: 2)) // Identical index
    }
    
    func testUserDefaultsPersistenceWithCustomPinnedApps() {
        let testDefaults = UserDefaults(suiteName: "test_pinned_apps_suite")!
        testDefaults.removePersistentDomain(forName: "test_pinned_apps_suite")
        
        var settings = Settings.load(from: testDefaults)
        XCTAssertEqual(settings.pinnedApps, PinnedApp.defaultPinnedApps)
        
        settings.unpinApp(bundleIdentifier: "com.apple.Safari")
        settings.pinApp(bundleIdentifier: "com.apple.Preview", displayName: "Preview")
        settings.save(to: testDefaults)
        
        let reloaded = Settings.load(from: testDefaults)
        XCTAssertFalse(reloaded.isPinned(bundleIdentifier: "com.apple.Safari"))
        XCTAssertTrue(reloaded.isPinned(bundleIdentifier: "com.apple.Preview"))
        XCTAssertEqual(reloaded.pinnedApps.count, 3)
    }
}
