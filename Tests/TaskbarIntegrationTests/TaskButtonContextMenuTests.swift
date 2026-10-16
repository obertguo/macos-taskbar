// Tests/TaskbarIntegrationTests/TaskButtonContextMenuTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("TaskButton Context Menu Integration Suite")
@MainActor
struct TaskButtonContextMenuTests {

    @Test("Right-click context menu shows 'Minimize' for unminimized and 'Restore' for minimized")
    func testContextMenuTitlesForMinimizedAndUnminimized() {
        // Unminimized window
        let unminimizedWin = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "Apple",
            frame: .zero,
            isMinimized: false
        )
        let unminBtn = TaskButton(
            windowInfo: unminimizedWin,
            isFocused: false,
            showTitle: true,
            theme: ModernHybridTheme.definition
        )
        let unminMenu = unminBtn.menu(for: NSEvent())
        let unminFirstItem = unminMenu?.items.first
        #expect(unminFirstItem?.title == TaskbarStrings.ContextMenu.minimize)
        #expect(unminFirstItem?.title == "Minimize")

        // Minimized window
        let minimizedWin = WindowInfo(
            key: WindowKey(id: 2, pid: 100),
            pid: 100,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "Apple",
            frame: .zero,
            isMinimized: true
        )
        let minBtn = TaskButton(
            windowInfo: minimizedWin,
            isFocused: false,
            showTitle: true,
            theme: ModernHybridTheme.definition
        )
        let minMenu = minBtn.menu(for: NSEvent())
        let minFirstItem = minMenu?.items.first
        #expect(minFirstItem?.title == TaskbarStrings.ContextMenu.restore)
        #expect(minFirstItem?.title == "Restore")
    }

    @Test("Right-click on single unminimized window triggers onMinimizeOrRestore, not onClick")
    func testSingleWindowContextMenuTriggersMinimizeOrRestoreNotOnClick() {
        let win = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "Apple",
            frame: .zero,
            isMinimized: false
        )
        let btn = TaskButton(
            windowInfo: win,
            isFocused: true,
            showTitle: true,
            theme: ModernHybridTheme.definition
        )

        var onClickTriggered = false
        var onMinimizeOrRestoreTriggered = false

        btn.onClick = {
            onClickTriggered = true
        }
        btn.onMinimizeOrRestore = {
            onMinimizeOrRestoreTriggered = true
        }

        guard let menu = btn.menu(for: NSEvent()),
              let minItem = menu.items.first(where: { $0.title == TaskbarStrings.ContextMenu.minimize }) else {
            Issue.record("Minimize menu item not found")
            return
        }

        _ = btn.perform(minItem.action, with: minItem)

        #expect(onMinimizeOrRestoreTriggered, "Context menu action should trigger onMinimizeOrRestore")
        #expect(!onClickTriggered, "Context menu action must NOT trigger onClick")
    }

    @Test("Right-click on grouped button invokes onMinimizeOrRestore without triggering onClick (popup)")
    func testGroupedButtonContextMenuTriggersMinimizeOrRestoreWithoutOnClick() {
        let win1 = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "zsh 1",
            frame: .zero,
            isMinimized: false
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 2, pid: 100),
            pid: 100,
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "zsh 2",
            frame: .zero,
            isMinimized: false
        )
        let group = WindowGroup.applicationGroup(
            bundleID: "com.apple.Terminal",
            appName: "Terminal",
            windows: [win1, win2]
        )
        let btn = TaskButton(
            group: group,
            isFocused: false,
            showTitle: true,
            theme: ModernHybridTheme.definition
        )

        var onClickTriggered = false
        var onMinimizeOrRestoreTriggered = false

        btn.onClick = {
            // onClick would open popup for grouped button
            onClickTriggered = true
        }
        btn.onMinimizeOrRestore = {
            onMinimizeOrRestoreTriggered = true
        }

        guard let menu = btn.menu(for: NSEvent()),
              let minItem = menu.items.first(where: { $0.title == TaskbarStrings.ContextMenu.minimize }) else {
            Issue.record("Minimize menu item not found on grouped button")
            return
        }

        _ = btn.perform(minItem.action, with: minItem)

        #expect(onMinimizeOrRestoreTriggered, "Grouped button context menu should invoke onMinimizeOrRestore")
        #expect(!onClickTriggered, "Grouped button context menu must NOT invoke onClick (which would have opened popup)")
    }
}
