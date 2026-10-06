// Tests/TaskbarCoreTests/WindowOrderingLogicTests.swift

import XCTest
import CoreGraphics
@testable import TaskbarCore

final class WindowOrderingLogicTests: XCTestCase {
    
    private func makeGroup(id: String, appName: String) -> WindowGroup {
        let win = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
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
    func testReorderItemShiftsIndices() {
        let groupA = makeGroup(id: "A", appName: "AppA")
        let groupB = makeGroup(id: "B", appName: "AppB")
        let groupC = makeGroup(id: "C", appName: "AppC")
        let initialItems = [groupA, groupB, groupC]
        
        // Move item 0 ("A") to index 2
        let (reordered1, orderMap1) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: 0, toIndex: 2)
        XCTAssertEqual(reordered1.map { $0.id }, ["B", "C", "A"])
        XCTAssertEqual(orderMap1["B"], 0)
        XCTAssertEqual(orderMap1["C"], 1)
        XCTAssertEqual(orderMap1["A"], 2)
        
        // Move item 2 ("A") to index 0
        let (reordered2, orderMap2) = WindowOrderingLogic.moveItem(in: reordered1, fromIndex: 2, toIndex: 0)
        XCTAssertEqual(reordered2.map { $0.id }, ["A", "B", "C"])
        XCTAssertEqual(orderMap2["A"], 0)
        XCTAssertEqual(orderMap2["B"], 1)
        XCTAssertEqual(orderMap2["C"], 2)
        
        // Out of bounds moves return original array safely
        let (reorderedOOB1, _) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: -1, toIndex: 1)
        XCTAssertEqual(reorderedOOB1.map { $0.id }, ["A", "B", "C"])
        
        let (reorderedOOB2, _) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: 0, toIndex: 99)
        XCTAssertEqual(reorderedOOB2.map { $0.id }, ["A", "B", "C"])
        
        // Moving to same index returns same array
        let (reorderedSame, _) = WindowOrderingLogic.moveItem(in: initialItems, fromIndex: 1, toIndex: 1)
        XCTAssertEqual(reorderedSame.map { $0.id }, ["A", "B", "C"])
    }
    
    // TC-UNIT-010: Newly opened windows append without clobbering manual order
    func testCustomOrderPersistsAcrossNewWindows() {
        let groupA = makeGroup(id: "A", appName: "AppA")
        let groupB = makeGroup(id: "B", appName: "AppB")
        let groupC = makeGroup(id: "C", appName: "AppC")
        let groupNew1 = makeGroup(id: "New1", appName: "AppNew1")
        let groupNew2 = makeGroup(id: "New2", appName: "AppNew2")
        
        // User manually ordered: B at 0, A at 1, C at 2
        let customOrder: [String: Int] = ["B": 0, "A": 1, "C": 2]
        
        // Incoming items include newly discovered apps New1 and New2
        let incomingItems = [groupA, groupNew1, groupB, groupNew2, groupC]
        let sorted = WindowOrderingLogic.applyCustomOrder(items: incomingItems, customOrder: customOrder)
        
        // Expected result: Manually ordered items first in custom order [B, A, C],
        // followed by newly discovered items preserving their relative arrival order [New1, New2]
        XCTAssertEqual(sorted.map { $0.id }, ["B", "A", "C", "New1", "New2"])
    }
    
    // TC-UNIT-011: Closed windows cleanly removed from order dictionary
    func testCustomOrderPurgesClosedWindows() {
        let order: [String: Int] = [
            "win_1": 0,
            "win_2": 1,
            "win_3": 2,
            "win_4": 3
        ]
        
        // Suppose win_2 and win_4 closed; active IDs are win_1 and win_3
        let activeIDs: Set<String> = ["win_1", "win_3"]
        let pruned = WindowOrderingLogic.pruneOrderMap(order, activeIDs: activeIDs)
        
        XCTAssertEqual(pruned.count, 2)
        XCTAssertEqual(pruned["win_1"], 0)
        XCTAssertEqual(pruned["win_3"], 2)
        XCTAssertNil(pruned["win_2"])
        XCTAssertNil(pruned["win_4"])
    }
    
    func testEmptyInputs() {
        let empty = WindowOrderingLogic.applyCustomOrder(items: [], customOrder: ["A": 0])
        XCTAssertTrue(empty.isEmpty)
        
        let groupA = makeGroup(id: "A", appName: "AppA")
        let noCustomOrder = WindowOrderingLogic.applyCustomOrder(items: [groupA], customOrder: [:])
        XCTAssertEqual(noCustomOrder.map { $0.id }, ["A"])
    }
}
