// Tests/TaskbarCoreTests/WindowStoreTests.swift

import CoreGraphics
import Testing
@testable import TaskbarCore

@Suite("WindowStore Tests")
@MainActor
struct WindowStoreTests {
    let screens = [
        ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true),
        ScreenDescriptor(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false)
    ]
    
    @Test("Add and order windows")
    func testAddAndOrderWindows() {
        let store = WindowStore()
        
        let win1 = WindowInfo(
            key: WindowKey(id: 101, pid: 501),
            pid: 501,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "Apple",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 102, pid: 502),
            pid: 502,
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "zsh",
            frame: CGRect(x: 200, y: 200, width: 600, height: 400)
        )
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        
        let display1Windows = store.windows(forScreenID: 1, screens: screens)
        #expect(display1Windows.count == 2)
        #expect(display1Windows[0].key == win1.key)
        #expect(display1Windows[1].key == win2.key)
        
        // Updating title should preserve order
        var win1Updated = win1
        win1Updated.title = "New Tab"
        store.addOrUpdateWindow(win1Updated)
        
        let display1AfterUpdate = store.windows(forScreenID: 1, screens: screens)
        #expect(display1AfterUpdate[0].title == "New Tab")
        #expect(display1AfterUpdate[0].key == win1.key)
    }
    
    @Test("Display partitioning between multiple screens")
    func testDisplayPartitioning() {
        let store = WindowStore()
        
        let winOnScreen1 = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
            appName: "Notes",
            bundleID: "com.apple.Notes",
            title: "Notes",
            frame: CGRect(x: 100, y: 100, width: 500, height: 500)
        )
        let winOnScreen2 = WindowInfo(
            key: WindowKey(id: 2, pid: 200),
            pid: 200,
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            title: "Project",
            frame: CGRect(x: 2100, y: 100, width: 1000, height: 800)
        )
        
        store.addOrUpdateWindow(winOnScreen1)
        store.addOrUpdateWindow(winOnScreen2)
        
        #expect(store.windows(forScreenID: 1, screens: screens).map { $0.key } == [winOnScreen1.key])
        #expect(store.windows(forScreenID: 2, screens: screens).map { $0.key } == [winOnScreen2.key])
    }
    
    @Test("Sync snapshot reconciliation")
    func testSyncSnapshotReconciliation() {
        let store = WindowStore()
        let pid: pid_t = 300
        
        let w1 = WindowInfo(key: WindowKey(id: 1, pid: pid), pid: pid, appName: "App", bundleID: "com.app", title: "W1", frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let w2 = WindowInfo(key: WindowKey(id: 2, pid: pid), pid: pid, appName: "App", bundleID: "com.app", title: "W2", frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        
        store.syncSnapshot(forPID: pid, currentWindows: [w1, w2])
        #expect(store.totalWindowCount == 2)
        
        // Window 1 was closed; now only Window 2 remains
        store.syncSnapshot(forPID: pid, currentWindows: [w2])
        #expect(store.totalWindowCount == 1)
        #expect(store.windows(forScreenID: 1, screens: screens).first?.key == w2.key)
    }
    
    @Test("Full screen transition tracking")
    func testFullScreenTransitionTracking() {
        let store = WindowStore()
        let key = WindowKey(id: 401, pid: 400)
        
        // Window initially enters full-screen
        let fsWindow = WindowInfo(
            key: key,
            pid: 400,
            appName: "Browser",
            bundleID: "com.browser",
            title: "Web Page",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isFullScreen: true
        )
        store.addOrUpdateWindow(fsWindow)
        
        let storedFS = store.windows(forScreenID: 1, screens: screens).first
        #expect(storedFS != nil)
        #expect(storedFS?.isFullScreen == true)
        
        // Window exits full-screen back to normal window
        let normalWindow = WindowInfo(
            key: key,
            pid: 400,
            appName: "Browser",
            bundleID: "com.browser",
            title: "Web Page",
            frame: CGRect(x: 100, y: 100, width: 1200, height: 800),
            isFullScreen: false
        )
        store.addOrUpdateWindow(normalWindow)
        
        let storedNormal = store.windows(forScreenID: 1, screens: screens).first
        #expect(storedNormal != nil)
        #expect(storedNormal?.isFullScreen == false)
    }
    
    @Test("Set focused window increments focus order")
    func testSetFocusedWindowIncrementsFocusOrder() {
        let store = WindowStore()
        let win1 = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "Win 1",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 2, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "Win 2",
            frame: CGRect(x: 50, y: 50, width: 800, height: 600)
        )
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        
        #expect(store.window(forKey: win1.key)?.focusOrder == 0)
        #expect(store.window(forKey: win2.key)?.focusOrder == 0)
        
        store.setFocusedWindow(key: win1.key)
        #expect(store.window(forKey: win1.key)?.focusOrder == 1)
        #expect(store.window(forKey: win1.key)?.lastFocusedAt != nil)
        
        store.setFocusedWindow(key: win2.key)
        #expect(store.window(forKey: win2.key)?.focusOrder == 2)
        #expect(store.window(forKey: win2.key)?.lastFocusedAt != nil)
        #expect((store.window(forKey: win2.key)?.focusOrder ?? 0) > (store.window(forKey: win1.key)?.focusOrder ?? 0))
    }
    
    // MARK: - Phase 6 / M-13: OrderKey & Pruning Tests
    
    @Test("Custom order sorting with OrderKey")
    func testCustomOrderSortingWithOrderKey() {
        let store = WindowStore()
        let win1 = WindowInfo(key: WindowKey(id: 101, pid: 501), pid: 501, appName: "Safari", bundleID: "com.apple.Safari", title: "Apple", frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let win2 = WindowInfo(key: WindowKey(id: 102, pid: 502), pid: 502, appName: "Terminal", bundleID: "com.apple.Terminal", title: "zsh", frame: CGRect(x: 200, y: 200, width: 600, height: 400))
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        
        // Natural order is [win1, win2]
        #expect(store.windows(forScreenID: 1, screens: screens).map { $0.key } == [win1.key, win2.key])
        
        // Set custom order placing win2 at slot 0 and win1 at slot 1
        store.setCustomOrder([.window(win2.key): 0, .window(win1.key): 1], forScreenID: 1)
        #expect(store.windows(forScreenID: 1, screens: screens).map { $0.key } == [win2.key, win1.key])
        
        // Set custom order via app-level keys
        store.setCustomOrder([.app("com.apple.Terminal"): 0, .app("com.apple.Safari"): 1], forScreenID: 1)
        #expect(store.windows(forScreenID: 1, screens: screens).map { $0.key } == [win2.key, win1.key])
        
        // Clear custom order restores natural open order
        store.clearCustomOrder(forScreenID: 1)
        #expect(store.windows(forScreenID: 1, screens: screens).map { $0.key } == [win1.key, win2.key])
    }
    
    @Test("Remove window pruning and app reopening appends")
    func testRemoveWindowPruningAndAppReopeningAppends() {
        let store = WindowStore()
        let win1 = WindowInfo(key: WindowKey(id: 101, pid: 501), pid: 501, appName: "Safari", bundleID: "com.apple.Safari", title: "Apple", frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let win2 = WindowInfo(key: WindowKey(id: 102, pid: 502), pid: 502, appName: "Terminal", bundleID: "com.apple.Terminal", title: "zsh", frame: CGRect(x: 200, y: 200, width: 600, height: 400))
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        
        // Custom order: Safari at slot 0, Terminal at slot 1
        store.setCustomOrder([
            .window(win1.key): 0,
            .app("com.apple.Safari"): 0,
            .window(win2.key): 1,
            .app("com.apple.Terminal"): 1
        ], forScreenID: 1)
        
        // Focus Safari
        store.setFocusedWindow(key: win1.key)
        #expect(store.focusedWindowKey == win1.key)
        
        // Close Safari window 1 (its only window)
        store.removeWindow(key: win1.key)
        
        // Focused window key must be cleared
        #expect(store.focusedWindowKey == nil)
        
        // customOrders on screen 1 must prune BOTH .window(win1.key) AND .app("com.apple.Safari")
        let orderAfterClose = store.customOrder(forScreenID: 1)
        #expect(orderAfterClose[.window(win1.key)] == nil)
        #expect(orderAfterClose[.app("com.apple.Safari")] == nil)
        #expect(orderAfterClose[.window(win2.key)] == 1)
        #expect(orderAfterClose[.app("com.apple.Terminal")] == 1)
        
        // Reopen Safari with a new window. Because both .window and .app were pruned,
        // it must append at the end after Terminal (slot 1), not revive slot 0!
        let win1New = WindowInfo(key: WindowKey(id: 103, pid: 501), pid: 501, appName: "Safari", bundleID: "com.apple.Safari", title: "Apple New", frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        store.addOrUpdateWindow(win1New)
        
        let screen1Windows = store.windows(forScreenID: 1, screens: screens)
        #expect(screen1Windows.count == 2)
        #expect(screen1Windows[0].key == win2.key)
        #expect(screen1Windows[1].key == win1New.key)
    }
    
    @Test("Remove window keeps app key when other windows exist")
    func testRemoveWindowKeepsAppKeyWhenOtherWindowsExist() {
        let store = WindowStore()
        let win1 = WindowInfo(key: WindowKey(id: 101, pid: 501), pid: 501, appName: "Safari", bundleID: "com.apple.Safari", title: "Apple 1", frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let win2 = WindowInfo(key: WindowKey(id: 102, pid: 501), pid: 501, appName: "Safari", bundleID: "com.apple.Safari", title: "Apple 2", frame: CGRect(x: 120, y: 120, width: 800, height: 600))
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        
        store.setCustomOrder([
            .window(win1.key): 0,
            .window(win2.key): 1,
            .app("com.apple.Safari"): 0
        ], forScreenID: 1)
        
        // Close win1, but win2 is still open
        store.removeWindow(key: win1.key)
        
        let order = store.customOrder(forScreenID: 1)
        #expect(order[.window(win1.key)] == nil)
        #expect(order[.window(win2.key)] == 1)
        #expect(order[.app("com.apple.Safari")] == 0)
        
        // Now close win2 (last window)
        store.removeWindow(key: win2.key)
        let orderAfterAllClosed = store.customOrder(forScreenID: 1)
        #expect(orderAfterAllClosed[.window(win2.key)] == nil)
        #expect(orderAfterAllClosed[.app("com.apple.Safari")] == nil)
    }
    
    @Test("Remove windows for PID pruning")
    func testRemoveWindowsForPIDPruning() {
        let store = WindowStore()
        let win1 = WindowInfo(key: WindowKey(id: 1, pid: 100), pid: 100, appName: "AppA", bundleID: "com.test.appA", title: "A", frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let win2 = WindowInfo(key: WindowKey(id: 2, pid: 200), pid: 200, appName: "AppB", bundleID: "com.test.appB", title: "B", frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        store.setFocusedWindow(key: win1.key)
        
        store.setCustomOrder([
            .window(win1.key): 0,
            .app("com.test.appA"): 0,
            .window(win2.key): 1,
            .app("com.test.appB"): 1
        ], forScreenID: 1)
        
        store.removeWindows(forPID: 100)
        
        #expect(store.focusedWindowKey == nil)
        #expect(store.totalWindowCount == 1)
        
        let order = store.customOrder(forScreenID: 1)
        #expect(order[.window(win1.key)] == nil)
        #expect(order[.app("com.test.appA")] == nil)
        #expect(order[.window(win2.key)] == 1)
        #expect(order[.app("com.test.appB")] == 1)
    }
    
    @Test("Sync snapshot pruning and stale focused window key cleanup")
    func testSyncSnapshotPruningAndStaleFocusedWindowKey() {
        let store = WindowStore()
        let pid: pid_t = 300
        
        let win1 = WindowInfo(key: WindowKey(id: 1, pid: pid), pid: pid, appName: "App", bundleID: "com.app", title: "W1", frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let win2 = WindowInfo(key: WindowKey(id: 2, pid: pid), pid: pid, appName: "App", bundleID: "com.app", title: "W2", frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        
        store.syncSnapshot(forPID: pid, currentWindows: [win1, win2])
        store.setFocusedWindow(key: win1.key)
        #expect(store.focusedWindowKey == win1.key)
        
        store.setCustomOrder([
            .window(win1.key): 0,
            .window(win2.key): 1,
            .app("com.app"): 0
        ], forScreenID: 1)
        
        // win1 closed, only win2 reported
        store.syncSnapshot(forPID: pid, currentWindows: [win2])
        
        // Focused window key must be cleared because win1 is gone
        #expect(store.focusedWindowKey == nil)
        
        // win1 key must be pruned, but win2 and app key remain
        var order = store.customOrder(forScreenID: 1)
        #expect(order[.window(win1.key)] == nil)
        #expect(order[.window(win2.key)] == 1)
        #expect(order[.app("com.app")] == 0)
        
        // win2 also closes (currentWindows empty)
        store.syncSnapshot(forPID: pid, currentWindows: [])
        order = store.customOrder(forScreenID: 1)
        #expect(order[.window(win2.key)] == nil)
        #expect(order[.app("com.app")] == nil)
    }
}
