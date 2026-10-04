// Tests/TaskbarIntegrationTests/PinnedAppsIntegrationTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("Pinned Applications Integration Suite")
@MainActor
struct PinnedAppsIntegrationTests {
    
    @Test("PinnedButton properties, tracking, and dynamic context menu")
    func testPinnedButtonPropertiesAndContextMenu() {
        let app = PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder")
        let btn = PinnedButton(
            pinnedApp: app,
            isRunning: false,
            theme: ModernHybridTheme.definition
        )
        
        #expect(btn.toolTip == "Finder")
        #expect(btn.pinnedApp == app)
        #expect(btn.isRunning == false)
        
        // 1. Context menu when not running
        guard let menuNotRunning = btn.menu(for: NSEvent()) else {
            Issue.record("Failed to generate context menu for PinnedButton")
            return
        }
        
        let titlesNotRunning = menuNotRunning.items.map { $0.title }
        #expect(titlesNotRunning.contains(TaskbarStrings.ContextMenu.openApp("Finder")))
        #expect(titlesNotRunning.contains(TaskbarStrings.ContextMenu.unpinFromTaskbar))
        #expect(!titlesNotRunning.contains(TaskbarStrings.ContextMenu.quitApp("Finder")))
        
        // 2. Context menu when running
        btn.isRunning = true
        guard let menuRunning = btn.menu(for: NSEvent()) else {
            Issue.record("Failed to generate context menu for running PinnedButton")
            return
        }
        
        let titlesRunning = menuRunning.items.map { $0.title }
        #expect(titlesRunning.contains(TaskbarStrings.ContextMenu.openApp("Finder")))
        #expect(titlesRunning.contains(TaskbarStrings.ContextMenu.unpinFromTaskbar))
        #expect(titlesRunning.contains(TaskbarStrings.ContextMenu.quitApp("Finder")))
        
        // 3. Action invocation
        var clicked = false
        var unpinned = false
        var quit = false
        
        btn.onClick = { clicked = true }
        btn.onUnpin = { unpinned = true }
        btn.onQuit = { quit = true }
        
        if let openItem = menuRunning.items.first(where: { $0.title == TaskbarStrings.ContextMenu.openApp("Finder") }) {
            _ = btn.perform(openItem.action, with: openItem)
            #expect(clicked == true)
        }
        
        if let unpinItem = menuRunning.items.first(where: { $0.title == TaskbarStrings.ContextMenu.unpinFromTaskbar }) {
            _ = btn.perform(unpinItem.action, with: unpinItem)
            #expect(unpinned == true)
        }
        
        if let quitItem = menuRunning.items.first(where: { $0.title == TaskbarStrings.ContextMenu.quitApp("Finder") }) {
            _ = btn.perform(quitItem.action, with: quitItem)
            #expect(quit == true)
        }
    }
    
    @Test("TaskbarView pinned buttons layout, positioning, and square aspect ratio")
    func testTaskbarViewPinnedButtonsLayoutAndSizing() {
        let view = TaskbarView(
            theme: ModernHybridTheme.definition,
            launcherAction: .spotlight,
            pinnedApps: PinnedApp.defaultPinnedApps
        )
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        view.layout()
        
        #expect(view.allPinnedButtons.count == 3)
        
        let padY = TaskbarConstants.Layout.taskbarVerticalPadding
        let expectedBtnH = max(TaskbarConstants.Layout.minimumButtonHeight, view.bounds.height - (padY * 2))
        
        for btn in view.allPinnedButtons {
            #expect(btn.superview === view)
            #expect(btn.frame.width == expectedBtnH)
            #expect(btn.frame.height == expectedBtnH)
        }
        
        // Ensure buttons are adjacent following StartButton
        let startBtn = view.startButton
        let firstPinned = view.allPinnedButtons[0]
        let secondPinned = view.allPinnedButtons[1]
        let thirdPinned = view.allPinnedButtons[2]
        
        let expectedFirstX = startBtn.frame.maxX + TaskbarConstants.Layout.startButtonTrailingMargin
        #expect(abs(firstPinned.frame.minX - expectedFirstX) <= 0.5)
        
        let expectedSecondX = firstPinned.frame.maxX + TaskbarConstants.Layout.pinnedButtonSpacing
        #expect(abs(secondPinned.frame.minX - expectedSecondX) <= 0.5)
        
        let expectedThirdX = secondPinned.frame.maxX + TaskbarConstants.Layout.pinnedButtonSpacing
        #expect(abs(thirdPinned.frame.minX - expectedThirdX) <= 0.5)
    }
    
