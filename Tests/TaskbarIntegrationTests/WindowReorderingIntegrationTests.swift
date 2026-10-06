// Tests/TaskbarIntegrationTests/WindowReorderingIntegrationTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("Window Reordering and Drag Integration Suite")
@MainActor
struct WindowReorderingIntegrationTests {
    
    private func makeMouseEvent(type: NSEvent.EventType, location: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
    }
    
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
    
    // TC-DRAG-001: Dragging button beyond threshold triggers slot reorder; verify button frames update.
    @Test("TC-DRAG-001: Dragging task button beyond threshold reorders slots and updates layout")
    func testTaskButtonDragReorder() {
        let store = WindowStore()
        let screens = [
            ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true)
        ]
        
        let win1 = WindowInfo(
            key: WindowKey(id: 101, pid: 1),
            pid: 1,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "Apple",
            frame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 102, pid: 2),
            pid: 2,
            appName: "Terminal",
            bundleID: "com.apple.Terminal",
            title: "zsh",
            frame: CGRect(x: 200, y: 200, width: 600, height: 400)
        )
        let win3 = WindowInfo(
            key: WindowKey(id: 103, pid: 3),
            pid: 3,
            appName: "Notes",
            bundleID: "com.apple.Notes",
            title: "Notes",
            frame: CGRect(x: 300, y: 300, width: 500, height: 400)
        )
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        store.addOrUpdateWindow(win3)
        
        let view = TaskbarView(
            theme: ModernHybridTheme.definition,
            launcherAction: .spotlight,
            store: store
        )
        view.screenID = 1
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        view.updateWindows(windows: [win1, win2, win3], focusedKey: nil, frontmostPID: nil)
        view.layout()
        
        guard let btnSafari = view.button(forKey: win1.key),
              let btnTerminal = view.button(forKey: win2.key),
              let btnNotes = view.button(forKey: win3.key) else {
            Issue.record("Expected all three task buttons to exist")
            return
        }
        
        // 1. Initial order: Safari, Terminal, Notes
        #expect(btnSafari.frame.minX < btnTerminal.frame.minX)
        #expect(btnTerminal.frame.minX < btnNotes.frame.minX)
        
        // 2. Start drag on Safari button
        let startLoc = NSPoint(x: btnSafari.frame.midX, y: btnSafari.frame.midY)
        btnSafari.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: startLoc))
        #expect(btnSafari.isPressed)
        #expect(!btnSafari.isDragging)
        
        // Small drag within 4pt threshold does not activate drag session
        btnSafari.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: startLoc.x + 2.0, y: startLoc.y)))
        #expect(!btnSafari.isDragging)
        
        // Exceeding 4pt threshold initiates drag session
        btnSafari.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: startLoc.x + 10.0, y: startLoc.y)))
        #expect(btnSafari.isDragging)
        
        // Drag to target slot at the end (beyond Notes midpoint)
        let dropLoc = NSPoint(x: btnNotes.frame.maxX + 20.0, y: btnNotes.frame.midY)
        btnSafari.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: dropLoc))
        #expect(btnSafari.isDragging)
        
        // Release mouse to commit drop
        btnSafari.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: dropLoc))
        #expect(!btnSafari.isDragging)
        #expect(!btnSafari.isPressed)
        
        // 3. New order should be: Terminal, Notes, Safari
        #expect(btnTerminal.frame.minX < btnNotes.frame.minX)
        #expect(btnNotes.frame.minX < btnSafari.frame.minX)
        
        // Verify store customOrder persisted
        let order = store.customOrder(forScreenID: 1)
        #expect(order["win_2_102"] == 0) // Terminal
        #expect(order["win_3_103"] == 1) // Notes
        #expect(order["win_1_101"] == 2) // Safari
        
        // Verify store.windows queries return the new custom order
        let queriedWindows = store.windows(forScreenID: 1, screens: screens)
        #expect(queriedWindows.count == 3)
        #expect(queriedWindows[0].key == win2.key)
        #expect(queriedWindows[1].key == win3.key)
        #expect(queriedWindows[2].key == win1.key)
    }
    
    // TC-DRAG-002: Vertical mouse escape cancels drag session; button restores original slot.
    @Test("TC-DRAG-002: Vertical mouse escape and Escape key cancel drag session cleanly")
    func testDragSessionCancellation() {
        let store = WindowStore()
        let win1 = WindowInfo(
            key: WindowKey(id: 1, pid: 10),
            pid: 10,
            appName: "AppA",
            bundleID: "com.test.a",
            title: "A",
            frame: .zero
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 2, pid: 20),
            pid: 20,
            appName: "AppB",
            bundleID: "com.test.b",
            title: "B",
            frame: .zero
        )
        
        let view = TaskbarView(
            theme: ModernHybridTheme.definition,
            launcherAction: .spotlight,
            store: store
        )
        view.screenID = 1
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        view.updateWindows(windows: [win1, win2], focusedKey: nil, frontmostPID: nil)
        view.layout()
        
        guard let btnA = view.button(forKey: win1.key),
              let btnB = view.button(forKey: win2.key) else {
            Issue.record("Expected buttons to exist")
            return
        }
        
        let initialAX = btnA.frame.minX
        let initialBX = btnB.frame.minX
        
        // Case 1: Vertical departure (> 30pt out of taskbar)
        let startLoc = NSPoint(x: btnA.frame.midX, y: btnA.frame.midY)
        btnA.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: startLoc))
        btnA.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: startLoc.x + 20.0, y: startLoc.y)))
        #expect(btnA.isDragging)
        
        // Move vertically > 30pt away from bottom (local y < -30)
        btnA.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: startLoc.x + 20.0, y: -50.0)))
        #expect(!btnA.isDragging, "Vertical departure must cancel drag")
        
        btnA.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: startLoc.x + 20.0, y: -50.0)))
        
        // Frames must remain unchanged
        #expect(btnA.frame.minX == initialAX)
        #expect(btnB.frame.minX == initialBX)
        
        // Case 2: Escape key press
        btnA.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: startLoc))
        btnA.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: startLoc.x + 20.0, y: startLoc.y)))
        #expect(btnA.isDragging)
        
        // Press Escape key
        btnA.keyDown(with: makeKeyEvent(keyCode: TaskbarConstants.KeyCodes.escape))
        #expect(!btnA.isDragging, "Escape key must cancel drag")
        
        btnA.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: startLoc.x + 20.0, y: startLoc.y)))
        #expect(btnA.frame.minX == initialAX)
    }
    
    // TC-DRAG-003: Multi-display drag isolation: dragging on Display 1 does not disrupt Display 2 button layout.
    @Test("TC-DRAG-003: Multi-display drag isolation maintains independent custom ordering")
    func testMultiDisplayDragIsolation() {
        let store = WindowStore()
        let screens = [
            ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true),
            ScreenDescriptor(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false)
        ]
        
        let win1 = WindowInfo(
            key: WindowKey(id: 1, pid: 10),
            pid: 10,
            appName: "Screen1_AppA",
            bundleID: "com.test.s1a",
            title: "S1_A",
            frame: CGRect(x: 100, y: 100, width: 500, height: 500) // Screen 1
        )
        let win2 = WindowInfo(
            key: WindowKey(id: 2, pid: 20),
            pid: 20,
            appName: "Screen1_AppB",
            bundleID: "com.test.s1b",
            title: "S1_B",
            frame: CGRect(x: 200, y: 200, width: 500, height: 500) // Screen 1
        )
        let win3 = WindowInfo(
            key: WindowKey(id: 3, pid: 30),
            pid: 30,
            appName: "Screen2_AppC",
            bundleID: "com.test.s2c",
            title: "S2_C",
            frame: CGRect(x: 2100, y: 100, width: 500, height: 500) // Screen 2
        )
        let win4 = WindowInfo(
            key: WindowKey(id: 4, pid: 40),
            pid: 40,
            appName: "Screen2_AppD",
            bundleID: "com.test.s2d",
            title: "S2_D",
            frame: CGRect(x: 2200, y: 200, width: 500, height: 500) // Screen 2
        )
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        store.addOrUpdateWindow(win3)
        store.addOrUpdateWindow(win4)
        
        let view1 = TaskbarView(theme: ModernHybridTheme.definition, launcherAction: .spotlight, store: store)
        view1.screenID = 1
        view1.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        view1.updateWindows(windows: [win1, win2], focusedKey: nil, frontmostPID: nil)
        view1.layout()
        
        let view2 = TaskbarView(theme: ModernHybridTheme.definition, launcherAction: .spotlight, store: store)
        view2.screenID = 2
        view2.frame = NSRect(x: 0, y: 0, width: 800, height: 30)
        view2.updateWindows(windows: [win3, win4], focusedKey: nil, frontmostPID: nil)
        view2.layout()
        
        // Reorder Screen 1 buttons: drag win1 past win2
        guard let btnS1A = view1.button(forKey: win1.key),
              let btnS1B = view1.button(forKey: win2.key),
              let btnS2C = view2.button(forKey: win3.key),
              let btnS2D = view2.button(forKey: win4.key) else {
            Issue.record("Expected all buttons to exist")
            return
        }
        
        let startLoc = NSPoint(x: btnS1A.frame.midX, y: btnS1A.frame.midY)
        btnS1A.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: startLoc))
        btnS1A.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: btnS1B.frame.maxX + 20.0, y: btnS1B.frame.midY)))
        btnS1A.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: btnS1B.frame.maxX + 20.0, y: btnS1B.frame.midY)))
        
        // Verify View 1 reordered
        #expect(btnS1B.frame.minX < btnS1A.frame.minX)
        
        // Verify View 2 is completely undisturbed
        #expect(btnS2C.frame.minX < btnS2D.frame.minX)
        
        // Verify custom orders in store
        let order1 = store.customOrder(forScreenID: 1)
        let order2 = store.customOrder(forScreenID: 2)
        #expect(order1["win_20_2"] == 0)
        #expect(order1["win_10_1"] == 1)
        #expect(order2.isEmpty, "Screen 2 custom order must remain unperturbed")
        
        // Verify queried windows
        let s1Windows = store.windows(forScreenID: 1, screens: screens)
        let s2Windows = store.windows(forScreenID: 2, screens: screens)
        #expect(s1Windows.map { $0.key } == [win2.key, win1.key])
        #expect(s2Windows.map { $0.key } == [win3.key, win4.key])
    }
    
    // TC-DRAG-004: Dragging a pinned button reorders Settings.pinnedApps, immediately persists to disk, and broadcasts the new order across all displays.
    @Test("TC-DRAG-004: Dragging pinned button reorders Settings and syncs across all displays")
    func testPinnedButtonDragReorderMultiDisplaySync() {
        let initialPinned = [
            PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder"),
            PinnedApp(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal"),
            PinnedApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari")
        ]
        let settings = Settings(pinnedApps: initialPinned)
        let store = WindowStore()
        let manager = ScreenManager(settings: settings, store: store)
        
        let panels = manager.allPanels
        #expect(!panels.isEmpty)
        
        let firstPanel = panels[0]
        let view = firstPanel.taskbarView
        let pinnedBtns = view.allPinnedButtons
        #expect(pinnedBtns.count == 3)
        
        let finderBtn = pinnedBtns[0]
        let terminalBtn = pinnedBtns[1]
        
        // Drag Finder (index 0) past Terminal (index 1) to slot 2
        let startLoc = NSPoint(x: finderBtn.frame.midX, y: finderBtn.frame.midY)
        finderBtn.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: startLoc))
        
        let dropLoc = NSPoint(x: terminalBtn.frame.maxX + 1.0, y: terminalBtn.frame.midY)
        finderBtn.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: dropLoc))
        #expect(finderBtn.isDragging)
        
        finderBtn.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: dropLoc))
        #expect(!finderBtn.isDragging)
        
        // Verify Settings.pinnedApps has new order: [Terminal, Finder, Safari]
        let expectedIDs = ["com.apple.Terminal", "com.apple.finder", "com.apple.Safari"]
        #expect(manager.settings.pinnedApps.map { $0.bundleIdentifier } == expectedIDs)
        
        // Verify ALL display panels received and applied the synchronized new order
        for panel in manager.allPanels {
            let panelPinnedIDs = panel.taskbarView.allPinnedButtons.map { $0.pinnedApp.bundleIdentifier }
            #expect(panelPinnedIDs == expectedIDs)
        }
        
        manager.closeAll()
    }
}
