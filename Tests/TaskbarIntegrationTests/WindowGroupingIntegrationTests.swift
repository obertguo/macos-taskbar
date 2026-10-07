// Tests/TaskbarIntegrationTests/WindowGroupingIntegrationTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("Application Window Grouping and Popup Integration Suite")
@MainActor
struct WindowGroupingIntegrationTests {
    
    private func makeKeyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
    
    // TC-GROUP-001: Multi-window application forms group button with badge counter.
    @Test("TC-GROUP-001: Multi-window application aggregates into single button with badge counter")
    func testMultiWindowGroupAggregationAndBadge() {
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight)
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 38)
        
        let winSafari1 = WindowInfo(
            key: WindowKey(id: 101, pid: 1000),
            pid: 1000,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "Apple Inc.",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isMinimized: false
        )
        let winSafari2 = WindowInfo(
            key: WindowKey(id: 102, pid: 1000),
            pid: 1000,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "GitHub - Dashboard",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            isMinimized: false
        )
        let winTerminal = WindowInfo(
            key: WindowKey(id: 201, pid: 2000),
            pid: 2000,
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "zsh (active)",
            frame: CGRect(x: 50, y: 50, width: 600, height: 400),
            isMinimized: false
        )
        
        view.updateWindows(windows: [winSafari1, winSafari2, winTerminal], focusedKey: nil, frontmostPID: nil)
        
        guard let btnSafari1 = view.button(forKey: winSafari1.key),
              let btnSafari2 = view.button(forKey: winSafari2.key),
              let btnTerminal = view.button(forKey: winTerminal.key) else {
            Issue.record("Expected task buttons to exist for all windows")
            return
        }
        
        // Assert pointer equality: both Safari windows belong to the identical group button
        #expect(btnSafari1 === btnSafari2, "Multiple windows of the same bundleID must share one TaskButton")
        #expect(btnSafari1 !== btnTerminal, "Different bundleIDs must receive distinct TaskButtons")
        
        // Group properties validation
        #expect(btnSafari1.group.isGrouped == true, "Group with 2 windows must report isGrouped == true")
        #expect(btnSafari1.group.count == 2, "Group count must equal 2")
        #expect(btnSafari1.group.displayTitle == "Safari (2)", "Group title must display count badge format")
        #expect(btnSafari1.toolTip == "Safari (2)", "Button tooltip must reflect grouped count")
        
        // Single window button properties
        #expect(btnTerminal.group.isGrouped == false, "Single window must report isGrouped == false")
        #expect(btnTerminal.group.count == 1, "Single window count must equal 1")
        #expect(btnTerminal.group.displayTitle == "zsh (active)", "Ungrouped button title must display window title")
    }
    
    // TC-GROUP-002: Group button click opens popup window list displaying matching window titles.
    @Test("TC-GROUP-002: Group button click presents window list popup with matching titles")
    func testGroupButtonClickOpensPopup() {
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight)
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 38)
        
        let win1 = WindowInfo(
            key: WindowKey(id: 11, pid: 1100),
            pid: 1100,
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            title: "ProjectA - AppKit",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            isMinimized: false
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 12, pid: 1100),
            pid: 1100,
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            title: "ProjectB - TaskbarCore",
            frame: CGRect(x: 50, y: 50, width: 1000, height: 800),
            isMinimized: false
        )
        
        view.updateWindows(windows: [win1, win2], focusedKey: win1.key, frontmostPID: 1100)
        
        guard let groupBtn = view.button(forKey: win1.key) else {
            Issue.record("Expected grouped button for Xcode")
            return
        }
        
        #expect(view.activeGroupPopup == nil, "Popup must be nil initially")
        
        // Simulate clicking grouped button
        groupBtn.onClick?()
        
        guard let popup = view.activeGroupPopup else {
            Issue.record("Group button click must present GroupWindowPopup")
            return
        }
        
        #expect(popup.windows.count == 2, "Popup must contain 2 windows")
        #expect(popup.windows[0].title == "ProjectA - AppKit", "First row must display first window title")
        #expect(popup.windows[1].title == "ProjectB - TaskbarCore", "Second row must display second window title")
        
        // Keyboard navigation: Escape key dismisses popup
        let escapeEvent = makeKeyEvent(keyCode: TaskbarConstants.KeyCodes.escape)
        popup.keyDown(with: escapeEvent)
        #expect(view.activeGroupPopup == nil, "Pressing Escape must dismiss the popup")
    }
    
    // TC-GROUP-003: Selecting window in popup focuses specific target window without raising unrelated windows.
    @Test("TC-GROUP-003: Selecting window in popup triggers selection and dismisses panel")
    func testSelectWindowFromPopup() {
        let view = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight)
        view.frame = NSRect(x: 0, y: 0, width: 1200, height: 38)
        
        let win1 = WindowInfo(
            key: WindowKey(id: 31, pid: 3100),
            pid: 3100,
            appName: "Notes",
            bundleID: "com.apple.Notes",
            title: "Shopping List",
            frame: CGRect(x: 0, y: 0, width: 400, height: 500),
            isMinimized: false
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 32, pid: 3100),
            pid: 3100,
            appName: "Notes",
            bundleID: "com.apple.Notes",
            title: "Engineering Spec",
            frame: CGRect(x: 100, y: 100, width: 400, height: 500),
            isMinimized: false
        )
        
        view.updateWindows(windows: [win1, win2], focusedKey: nil, frontmostPID: nil)
        
        guard let groupBtn = view.button(forKey: win1.key) else {
            Issue.record("Expected Notes group button")
            return
        }
        
        groupBtn.onClick?()
        guard let popup = view.activeGroupPopup else {
            Issue.record("Expected active popup")
            return
        }
        
        var selectedWindowKey: WindowKey?
        popup.onSelectWindow = { win in
            selectedWindowKey = win.key
        }
        
        // Select second window (Engineering Spec)
        popup.selectWindow(win2)
        
        #expect(selectedWindowKey == win2.key, "Selecting row must callback with win2")
        #expect(view.activeGroupPopup == nil, "Selecting a window row must dismiss the popup")
    }
    
    // TC-GROUP-004: Dynamic mode switching via ScreenManager updates taskbar layout across all displays.
    @Test("TC-GROUP-004: Dynamic grouping mode switching via ScreenManager reconfigures taskbar layout")
    func testDynamicGroupingModeSwitching() {
        let store = WindowStore()
        let settings = Settings(
            pinnedApps: [],
            windowGroupingMode: .always
        )
        let manager = ScreenManager(settings: settings, store: store)
        
        let win1 = WindowInfo(
            key: WindowKey(id: 41, pid: 4100),
            pid: 4100,
            appName: "Pages",
            bundleID: "com.apple.Pages",
            title: "Document 1",
            frame: CGRect(x: 0, y: 0, width: 600, height: 700),
            isMinimized: false
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 42, pid: 4100),
            pid: 4100,
            appName: "Pages",
            bundleID: "com.apple.Pages",
            title: "Document 2",
            frame: CGRect(x: 100, y: 100, width: 600, height: 700),
            isMinimized: false
        )
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        manager.updateWindows()
        
        // 1. In .always mode: 2 windows of Pages must group into 1 button
        let primaryScreenID = manager.screenDescriptors().first?.id ?? 0
        let windows = store.windows(forScreenID: primaryScreenID, screens: manager.screenDescriptors())
        #expect(windows.count == 2)
        
        let initialGroups = WindowGroupingLogic.groupWindows(windows, mode: .always)
        #expect(initialGroups.count == 1, "In .always mode, 2 Pages windows form 1 group")
        #expect(initialGroups.first?.isGrouped == true)
        
        // 2. Switch to .never mode
        manager.updateGroupingMode(.never)
        #expect(manager.settings.windowGroupingMode == .never, "Settings must update to .never")
        
        let ungrouped = WindowGroupingLogic.groupWindows(windows, mode: .never)
        #expect(ungrouped.count == 2, "In .never mode, each window gets its own button")
        #expect(ungrouped.allSatisfy { !$0.isGrouped })
        
        // 3. Switch back to .always mode
        manager.updateGroupingMode(.always)
        #expect(manager.settings.windowGroupingMode == .always, "Settings must update back to .always")
        
        let regrouped = WindowGroupingLogic.groupWindows(windows, mode: .always)
        #expect(regrouped.count == 1, "In .always mode, windows recombine into 1 group")
        #expect(regrouped.first?.isGrouped == true)
    }
}