    @Test("TaskbarView view recycling preserves existing PinnedButton instances")
    func testTaskbarViewPinnedButtonRecycling() {
        let view = TaskbarView(
            theme: ModernHybridTheme.definition,
            launcherAction: .spotlight,
            pinnedApps: PinnedApp.defaultPinnedApps
        )
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        view.layout()
        
        guard let finderBtnBefore = view.pinnedButton(forBundleID: "com.apple.finder"),
              let safariBtnBefore = view.pinnedButton(forBundleID: "com.apple.Safari") else {
            Issue.record("Expected default pinned buttons to exist")
            return
        }
        
        // Update with reordered list
        let reordered = [
            PinnedApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari"),
            PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder")
        ]
        view.updatePinnedApps(reordered)
        
        let finderBtnAfter = view.pinnedButton(forBundleID: "com.apple.finder")
        let safariBtnAfter = view.pinnedButton(forBundleID: "com.apple.Safari")
        let terminalBtnAfter = view.pinnedButton(forBundleID: "com.apple.Terminal")
        
        // Instances should be recycled and identical in memory
        #expect(finderBtnBefore === finderBtnAfter)
        #expect(safariBtnBefore === safariBtnAfter)
        
        // Unpinned app button should be cleaned up
        #expect(terminalBtnAfter == nil)
        #expect(view.allPinnedButtons.count == 2)
    }
    
