// Tests/TaskbarIntegrationTests/DeterministicLifecycleTests.swift

import Foundation
import Testing
import CoreGraphics
import TaskbarCore
import TaskbarKit

@Suite("Deterministic Window Lifecycle Suite", .serialized)
@MainActor
struct DeterministicLifecycleTests {
    
    @Test("TC-FUNC-001: Window creation and taskbar store discovery")
    func testWindowCreation() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        source.startTracking()
        #expect(source.isTracking == true)
        
        var changeNotificationCount = 0
        source.onWindowsChanged = {
            changeNotificationCount += 1
        }
        
        let docTitle = "DeterministicDoc_\(UUID().uuidString.prefix(6))"
        let window = source.addWindow(
            id: 1001,
            pid: 42,
            appName: "TextEdit",
            bundleID: "com.apple.TextEdit",
            title: docTitle,
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isMain: true
        )
        
        #expect(store.totalWindowCount == 1, "WindowStore should register exactly 1 window")
        #expect(store.allWindows.contains { $0.title == docTitle && $0.appName == "TextEdit" })
        #expect(store.window(forKey: window.key)?.title == docTitle)
        #expect(store.focusedWindowKey == window.key, "Main window should be marked as focused")
        #expect(changeNotificationCount == 1, "onWindowsChanged callback must be triggered on window addition")
    }
    
    @Test("TC-FUNC-002: Window minimization state tracking")
    func testWindowMinimization() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let spyActions = SpyWindowActions()
        source.startTracking()
        
        let window = source.addWindow(
            id: 2001,
            pid: 42,
            appName: "TextEdit",
            title: "MiniDoc",
            isMinimized: false,
            isMain: true
        )
        #expect(store.window(forKey: window.key)?.isMinimized == false)
        #expect(store.focusedWindowKey == window.key)
        
        // Dispatch minimize through WindowActionPerforming spy
        spyActions.minimizeWindow(window.key)
        #expect(spyActions.invocations.contains(.minimizeWindow(window.key)))
        
        // Update window source state
        var changeCount = 0
        source.onWindowsChanged = { changeCount += 1 }
        source.setMinimized(key: window.key, isMinimized: true)
        
        #expect(store.window(forKey: window.key)?.isMinimized == true)
        #expect(store.focusedWindowKey == nil, "Minimized window should lose focus in WindowStore")
        #expect(changeCount == 1, "onWindowsChanged must be called when minimized state changes")
    }
    
    @Test("TC-FUNC-003: Window restoration / deminiaturization state tracking")
    func testWindowRestoration() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let spyActions = SpyWindowActions()
        source.startTracking()
        
        let window = source.addWindow(
            id: 3001,
            pid: 42,
            appName: "TextEdit",
            title: "RestoreDoc",
            isMinimized: true
        )
        #expect(store.window(forKey: window.key)?.isMinimized == true)
        
        // Dispatch restoreAndFocus action through WindowActionPerforming spy
        spyActions.restoreAndFocusWindow(window.key)
        #expect(spyActions.invocations.contains(.restoreAndFocusWindow(window.key)))
        
        // Update window source state
        var changeCount = 0
        source.onWindowsChanged = { changeCount += 1 }
        source.setMinimized(key: window.key, isMinimized: false)
        source.setFocused(key: window.key)
        
        #expect(store.window(forKey: window.key)?.isMinimized == false)
        #expect(store.focusedWindowKey == window.key)
        #expect(changeCount == 2, "onWindowsChanged must be called on deminimization and focus update")
    }
    
    @Test("TC-FUNC-004: Window focus targeting specific window without raising other windows")
    func testSingleWindowFocusIsolation() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let spyActions = SpyWindowActions()
        source.startTracking()
        
        let doc1 = source.addWindow(id: 4001, pid: 42, appName: "TextEdit", title: "Doc1", isMain: false)
        let doc2 = source.addWindow(id: 4002, pid: 42, appName: "TextEdit", title: "Doc2", isMain: false)
        
        #expect(store.totalWindowCount == 2)
        
        // Target Doc1 specifically
        spyActions.performAction(.focus, for: doc1.key)
        #expect(spyActions.invocations.contains(.performAction(.focus, doc1.key)))
        #expect(!spyActions.invocations.contains(.performAction(.focus, doc2.key)), "Doc2 must not be targeted")
        
        // Apply focus to Doc1
        source.setFocused(key: doc1.key)
        #expect(store.focusedWindowKey == doc1.key)
        
        let win1 = store.window(forKey: doc1.key)
        let win2 = store.window(forKey: doc2.key)
        #expect((win1?.focusOrder ?? 0) > (win2?.focusOrder ?? 0), "Doc1 focusOrder must exceed Doc2")
        #expect(win2?.focusOrder == 0, "Doc2 focusOrder must remain 0")
    }
    
    @Test("TC-FUNC-005: Dynamic window title mutation")
    func testWindowTitleMutation() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        source.startTracking()
        
        let window = source.addWindow(id: 5001, pid: 42, appName: "TextEdit", title: "TitleA")
        #expect(store.window(forKey: window.key)?.title == "TitleA")
        
        var changeCount = 0
        source.onWindowsChanged = { changeCount += 1 }
        
        source.updateTitle(key: window.key, newTitle: "TitleB")
        #expect(store.window(forKey: window.key)?.title == "TitleB")
        #expect(changeCount == 1, "onWindowsChanged must trigger after title update")
    }
    
    @Test("TC-FUNC-006: Window close and taskbar store teardown")
    func testWindowClose() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let spyActions = SpyWindowActions()
        source.startTracking()
        
        let window = source.addWindow(id: 6001, pid: 42, appName: "TextEdit", title: "CloseDoc", isMain: true)
        #expect(store.totalWindowCount == 1)
        #expect(store.focusedWindowKey == window.key)
        
        // Close window through WindowActionPerforming spy
        spyActions.closeWindow(window.key)
        #expect(spyActions.invocations.contains(.closeWindow(window.key)))
        
        var changeCount = 0
        source.onWindowsChanged = { changeCount += 1 }
        
        source.removeWindow(key: window.key)
        #expect(store.totalWindowCount == 0, "Store should have 0 windows after close")
        #expect(store.window(forKey: window.key) == nil)
        #expect(store.focusedWindowKey == nil, "Closing focused window should clear focusedWindowKey")
        #expect(changeCount == 1, "onWindowsChanged must trigger after window removal")
    }
    
    @Test("TC-FUNC-007: Application termination and observer cleanup")
    func testApplicationTermination() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let spyActions = SpyWindowActions()
        source.startTracking()
        
        _ = source.addWindow(id: 7001, pid: 88, appName: "Safari", bundleID: "com.apple.Safari", title: "Tab 1")
        _ = source.addWindow(id: 7002, pid: 88, appName: "Safari", bundleID: "com.apple.Safari", title: "Tab 2")
        let finderWin = source.addWindow(id: 7003, pid: 99, appName: "Finder", bundleID: "com.apple.finder", title: "Downloads")
        
        #expect(store.totalWindowCount == 3)
        
        // Quit Safari via WindowActionPerforming spy
        spyActions.quitApplication(pid: 88)
        #expect(spyActions.invocations.contains(.quitApplication(pid: 88)))
        
        var changeCount = 0
        source.onWindowsChanged = { changeCount += 1 }
        
        source.removeAllWindows(forPID: 88)
        #expect(store.totalWindowCount == 1)
        #expect(store.allWindows.contains { $0.key == finderWin.key })
        #expect(!store.allWindows.contains { $0.pid == 88 })
        #expect(changeCount == 1)
        
        // Stop tracking / observer cleanup
        source.stopTracking()
        #expect(source.isTracking == false)
    }
}
