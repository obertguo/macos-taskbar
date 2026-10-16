// Tests/TaskbarCoreTests/WindowOrderingLogicTests.swift

import CoreGraphics
import Foundation
import Testing
@testable import TaskbarCore

@Suite("Window Ordering Logic Tests")
struct WindowOrderingLogicTests {
    
    private func makeGroup(id: String, appName: String, winID: UInt64? = nil, pid: pid_t? = nil) -> WindowGroup {
        let derivedID = winID ?? UInt64(abs(id.utf8.reduce(0) { ($0 << 5) &+ $0 &+ Int($1) }) % 10000 + 1)
        let derivedPID = pid ?? pid_t(abs(appName.utf8.reduce(0) { ($0 << 5) &+ $0 &+ Int($1) }) % 10000 + 100)
        let win = WindowInfo(
            key: WindowKey(id: derivedID, pid: derivedPID),
            pid: derivedPID,
            appName: appName,
            bundleID: "com.test.\(appName)",
            title: appName,
            frame: .zero
        )
        return WindowGroup(
            id: id,
            bundleID: "com.test.\(appName)",
            appName: appName,
            windows: [win],
            isGrouped: false
        )
    }
    
    // TC-UNIT-009: Validates slot move array operations
    @Test("Reorder item shifts indices and maps keys")
    func testReorderItemShiftsIndices() {
        let groupA = makeGroup(id: "A", appName: "AppA")
        let groupB = makeGroup(id: "B", appName: "AppB")
        let groupC = makeGroup(id: "C", appName: "AppC")
        let initialItems = [groupA, groupB, groupC]
        
        // Move item 0 ("A") to index 2
        let (reordered1, orderMap1) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: 0, toIndex: 2)
        #expect(reordered1.map { $0.id } == ["B", "C", "A"])
        #expect(orderMap1[.app("com.test.AppB")] == 0)
        #expect(orderMap1[.app("com.test.AppC")] == 1)
        #expect(orderMap1[.app("com.test.AppA")] == 2)
        #expect(orderMap1[.window(groupB.windows[0].key)] == 0)
        #expect(orderMap1[.window(groupC.windows[0].key)] == 1)
        #expect(orderMap1[.window(groupA.windows[0].key)] == 2)
        
        // Move item 2 ("A") to index 0
        let (reordered2, orderMap2) = WindowOrderingLogic.moveItem(in: reordered1, fromIndex: 2, toIndex: 0)
        #expect(reordered2.map { $0.id } == ["A", "B", "C"])
        #expect(orderMap2[.app("com.test.AppA")] == 0)
        #expect(orderMap2[.app("com.test.AppB")] == 1)
        #expect(orderMap2[.app("com.test.AppC")] == 2)
        
