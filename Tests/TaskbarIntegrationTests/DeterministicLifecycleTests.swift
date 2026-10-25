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
        AppEnvironment.testLock.lock()
        let spyActions = SpyWindowActions()
        AppEnvironment.current = AppEnvironment(windowActions: spyActions)
        defer {
            AppEnvironment.reset()
            AppEnvironment.testLock.unlock()
        }
        
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight, store: store)
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
        
        view.updateWindows(windows: store.allWindows, focusedKey: store.focusedWindowKey, frontmostPID: store.frontmostPID)
        #expect(view.taskButtons.count == 1)
        
        // Dispatch minimize through TaskButton interaction
        let btn = view.taskButtons[0]
        btn.onMinimizeOrRestore?()
        #expect(spyActions.invocations.contains(.minimizeWindow(key: window.key)))
        
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
        AppEnvironment.testLock.lock()
        let spyActions = SpyWindowActions()
        AppEnvironment.current = AppEnvironment(windowActions: spyActions)
        defer {
            AppEnvironment.reset()
            AppEnvironment.testLock.unlock()
        }
        
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight, store: store)
        source.startTracking()
        
        let window = source.addWindow(
            id: 3001,
            pid: 42,
            appName: "TextEdit",
            title: "RestoreDoc",
            isMinimized: true
        )
        #expect(store.window(forKey: window.key)?.isMinimized == true)
        
        view.updateWindows(windows: store.allWindows, focusedKey: store.focusedWindowKey, frontmostPID: store.frontmostPID)
        #expect(view.taskButtons.count == 1)
        
        // Dispatch restoreAndFocus action through TaskButton interaction
        let btn = view.taskButtons[0]
        btn.onMinimizeOrRestore?()
        #expect(spyActions.invocations.contains(.restoreAndFocusWindow(key: window.key)))
        
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
        AppEnvironment.testLock.lock()
        let spyActions = SpyWindowActions()
        AppEnvironment.current = AppEnvironment(windowActions: spyActions)
        defer {
            AppEnvironment.reset()
            AppEnvironment.testLock.unlock()
        }
        
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight, groupingMode: .never, store: store)
        source.startTracking()
        
        let doc1 = source.addWindow(id: 4001, pid: 42, appName: "TextEdit", title: "Doc1", isMain: false)
        let doc2 = source.addWindow(id: 4002, pid: 42, appName: "TextEdit", title: "Doc2", isMain: false)
        
        #expect(store.totalWindowCount == 2)
        
        view.updateWindows(windows: store.allWindows, focusedKey: store.focusedWindowKey, frontmostPID: store.frontmostPID)
        #expect(view.taskButtons.count == 2)
        
        // Target Doc1 specifically by clicking its button
        let btn1 = view.taskButtons.first { $0.group.primaryWindow?.key == doc1.key }
        btn1?.onClick?()
        
        let doc1Targeted = spyActions.invocations.contains { invocation in
            if case let .performAction(_, key) = invocation { return key == doc1.key }
            if case let .focusWindow(key) = invocation { return key == doc1.key }
            if case let .restoreAndFocusWindow(key) = invocation { return key == doc1.key }
            return false
        }
        #expect(doc1Targeted, "Doc1 must be targeted via windowActions")
        
        let doc2Targeted = spyActions.invocations.contains { invocation in
            if case let .performAction(_, key) = invocation { return key == doc2.key }
            if case let .focusWindow(key) = invocation { return key == doc2.key }
            if case let .restoreAndFocusWindow(key) = invocation { return key == doc2.key }
            return false
        }
        #expect(!doc2Targeted, "Doc2 must not be targeted")
        
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
        AppEnvironment.testLock.lock()
        let spyActions = SpyWindowActions()
        AppEnvironment.current = AppEnvironment(windowActions: spyActions)
        defer {
            AppEnvironment.reset()
            AppEnvironment.testLock.unlock()
        }
        
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight, store: store)
        source.startTracking()
        
        let window = source.addWindow(id: 6001, pid: 42, appName: "TextEdit", title: "CloseDoc", isMain: true)
        #expect(store.totalWindowCount == 1)
        #expect(store.focusedWindowKey == window.key)
        
        view.updateWindows(windows: store.allWindows, focusedKey: store.focusedWindowKey, frontmostPID: store.frontmostPID)
        #expect(view.taskButtons.count == 1)
        
        // Close window through TaskButton interaction
        let btn = view.taskButtons[0]
        btn.onClose?()
        #expect(spyActions.invocations.contains(.closeWindow(key: window.key)))
        
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
        AppEnvironment.testLock.lock()
        let spyActions = SpyWindowActions()
        AppEnvironment.current = AppEnvironment(windowActions: spyActions)
        defer {
            AppEnvironment.reset()
            AppEnvironment.testLock.unlock()
        }
        
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight, store: store)
        source.startTracking()
        
        _ = source.addWindow(id: 7001, pid: 88, appName: "Safari", bundleID: "com.apple.Safari", title: "Tab 1")
        _ = source.addWindow(id: 7002, pid: 88, appName: "Safari", bundleID: "com.apple.Safari", title: "Tab 2")
        let finderWin = source.addWindow(id: 7003, pid: 99, appName: "Finder", bundleID: "com.apple.finder", title: "Downloads")
        
        #expect(store.totalWindowCount == 3)
        
        view.updateWindows(windows: store.allWindows, focusedKey: store.focusedWindowKey, frontmostPID: store.frontmostPID)
        
        // Quit Safari via TaskButton onQuit interaction
        let safariBtn = view.taskButtons.first { $0.group.bundleID == "com.apple.Safari" }
        safariBtn?.onQuit?()
        #expect(spyActions.invocations.contains(.quitApplicationPID(pid: 88)))
        
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
    
    @Test("TC-FUNC-008: Background window mutation or creation preserves frontmost app focus")
    func testBackgroundWindowDoesNotHijackFocus() {
        let store = WindowStore()
        let source = FakeWindowSource(store: store)
        source.startTracking()
        
        let frontPID: pid_t = 100
        let backPID: pid_t = 200
        
        // 1. User is working in FrontApp
        let frontWin = source.addWindow(id: 8001, pid: frontPID, appName: "FrontApp", bundleID: "com.front.app", title: "Active Document", isMain: true)
        source.setFrontmostPID(frontPID)
        source.setFocused(key: frontWin.key)
        
        #expect(store.frontmostPID == frontPID)
        #expect(store.focusedWindowKey == frontWin.key)
        
        // 2. BackgroundApp creates a main window (isMain == true)
        let backWin = source.addWindow(id: 8002, pid: backPID, appName: "BackApp", bundleID: "com.back.app", title: "Background Window", isMain: true)
        
        // 3. Verify store focus and frontmost PID were not stolen
        #expect(store.frontmostPID == frontPID, "Frontmost PID must remain unchanged")
        #expect(store.focusedWindowKey == frontWin.key, "Focused window key must remain unchanged")
        
        // 4. Background window title mutation
        source.updateTitle(key: backWin.key, newTitle: "Background Window (Updated Title)")
        #expect(store.focusedWindowKey == frontWin.key, "Title change in background app must not hijack focus")
        #expect(store.window(forKey: backWin.key)?.title == "Background Window (Updated Title)")
    }
}
