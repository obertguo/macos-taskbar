// Tests/TaskbarCoreTests/ClickPolicyTests.swift

import XCTest
import CoreGraphics
@testable import TaskbarCore

final class ClickPolicyTests: XCTestCase {
    let testKey = WindowKey(id: 100, pid: 10)
    
    func testClickUnfocusedWindow() {
        let win = WindowInfo(
            key: testKey,
            pid: 10,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Downloads",
            frame: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        // Another window is focused
        let action = ClickPolicy.leftClickAction(
            for: win,
            focusedKey: WindowKey(id: 999, pid: 20),
            isFrontmostApp: false
        )
        XCTAssertEqual(action, .focus)
    }
    
    func testClickAlreadyFocusedWindow() {
        let win = WindowInfo(
            key: testKey,
            pid: 10,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Downloads",
            frame: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        // Same window is focused and its app is frontmost -> minimize
        let action = ClickPolicy.leftClickAction(
            for: win,
            focusedKey: testKey,
            isFrontmostApp: true
        )
        XCTAssertEqual(action, .minimize)
    }
    
    func testClickFrontmostAppWithNilFocusedKey() {
        // In Chrome/Discord, focusedKey may be nil even when frontmost
        let win = WindowInfo(
            key: testKey,
            pid: 10,
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            title: "Google",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isMain: true
        )
        let action = ClickPolicy.leftClickAction(
            for: win,
            focusedKey: nil,
            isFrontmostApp: true
        )
        XCTAssertEqual(action, .minimize, "Clicking frontmost window when focusedKey is nil should minimize")
    }
    
    func testClickMinimizedWindow() {
        var win = WindowInfo(
            key: testKey,
            pid: 10,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Downloads",
            frame: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        win.isMinimized = true
        
        let action = ClickPolicy.leftClickAction(
            for: win,
            focusedKey: nil,
            isFrontmostApp: false
        )
        XCTAssertEqual(action, .restoreAndFocus)
    }
    
    func testClickHiddenAppWindow() {
        var win = WindowInfo(
            key: testKey,
            pid: 10,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Downloads",
            frame: CGRect(x: 0, y: 0, width: 500, height: 500)
        )
        win.isAppHidden = true
        
        let action = ClickPolicy.leftClickAction(
            for: win,
            focusedKey: nil,
            isFrontmostApp: false
        )
        XCTAssertEqual(action, .restoreAndFocus)
    }
}
