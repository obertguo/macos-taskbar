// Tests/TaskbarCoreTests/ClickPolicyTests.swift

import CoreGraphics
import Testing
@testable import TaskbarCore

@Suite("Click Policy Tests")
struct ClickPolicyTests {
    let testKey = WindowKey(id: 100, pid: 10)
    
    @Test("Click unfocused window focuses it")
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
        #expect(action == .focus)
    }
    
    @Test("Click already focused window minimizes it")
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
        #expect(action == .minimize)
    }
    
    @Test("Click frontmost app with nil focused key minimizes only if main")
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
        #expect(action == .minimize)
    }
    
    @Test("Click secondary non-main window of frontmost app with nil focused key focuses it")
    func testClickSecondaryWindowOfFrontmostAppWithNilFocusedKey() {
        let secondaryWin = WindowInfo(
            key: WindowKey(id: 200, pid: 10),
            pid: 10,
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            title: "Secondary Window",
            frame: CGRect(x: 800, y: 0, width: 800, height: 600),
            isMain: false
        )
        let action = ClickPolicy.leftClickAction(
            for: secondaryWin,
            focusedKey: nil,
            isFrontmostApp: true
        )
        #expect(action == .focus, "Secondary non-main window must be focused on first click, never minimized")
    }
    
    @Test("Click secondary window of frontmost app when another window is focused focuses it")
    func testClickSecondaryWindowOfFrontmostAppWhenAnotherWindowIsFocused() {
        let secondaryWin = WindowInfo(
            key: WindowKey(id: 200, pid: 10),
            pid: 10,
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            title: "Secondary Window",
            frame: CGRect(x: 800, y: 0, width: 800, height: 600),
            isMain: false
        )
        // Primary window 100 is currently focused
        let action = ClickPolicy.leftClickAction(
            for: secondaryWin,
            focusedKey: testKey,
            isFrontmostApp: true
        )
        #expect(action == .focus, "Must focus secondary window instead of minimizing")
    }
    
    @Test("Click minimized window restores and focuses it")
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
        #expect(action == .restoreAndFocus)
    }
    
    @Test("Click hidden app window restores and focuses it")
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
        #expect(action == .restoreAndFocus)
    }
}
