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
        
        guard let win1Info = store.allWindows.first(where: { $0.title.contains(doc1Title) }),
              let win2Info = store.allWindows.first(where: { $0.title.contains(doc2Title) }) else {
            Issue.record("Failed to find both documents in WindowStore")
            return
        }
        
        // Introduce an intervening Finder window in front of TextEdit
        let openFinderProc = Process()
        openFinderProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        openFinderProc.arguments = ["-e", "tell application \"Finder\" to activate\ntell application \"Finder\" to make new Finder window to desktop\nreturn \"\""]
        try openFinderProc.run()
        openFinderProc.waitUntilExit()
        
        defer {
            let closeFinderProc = Process()
            closeFinderProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            closeFinderProc.arguments = ["-e", "tell application \"Finder\"\nif (count of windows) > 0 then close front window\nend tell"]
            try? closeFinderProc.run()
            closeFinderProc.waitUntilExit()
        }
        
        let finderActivated = await waitUntil(timeoutSeconds: 3.0) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        }
        #expect(finderActivated == true, "Intervening Finder window should become frontmost")
        
        // Helper to query on-screen z-order of target windows
        func getZOrder(ids: [UInt64]) -> [UInt64] {
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
                return []
            }
            var result: [UInt64] = []
            for dict in list {
                guard let layer = dict[kCGWindowLayer] as? Int, layer == 0,
                      let wid = dict[kCGWindowNumber] as? CGWindowID else {
                    continue
                }
                let id64 = UInt64(wid)
                if ids.contains(id64) {
                    result.append(id64)
                }
            }
            return result
        }
        
        // Find the Finder window ID with retry
        var finderWid: CGWindowID?
        let foundFinder = await waitUntil(timeoutSeconds: 3.0) {
            guard let finderApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }),
                  let finderList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]],
                  let wid = finderList.first(where: {
                      ($0[kCGWindowLayer] as? Int == 0) && (($0[kCGWindowOwnerPID] as? pid_t) == finderApp.processIdentifier)
                  })?[kCGWindowNumber] as? CGWindowID else {
                return false
            }
            finderWid = wid
            return true
        }
        #expect(foundFinder == true, "Finder window must be present in on-screen window list")
        
        guard let resolvedFinderWid = finderWid else {
            Issue.record("Failed to locate intervening Finder window")
            return
        }
        
        let finderWid64 = UInt64(resolvedFinderWid)
        
        // Ensure Finder window presentation and activation has fully settled
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Target: Focus doc1 only. Doc 2 must NOT be raised above the intervening Finder window.
        WindowActions.performAction(.focus, for: win1Info.key)
        
        let textEditFocused = await waitUntil(timeoutSeconds: 3.0) {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit"
        }
        #expect(textEditFocused == true, "TextEdit should be the active application")
        
        // Wait for z-order to settle in WindowServer
        let doc1Frontmost = await waitUntil(timeoutSeconds: 3.0) {
            let z = getZOrder(ids: [win1Info.key.id, finderWid64, win2Info.key.id])
            return z.first == win1Info.key.id
        }
        #expect(doc1Frontmost == true, "Target doc 1 should be frontmost in z-order")
        
        let zOrder = getZOrder(ids: [win1Info.key.id, finderWid64, win2Info.key.id])
        
        // Finder must remain ahead of Doc 2 (Doc 2 must NOT have been raised above Finder)
        if let finderIndex = zOrder.firstIndex(of: finderWid64),
           let doc2Index = zOrder.firstIndex(of: win2Info.key.id) {
            #expect(finderIndex < doc2Index, "Intervening Finder window must remain above background Doc 2")
        } else {
            Issue.record("Both Finder and Doc 2 should be present in on-screen z-order")
        }
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
