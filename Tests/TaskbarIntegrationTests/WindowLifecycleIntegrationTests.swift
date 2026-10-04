// Tests/TaskbarIntegrationTests/WindowLifecycleIntegrationTests.swift

import Foundation
import Testing
import AppKit
import TaskbarCore
import TaskbarKit

@Suite("Window Lifecycle Integration Suite", .serialized)
@MainActor
struct WindowLifecycleIntegrationTests {
    
    /// Helper to wait asynchronously until a condition is met or timeout expires.
    private func waitUntil(
        timeoutSeconds: Double = 5.0,
        intervalSeconds: Double = 0.05,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            await Task.yield()
        }
        return condition()
    }
    
    @Test("TC-FUNC-001: Window creation and taskbar store discovery")
    func testWindowCreation() async throws {
        guard AccessibilityPermission.isGranted() else {
            print("Skipping TC-FUNC-001: Accessibility permission not granted in current test environment.")
            return
        }
        
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        let uniqueTitle = "TaskbarDoc_\(UUID().uuidString.prefix(6))"
        let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: uniqueTitle)
        defer { fixture.terminate() }
        
        let discovered = await waitUntil(timeoutSeconds: 3.0) {
            store.allWindows.contains { $0.title.contains(uniqueTitle) || $0.appName == "TextEdit" }
        }
        
        #expect(discovered == true, "Taskbar should discover TextEdit window within 3 seconds")
    }
    
    @Test("TC-FUNC-002: Window minimization state tracking")
    func testWindowMinimization() async throws {
        guard AccessibilityPermission.isGranted() else {
            print("Skipping TC-FUNC-002: Accessibility permission not granted.")
            return
        }
        
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        let uniqueTitle = "MiniDoc_\(UUID().uuidString.prefix(6))"
        let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: uniqueTitle)
        defer { fixture.terminate() }
        
        // Ensure window is tracked first
        let ready = await waitUntil {
            store.allWindows.contains { $0.appName == "TextEdit" }
        }
        #expect(ready == true)
        
        // Minimize window
        try fixture.minimizeWindow(index: 1)
        
        // Verify store updates minimization state
        let minimized = await waitUntil(timeoutSeconds: 3.0) {
            store.allWindows.first(where: { $0.appName == "TextEdit" })?.isMinimized == true
        }
        #expect(minimized == true, "WindowStore should record isMinimized == true")
    }
    
    @Test("TC-FUNC-003: Window restoration / deminiaturization state tracking")
    func testWindowRestoration() async throws {
        guard AccessibilityPermission.isGranted() else {
            print("Skipping TC-FUNC-003: Accessibility permission not granted.")
            return
        }
        
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        let uniqueTitle = "RestoreDoc_\(UUID().uuidString.prefix(6))"
        let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: uniqueTitle)
        defer { fixture.terminate() }
        
        // Minimize then restore
        try fixture.minimizeWindow(index: 1)
        _ = await waitUntil {
            store.allWindows.first(where: { $0.appName == "TextEdit" })?.isMinimized == true
        }
        
        try fixture.restoreWindow(index: 1)
        
        let restored = await waitUntil(timeoutSeconds: 3.0) {
            guard let win = store.allWindows.first(where: { $0.appName == "TextEdit" }) else { return false }
            return !win.isMinimized
        }
        #expect(restored == true, "WindowStore should record isMinimized == false after restore")
    }
    
    @Test("TC-FUNC-004: Window focus targeting specific window without raising other windows of the same application")
    func testSingleWindowFocusIsolation() async throws {
        guard AccessibilityPermission.isGranted() else {
            print("Skipping TC-FUNC-004: Accessibility permission not granted.")
            return
        }
        
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        let doc1Title = "FocusDoc1_\(UUID().uuidString.prefix(6))"
        let doc2Title = "FocusDoc2_\(UUID().uuidString.prefix(6))"
        
        let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: doc1Title)
        defer { fixture.terminate() }
        
        try fixture.createDocument(documentTitle: doc2Title)
        
        // Wait for both windows to be discovered in WindowStore
        let bothDiscovered = await waitUntil(timeoutSeconds: 3.0) {
            store.allWindows.contains { $0.title.contains(doc1Title) } &&
            store.allWindows.contains { $0.title.contains(doc2Title) }
        }
        #expect(bothDiscovered == true, "Both document windows should be tracked in store")
        
        guard let win2Info = store.allWindows.first(where: { $0.title.contains(doc2Title) }) else {
            Issue.record("Failed to find second document in WindowStore")
            return
        }
        
        // Focus the second window via WindowActions
        WindowActions.performAction(.focus, for: win2Info.key)
        
        // Verify target application is activated
        let focused = await waitUntil(timeoutSeconds: 3.0) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        }
        #expect(focused == true, "Target application should be activated")
    }
    
    @Test("TC-FUNC-005: Dynamic window title mutation")
    func testWindowTitleMutation() async throws {
        guard AccessibilityPermission.isGranted() else {
            print("Skipping TC-FUNC-005: Accessibility permission not granted.")
            return
        }
        
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        let initialTitle = "TitleA_\(UUID().uuidString.prefix(6))"
        let updatedTitle = "TitleB_\(UUID().uuidString.prefix(6))"
        
        let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: initialTitle)
        defer { fixture.terminate() }
        
        _ = await waitUntil {
            store.allWindows.contains { $0.appName == "TextEdit" }
        }
        
        // Mutate title
        try fixture.setTitle(updatedTitle, index: 1)
        
        let titleChanged = await waitUntil(timeoutSeconds: 3.0) {
            store.allWindows.contains { $0.appName == "TextEdit" && $0.title.contains(updatedTitle) }
        }
        #expect(titleChanged == true, "WindowStore should update window title to \(updatedTitle)")
    }
    
    @Test("TC-FUNC-006: Window close and taskbar store teardown")
    func testWindowClose() async throws {
        guard AccessibilityPermission.isGranted() else {
            print("Skipping TC-FUNC-006: Accessibility permission not granted.")
            return
        }
        
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        let title = "CloseDoc_\(UUID().uuidString.prefix(6))"
        let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: title)
        defer { fixture.terminate() }
        
        _ = await waitUntil {
            store.allWindows.contains { $0.appName == "TextEdit" }
        }
        
        // Close the window
        try fixture.closeWindow(index: 1)
        
        let closed = await waitUntil(timeoutSeconds: 3.0) {
            !store.allWindows.contains { $0.appName == "TextEdit" && $0.title.contains(title) }
        }
        #expect(closed == true, "WindowStore should remove window after it is closed")
    }
    
    @Test("TC-FUNC-007: Application termination and observer cleanup")
    func testApplicationTermination() async throws {
        guard AccessibilityPermission.isGranted() else {
            print("Skipping TC-FUNC-007: Accessibility permission not granted.")
            return
        }
        
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        let title = "QuitDoc_\(UUID().uuidString.prefix(6))"
        let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: title)
        
        _ = await waitUntil {
            store.allWindows.contains { $0.appName == "TextEdit" }
        }
        
        // Terminate TextEdit
        fixture.terminate()
        
        let cleared = await waitUntil(timeoutSeconds: 3.0) {
            !store.allWindows.contains { $0.appName == "TextEdit" }
        }
        #expect(cleared == true, "WindowStore should purge all windows when application terminates")
    }
}