        // Out of bounds moves return original array safely
        let (reorderedOOB1, _) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: -1, toIndex: 1)
        #expect(reorderedOOB1.map { $0.id } == ["A", "B", "C"])
        
        let (reorderedOOB2, _) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: 0, toIndex: 99)
        #expect(reorderedOOB2.map { $0.id } == ["A", "B", "C"])
        
        // Moving to same index returns same array
        let (reorderedSame, _) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: 1, toIndex: 1)
        #expect(reorderedSame.map { $0.id } == ["A", "B", "C"])
    }
    
    // TC-UNIT-010: Newly opened windows append without clobbering manual order
    @Test("Custom order persists across new windows")
    func testCustomOrderPersistsAcrossNewWindows() {
        let groupA = makeGroup(id: "A", appName: "AppA")
        let groupB = makeGroup(id: "B", appName: "AppB")
        let groupC = makeGroup(id: "C", appName: "AppC")
        let groupNew1 = makeGroup(id: "New1", appName: "AppNew1")
        let groupNew2 = makeGroup(id: "New2", appName: "AppNew2")
        
        // User manually ordered: B at 0, A at 1, C at 2
        let customOrder: [OrderKey: Int] = [
            .app("com.test.AppB"): 0,
            .app("com.test.AppA"): 1,
            .app("com.test.AppC"): 2
        ]
        
        // Incoming items include newly discovered apps New1 and New2
        let incomingItems = [groupA, groupNew1, groupB, groupNew2, groupC]
        let sorted = WindowOrderingLogic.applyCustomOrder(items: incomingItems, customOrder: customOrder)
        
        // Expected result: Manually ordered items first in custom order [B, A, C],
        // followed by newly discovered items preserving their relative arrival order [New1, New2]
        #expect(sorted.map { $0.id } == ["B", "A", "C", "New1", "New2"])
    }
    
    // TC-UNIT-011: Closed windows cleanly removed from order dictionary
    @Test("Custom order purges closed windows")
    func testCustomOrderPurgesClosedWindows() {
        let key1 = WindowKey(id: 1, pid: 100)
        let key2 = WindowKey(id: 2, pid: 100)
        let key3 = WindowKey(id: 3, pid: 100)
        let key4 = WindowKey(id: 4, pid: 100)
        
        let order: [OrderKey: Int] = [
            .window(key1): 0,
            .window(key2): 1,
            .window(key3): 2,
            .window(key4): 3,
            .app("com.test.AppA"): 0
        ]
        
        // Suppose win_2 and win_4 closed; active keys are win_1, win_3, and AppA
        let activeKeys: Set<OrderKey> = [
            .window(key1),
            .window(key3),
            .app("com.test.AppA")
        ]
        let pruned = WindowOrderingLogic.pruneOrderMap(order, activeKeys: activeKeys)
        
        #expect(pruned.count == 3)
        #expect(pruned[.window(key1)] == 0)
        #expect(pruned[.window(key3)] == 2)
        #expect(pruned[.app("com.test.AppA")] == 0)
        #expect(pruned[.window(key2)] == nil)
        #expect(pruned[.window(key4)] == nil)
    }
    
    @Test("Empty inputs handling")
    func testEmptyInputs() {
        let empty = WindowOrderingLogic.applyCustomOrder(items: [], customOrder: [.app("com.test.AppA"): 0])
        #expect(empty.isEmpty)
        
        let groupA = makeGroup(id: "A", appName: "AppA")
        let noCustomOrder = WindowOrderingLogic.applyCustomOrder(items: [groupA], customOrder: [:])
        #expect(noCustomOrder.map { $0.id } == ["A"])
    }
    
    @Test("Single pass decorate sort undecorate with window and app slots")
    func testSinglePassDecorateSortUndecorateWithWindowAndAppSlots() {
        let win1 = WindowInfo(key: WindowKey(id: 10, pid: 1), pid: 1, appName: "App1", bundleID: "com.test.app1", title: "W1", frame: .zero)
        let win2 = WindowInfo(key: WindowKey(id: 20, pid: 2), pid: 2, appName: "App2", bundleID: "com.test.app2", title: "W2", frame: .zero)
        let win3 = WindowInfo(key: WindowKey(id: 30, pid: 3), pid: 3, appName: "App3", bundleID: "com.test.app3", title: "W3", frame: .zero)
        
        let group1 = WindowGroup(id: "G1", bundleID: "com.test.app1", appName: "App1", windows: [win1], isGrouped: true)
        let group2 = WindowGroup(id: "G2", bundleID: "com.test.app2", appName: "App2", windows: [win2], isGrouped: true)
        let group3 = WindowGroup(id: "G3", bundleID: "com.test.app3", appName: "App3", windows: [win3], isGrouped: true)
        
        // Order group3 first via app slot, group1 second via window slot, group2 unassigned
        let customOrder: [OrderKey: Int] = [
            .app("com.test.app3"): 0,
            .window(win1.key): 1
        ]
        
        let sorted = WindowOrderingLogic.applyCustomOrder(items: [group1, group2, group3], customOrder: customOrder)
        #expect(sorted.map { $0.id } == ["G3", "G1", "G2"])
    }
}
