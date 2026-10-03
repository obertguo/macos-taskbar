// Tests/TaskbarCoreTests/WindowStoreTests.swift

import XCTest
import CoreGraphics
@testable import TaskbarCore

final class WindowStoreTests: XCTestCase {
    let screens = [
        ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true),
        ScreenDescriptor(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false)
    ]
    
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
        XCTAssertEqual(display1Windows.count, 2)
        XCTAssertEqual(display1Windows[0].key, win1.key)
        XCTAssertEqual(display1Windows[1].key, win2.key)
        
        // Updating title should preserve order
        var win1Updated = win1
        win1Updated.title = "New Tab"
        store.addOrUpdateWindow(win1Updated)
        
        let display1AfterUpdate = store.windows(forScreenID: 1, screens: screens)
        XCTAssertEqual(display1AfterUpdate[0].title, "New Tab")
        XCTAssertEqual(display1AfterUpdate[0].key, win1.key)
    }
    
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
        
        XCTAssertEqual(store.windows(forScreenID: 1, screens: screens).map { $0.key }, [winOnScreen1.key])
        XCTAssertEqual(store.windows(forScreenID: 2, screens: screens).map { $0.key }, [winOnScreen2.key])
    }
    
    func testSyncSnapshotReconciliation() {
        let store = WindowStore()
        let pid: pid_t = 300
        
        let w1 = WindowInfo(key: WindowKey(id: 1, pid: pid), pid: pid, appName: "App", bundleID: "com.app", title: "W1", frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let w2 = WindowInfo(key: WindowKey(id: 2, pid: pid), pid: pid, appName: "App", bundleID: "com.app", title: "W2", frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        
        store.syncSnapshot(forPID: pid, currentWindows: [w1, w2])
        XCTAssertEqual(store.totalWindowCount, 2)
        
        // Window 1 was closed; now only Window 2 remains
        store.syncSnapshot(forPID: pid, currentWindows: [w2])
        XCTAssertEqual(store.totalWindowCount, 1)
        XCTAssertEqual(store.windows(forScreenID: 1, screens: screens).first?.key, w2.key)
    }
    
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
        XCTAssertNotNil(storedFS)
        XCTAssertTrue(storedFS?.isFullScreen == true)
        
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
        XCTAssertNotNil(storedNormal)
        XCTAssertFalse(storedNormal?.isFullScreen == true, "WindowStore must update isFullScreen to false when window exits full-screen mode")
    }
}
