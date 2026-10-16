// Tests/TaskbarCoreTests/PinnedAppTests.swift

import Foundation
import Testing
@testable import TaskbarCore

@Suite("Pinned App Tests")
struct PinnedAppTests {
    
    @Test("Pinned app model initialization")
    func testPinnedAppInitialization() {
        let fixedID = UUID()
        let app = PinnedApp(
            id: fixedID,
            bundleIdentifier: "com.apple.calculator",
            displayName: "Calculator",
            customPath: "/Applications/Calculator.app"
        )
        
        #expect(app.id == fixedID)
        #expect(app.bundleIdentifier == "com.apple.calculator")
        #expect(app.displayName == "Calculator")
        #expect(app.customPath == "/Applications/Calculator.app")
    }
    
    @Test("Pinned app serialization round trip")
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
        #expect(original == decoded)
        #expect(original.id == decoded.id)
        #expect(original.bundleIdentifier == decoded.bundleIdentifier)
        #expect(original.displayName == decoded.displayName)
        #expect(original.customPath == decoded.customPath)
    }
    
    @Test("Pinned app resilient decoding from minimal JSON")
    func testPinnedAppResilientDecoding() throws {
        // Minimal JSON with only bundleIdentifier provided
        let json = """
        {
            "bundleIdentifier": "com.apple.Notes"
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(PinnedApp.self, from: json)
        #expect(decoded.bundleIdentifier == "com.apple.Notes")
        #expect(decoded.displayName == "com.apple.Notes") // Fallback to bundleID
        #expect(decoded.customPath == nil)
        #expect(!decoded.id.uuidString.isEmpty) // UUID automatically assigned
    }
    
    @Test("Default pinned apps list")
    func testDefaultPinnedApps() {
        let defaults = PinnedApp.defaultPinnedApps
        #expect(defaults.count == 3)
        #expect(defaults[0].bundleIdentifier == "com.apple.finder")
        #expect(defaults[0].displayName == "Finder")
        #expect(defaults[1].bundleIdentifier == "com.apple.Safari")
        #expect(defaults[1].displayName == "Safari")
        #expect(defaults[2].bundleIdentifier == "com.apple.Terminal")
        #expect(defaults[2].displayName == "Terminal")
    }
    
    @Test("Pin app and duplicate prevention")
    func testPinAppAndDuplicatePrevention() {
        var settings = Settings.default
        let initialCount = settings.pinnedApps.count
        
        // Pin new app
        let pinned = settings.pinApp(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit")
        #expect(pinned)
        #expect(settings.pinnedApps.count == initialCount + 1)
        #expect(settings.isPinned(bundleIdentifier: "com.apple.TextEdit"))
        
        // Attempt duplicate pin
        let duplicate = settings.pinApp(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit Again")
        #expect(!duplicate)
        #expect(settings.pinnedApps.count == initialCount + 1)
    }
    
    @Test("Pin app model directly")
    func testPinAppModelDirectly() {
        var settings = Settings.default
        let custom = PinnedApp(bundleIdentifier: "com.github.GitHubClient", displayName: "GitHub Desktop")
        
        let added = settings.pinApp(custom)
        #expect(added)
        #expect(settings.isPinned(bundleIdentifier: "com.github.GitHubClient"))
        
        let duplicate = settings.pinApp(custom)
        #expect(!duplicate)
    }
    
    @Test("Unpin app")
    func testUnpinApp() {
        var settings = Settings.default
        #expect(settings.isPinned(bundleIdentifier: "com.apple.finder"))
        
        let removed = settings.unpinApp(bundleIdentifier: "com.apple.finder")
        #expect(removed)
        #expect(!settings.isPinned(bundleIdentifier: "com.apple.finder"))
        
        // Unpin non-existent app
        let removedAgain = settings.unpinApp(bundleIdentifier: "com.nonexistent.app")
        #expect(!removedAgain)
    }
    
    @Test("Move pinned app reorders correctly")
    func testMovePinnedApp() {
        var settings = Settings.default
        let originalFirst = settings.pinnedApps[0].bundleIdentifier
        let originalSecond = settings.pinnedApps[1].bundleIdentifier
        
        // Swap first and second
        let moved = settings.movePinnedApp(fromIndex: 0, toIndex: 1)
        #expect(moved)
        #expect(settings.pinnedApps[0].bundleIdentifier == originalSecond)
        #expect(settings.pinnedApps[1].bundleIdentifier == originalFirst)
        
        // Out of bounds checks
        let movedNegative = settings.movePinnedApp(fromIndex: -1, toIndex: 1)
        #expect(!movedNegative)
        let movedOOB = settings.movePinnedApp(fromIndex: 0, toIndex: 99)
        #expect(!movedOOB)
        let movedSame = settings.movePinnedApp(fromIndex: 2, toIndex: 2) // Identical index
        #expect(!movedSame)
    }
    
    @Test("UserDefaults persistence with custom pinned apps")
    func testUserDefaultsPersistenceWithCustomPinnedApps() {
        let suiteName = "test_pinned_apps_suite_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        
        var settings = Settings.load(from: testDefaults)
        #expect(settings.pinnedApps == PinnedApp.defaultPinnedApps)
        
        settings.unpinApp(bundleIdentifier: "com.apple.Safari")
        settings.pinApp(bundleIdentifier: "com.apple.Preview", displayName: "Preview")
        settings.save(to: testDefaults)
        
        let reloaded = Settings.load(from: testDefaults)
        #expect(!reloaded.isPinned(bundleIdentifier: "com.apple.Safari"))
        #expect(reloaded.isPinned(bundleIdentifier: "com.apple.Preview"))
        #expect(reloaded.pinnedApps.count == 3)
    }
}