    @Test("TaskButton dynamic Pin to Taskbar / Unpin from Taskbar context menu")
    func testTaskButtonDynamicPinningContextMenu() {
        let pinned = [PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder")]
        let view = TaskbarView(
            theme: ModernHybridTheme.definition,
            launcherAction: .spotlight,
            pinnedApps: pinned
        )
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        
        var pinRequestedBundleID: String?
        var pinRequestedAppName: String?
        var unpinRequestedBundleID: String?
        
        view.onPinRequested = { bundleID, appName in
            pinRequestedBundleID = bundleID
            pinRequestedAppName = appName
        }
        view.onUnpinRequested = { bundleID in
            unpinRequestedBundleID = bundleID
        }
        
        let finderWindow = WindowInfo(
            key: WindowKey(id: 1, pid: 101),
            pid: 101,
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: "Documents",
            frame: .zero,
            isMinimized: false,
            isAppHidden: false
        )
        let textEditWindow = WindowInfo(
            key: WindowKey(id: 2, pid: 102),
            pid: 102,
            appName: "TextEdit",
            bundleID: "com.apple.TextEdit",
            title: "Notes.txt",
            frame: .zero,
            isMinimized: false,
            isAppHidden: false
        )
        
        view.updateWindows(windows: [finderWindow, textEditWindow], focusedKey: nil, frontmostPID: nil)
        
        guard let finderTaskBtn = view.button(forKey: finderWindow.key),
              let textEditTaskBtn = view.button(forKey: textEditWindow.key) else {
            Issue.record("Failed to find task buttons")
            return
        }
        
        #expect(finderTaskBtn.isPinned == true)
        #expect(textEditTaskBtn.isPinned == false)
        
        // Verify context menu items
        let finderMenu = finderTaskBtn.menu(for: NSEvent())
        let finderTitles = finderMenu?.items.map { $0.title } ?? []
        #expect(finderTitles.contains(TaskbarStrings.ContextMenu.unpinFromTaskbar))
        #expect(!finderTitles.contains(TaskbarStrings.ContextMenu.pinToTaskbar))
        
        let textEditMenu = textEditTaskBtn.menu(for: NSEvent())
        let textEditTitles = textEditMenu?.items.map { $0.title } ?? []
        #expect(textEditTitles.contains(TaskbarStrings.ContextMenu.pinToTaskbar))
        #expect(!textEditTitles.contains(TaskbarStrings.ContextMenu.unpinFromTaskbar))
        
        // Trigger toggle pin on TextEdit button
        if let pinItem = textEditMenu?.items.first(where: { $0.title == TaskbarStrings.ContextMenu.pinToTaskbar }) {
            _ = textEditTaskBtn.perform(pinItem.action, with: pinItem)
            #expect(pinRequestedBundleID == "com.apple.TextEdit")
            #expect(pinRequestedAppName == "TextEdit")
        }
        
        // Trigger toggle unpin on Finder button
        if let unpinItem = finderMenu?.items.first(where: { $0.title == TaskbarStrings.ContextMenu.unpinFromTaskbar }) {
            _ = finderTaskBtn.perform(unpinItem.action, with: unpinItem)
            #expect(unpinRequestedBundleID == "com.apple.finder")
        }
    }
    
    @Test("Running indicator state transitions based on window updates")
    func testRunningIndicatorStateTransitions() {
        let app = PinnedApp(bundleIdentifier: "com.test.unique.app", displayName: "TestApp")
        let view = TaskbarView(
            theme: ModernHybridTheme.definition,
            launcherAction: .spotlight,
            pinnedApps: [app]
        )
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        view.layout()
        
        guard let btn = view.pinnedButton(forBundleID: "com.test.unique.app") else {
            Issue.record("Pinned button not found")
            return
        }
        
        #expect(btn.isRunning == false)
        
        // App opens a window
        let testWindow = WindowInfo(
            key: WindowKey(id: 1, pid: 9999),
            pid: 9999,
            appName: "TestApp",
            bundleID: "com.test.unique.app",
            title: "Main Window",
            frame: .zero,
            isMinimized: false,
            isAppHidden: false
        )
        
        view.updateWindows(windows: [testWindow], focusedKey: nil, frontmostPID: nil)
        #expect(btn.isRunning == true)
        
        // App closes all windows
        view.updateWindows(windows: [], focusedKey: nil, frontmostPID: nil)
        #expect(btn.isRunning == false)
    }
    
    @Test("ScreenManager propagates pin and unpin actions across all panels")
    func testScreenManagerMultiDisplayPinnedAppsSync() {
        let settings = Settings(
            pinnedApps: [
                PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder")
            ]
        )
        let store = WindowStore()
        let manager = ScreenManager(settings: settings, store: store)
        
        let initialPanels = manager.allPanels
        #expect(!initialPanels.isEmpty)
        
        for panel in initialPanels {
            #expect(panel.taskbarView.allPinnedButtons.count == 1)
            #expect(panel.taskbarView.pinnedButton(forBundleID: "com.apple.finder") != nil)
        }
        
        // Pin new app via ScreenManager
        manager.pinApp(bundleIdentifier: "com.apple.Notes", displayName: "Notes")
        
        for panel in manager.allPanels {
            #expect(panel.taskbarView.allPinnedButtons.count == 2)
            #expect(panel.taskbarView.pinnedButton(forBundleID: "com.apple.Notes") != nil)
        }
        
        // Unpin app via ScreenManager
        manager.unpinApp(bundleIdentifier: "com.apple.Notes")
        
        for panel in manager.allPanels {
            #expect(panel.taskbarView.allPinnedButtons.count == 1)
            #expect(panel.taskbarView.pinnedButton(forBundleID: "com.apple.Notes") == nil)
        }
        
        manager.closeAll()
    }
    
    @Test("IconCache bundle ID and fallback resolution")
    func testIconCacheResolution() {
        IconCache.shared.clearCache()
        
        // Finder system icon resolution
        let finderIcon = IconCache.shared.icon(for: "com.apple.finder", customPath: nil)
        #expect(finderIcon.size.width > 0)
        #expect(finderIcon.size.height > 0)
        
        // Cached resolution returns same object
        let cachedFinder = IconCache.shared.icon(for: "com.apple.finder", customPath: nil)
        #expect(finderIcon === cachedFinder)
        
        // Non-existent bundle ID returns fallback
        let fallback = IconCache.shared.icon(for: "com.nonexistent.fake.app.bundle")
        #expect(fallback.size.width > 0)
    }
}
