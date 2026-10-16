// Tests/TaskbarCoreTests/WindowGroupingLogicTests.swift

import CoreGraphics
import Foundation
import Testing
@testable import TaskbarCore

@Suite("Window Grouping Logic Tests")
struct WindowGroupingLogicTests {
    
    private func makeWindow(
        id: UInt64,
        pid: pid_t,
        bundleID: String,
        appName: String,
        title: String,
        isMinimized: Bool = false,
        isAppHidden: Bool = false
    ) -> WindowInfo {
        WindowInfo(
            key: WindowKey(id: id, pid: pid),
            pid: pid,
            appName: appName,
            bundleID: bundleID,
            title: title,
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isMinimized: isMinimized,
            isAppHidden: isAppHidden
        )
    }
    
    private func createTestWindows() -> [WindowInfo] {
        return [
            // 4 Safari windows
            makeWindow(id: 1, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Apple Inc."),
            makeWindow(id: 2, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "GitHub"),
            makeWindow(id: 3, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Google Search"),
            makeWindow(id: 4, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Hacker News"),
            // 3 Terminal windows
            makeWindow(id: 10, pid: 200, bundleID: "com.apple.Terminal", appName: "Terminal", title: "zsh 1"),
            makeWindow(id: 11, pid: 200, bundleID: "com.apple.Terminal", appName: "Terminal", title: "zsh 2"),
            makeWindow(id: 12, pid: 200, bundleID: "com.apple.Terminal", appName: "Terminal", title: "top"),
            // 3 Finder windows
            makeWindow(id: 20, pid: 300, bundleID: "com.apple.finder", appName: "Finder", title: "Documents"),
            makeWindow(id: 21, pid: 300, bundleID: "com.apple.finder", appName: "Finder", title: "Downloads"),
            makeWindow(id: 22, pid: 300, bundleID: "com.apple.finder", appName: "Finder", title: "Applications")
        ]
    }
    
    // TC-UNIT-005: Never Grouping Mode leaves all windows separate
    @Test("Never Grouping mode leaves all windows separate")
    func testNeverGroupingModeLeavesAllSeparate() {
        let windows = createTestWindows()
        #expect(windows.count == 10)
        
        let groups = WindowGroupingLogic.groupWindows(windows, mode: .never)
        
        #expect(groups.count == 10)
        for (index, group) in groups.enumerated() {
            #expect(!group.isGrouped)
            #expect(group.count == 1)
            #expect(group.windows.count == 1)
            #expect(group.primaryWindow?.key == windows[index].key)
            #expect(group.displayTitle == windows[index].displayTitle)
            #expect(group.id == "win_\(windows[index].key.pid)_\(windows[index].key.id)")
        }
    }
    
    // TC-UNIT-006: Always Grouping Mode aggregates by bundleID
    @Test("Always Grouping mode aggregates by bundleID")
    func testAlwaysGroupingModeAggregatesByBundleID() {
        let windows = createTestWindows()
        
        let groups = WindowGroupingLogic.groupWindows(windows, mode: .always)
        
        #expect(groups.count == 3)
        
        // Safari
        let safariGroup = groups[0]
        #expect(safariGroup.bundleID == "com.apple.Safari")
        #expect(safariGroup.appName == "Safari")
        #expect(safariGroup.count == 4)
        #expect(safariGroup.isGrouped)
        #expect(safariGroup.displayTitle == "Safari (4)")
        #expect(safariGroup.id == "group_com.apple.Safari")
        
        // Terminal
        let terminalGroup = groups[1]
        #expect(terminalGroup.bundleID == "com.apple.Terminal")
        #expect(terminalGroup.appName == "Terminal")
        #expect(terminalGroup.count == 3)
        #expect(terminalGroup.isGrouped)
        #expect(terminalGroup.displayTitle == "Terminal (3)")
        #expect(terminalGroup.id == "group_com.apple.Terminal")
        
        // Finder
        let finderGroup = groups[2]
        #expect(finderGroup.bundleID == "com.apple.finder")
        #expect(finderGroup.appName == "Finder")
        #expect(finderGroup.count == 3)
        #expect(finderGroup.isGrouped)
        #expect(finderGroup.displayTitle == "Finder (3)")
        #expect(finderGroup.id == "group_com.apple.finder")
    }
    
    // TC-UNIT-006 Edge: Single-window app under Always mode is not marked as isGrouped
    @Test("Always Grouping single-window app is not marked as grouped")
    func testAlwaysGroupingSingleWindowApp() {
        let windows = [
            makeWindow(id: 1, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Apple Inc.")
        ]
        
        let groups = WindowGroupingLogic.groupWindows(windows, mode: .always)
        #expect(groups.count == 1)
        #expect(!groups[0].isGrouped)
        #expect(groups[0].count == 1)
        #expect(groups[0].displayTitle == "Apple Inc.")
    }
    
    // TC-UNIT-007: When Crowded auto-groups on overflow
    @Test("When Crowded auto-groups on overflow")
    func testWhenCrowdedAutoGroupsOnOverflow() {
        let windows = createTestWindows() // 10 windows
        let minBtnW = 100.0
        let spacing = 4.0
        // Required width for 10 windows = 10 * 100 + 9 * 4 = 1000 + 36 = 1036.0
        
        // Case 1: Ample space (availableWidth = 1200 > 1036) -> Remains ungrouped (10 groups)
        let ampleGroups = WindowGroupingLogic.groupWindows(
            windows,
            mode: .whenCrowded,
            availableWidth: 1200.0,
            minButtonWidth: minBtnW,
            buttonSpacing: spacing
        )
        #expect(ampleGroups.count == 10)
        #expect(!ampleGroups[0].isGrouped)
        
        // Case 2: Exact boundary space (availableWidth = 1036.0) -> Remains ungrouped
        let exactGroups = WindowGroupingLogic.groupWindows(
            windows,
            mode: .whenCrowded,
            availableWidth: 1036.0,
            minButtonWidth: minBtnW,
            buttonSpacing: spacing
        )
        #expect(exactGroups.count == 10)
        
        // Case 3: Crowded space (availableWidth = 1035.0 < 1036.0) -> Aggregates to 3 groups
        let crowdedGroups = WindowGroupingLogic.groupWindows(
            windows,
            mode: .whenCrowded,
            availableWidth: 1035.0,
            minButtonWidth: minBtnW,
            buttonSpacing: spacing
        )
        #expect(crowdedGroups.count == 3)
        #expect(crowdedGroups[0].isGrouped)
        #expect(crowdedGroups[0].count == 4)
    }
    
    // TC-UNIT-008: Group derived states
    @Test("Group derived states for minimization and focus")
    func testGroupDerivedStates() {
        let win1 = makeWindow(id: 1, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Tab 1", isMinimized: true, isAppHidden: false)
        let win2 = makeWindow(id: 2, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Tab 2", isMinimized: true, isAppHidden: false)
        
        // Both minimized
        let groupAllMinimized = WindowGroup.applicationGroup(bundleID: "com.apple.Safari", appName: "Safari", windows: [win1, win2])
        #expect(groupAllMinimized.isMinimized)
        #expect(!groupAllMinimized.isAppHidden)
        
        // One un-minimized
        let win2Normal = makeWindow(id: 2, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "Tab 2", isMinimized: false, isAppHidden: false)
        let groupPartiallyMinimized = WindowGroup.applicationGroup(bundleID: "com.apple.Safari", appName: "Safari", windows: [win1, win2Normal])
        #expect(!groupPartiallyMinimized.isMinimized)
        
        // Focus state test
        let focusedKey = WindowKey(id: 2, pid: 100)
        #expect(groupPartiallyMinimized.isFocused(focusedKey: focusedKey, frontmostPID: 100))
        
        // Different frontmost PID does not focus
        #expect(!groupPartiallyMinimized.isFocused(focusedKey: focusedKey, frontmostPID: 999))
        
        // Unmatched window ID does not focus
        #expect(!groupPartiallyMinimized.isFocused(focusedKey: WindowKey(id: 99, pid: 100), frontmostPID: 100))
        
        // Minimized focused window does not count as active focus
        let focusedMinimizedKey = WindowKey(id: 1, pid: 100)
        #expect(!groupPartiallyMinimized.isFocused(focusedKey: focusedMinimizedKey, frontmostPID: 100))
        
        // Display title fallback for empty window title
        let emptyTitleWin = makeWindow(id: 3, pid: 100, bundleID: "com.apple.Safari", appName: "Safari", title: "   ")
        let singleGroup = WindowGroup.singleWindow(emptyTitleWin)
        #expect(singleGroup.displayTitle == "Safari")
    }
    
    // Empty collection handling
    @Test("Empty windows list returns empty array")
    func testEmptyWindowsListReturnsEmpty() {
        let emptyNever = WindowGroupingLogic.groupWindows([], mode: .never)
        let emptyAlways = WindowGroupingLogic.groupWindows([], mode: .always)
        let emptyCrowded = WindowGroupingLogic.groupWindows([], mode: .whenCrowded, availableWidth: 500)
        
        #expect(emptyNever.isEmpty)
        #expect(emptyAlways.isEmpty)
        #expect(emptyCrowded.isEmpty)
    }
    
    // MRU primaryWindow selection verification
    @Test("Primary window selection prioritizes MRU focus order")
    func testPrimaryWindowSelection() {
        // 1. Returns most recently focused unminimized window
        let w1 = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "W1",
            frame: .zero,
            openOrder: 1,
            focusOrder: 5
        )
        let w2 = WindowInfo(
            key: WindowKey(id: 2, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "W2",
            frame: .zero,
            openOrder: 2,
            focusOrder: 10
        )
        let group1 = WindowGroup.applicationGroup(bundleID: "com.app", appName: "App", windows: [w1, w2])
        #expect(group1.primaryWindow?.key == w2.key)
        
        // 2. Falls back to unminimized with lowest openOrder when none focused (focusOrder == 0)
        let w3 = WindowInfo(
            key: WindowKey(id: 3, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "W3",
            frame: .zero,
            openOrder: 10,
            focusOrder: 0
        )
        let w4 = WindowInfo(
            key: WindowKey(id: 4, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "W4",
            frame: .zero,
            openOrder: 5,
            focusOrder: 0
        )
        let group2 = WindowGroup.applicationGroup(bundleID: "com.app", appName: "App", windows: [w3, w4])
        #expect(group2.primaryWindow?.key == w4.key)
        
        // 3. Falls back to most recently focused minimized window when all are minimized
        let w5Min = WindowInfo(
            key: WindowKey(id: 5, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "W5",
            frame: .zero,
            isMinimized: true,
            openOrder: 1,
            focusOrder: 2
        )
        let w6Min = WindowInfo(
            key: WindowKey(id: 6, pid: 100),
            pid: 100,
            appName: "App",
            bundleID: "com.app",
            title: "W6",
            frame: .zero,
            isMinimized: true,
            openOrder: 2,
            focusOrder: 7
        )
        let group3 = WindowGroup.applicationGroup(bundleID: "com.app", appName: "App", windows: [w5Min, w6Min])
        #expect(group3.primaryWindow?.key == w6Min.key)
    }
}
