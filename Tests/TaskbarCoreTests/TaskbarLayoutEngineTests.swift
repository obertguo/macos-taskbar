// Tests/TaskbarCoreTests/TaskbarLayoutEngineTests.swift

import XCTest
import CoreGraphics
@testable import TaskbarCore

final class TaskbarLayoutEngineTests: XCTestCase {
    
    func testEmptyTaskbarLayout() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 800, height: 30),
            startButtonWidth: 60,
            pinnedItemCount: 0,
            taskItemCount: 0
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        XCTAssertEqual(plan.buttonHeight, 26.0) // 30 - 2*2
        XCTAssertEqual(plan.startButtonFrame, CGRect(x: 3, y: 2, width: 60, height: 26))
        XCTAssertTrue(plan.pinnedButtonFrames.isEmpty)
        XCTAssertTrue(plan.taskButtonFrames.isEmpty)
        XCTAssertNil(plan.overflowButtonFrame)
        XCTAssertEqual(plan.visibleTaskCount, 0)
        XCTAssertFalse(plan.hasOverflow)
    }
    
    func testPinnedOnlyLayout() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 800, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 3,
            taskItemCount: 0
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        XCTAssertEqual(plan.pinnedButtonFrames.count, 3)
        // btnH is 26. First pinned button starts at startBtn.maxX (53) + 4 = 57
        XCTAssertEqual(plan.pinnedButtonFrames[0], CGRect(x: 57, y: 2, width: 26, height: 26))
        // Second pinned: 57 + 26 + 2 = 85
        XCTAssertEqual(plan.pinnedButtonFrames[1], CGRect(x: 85, y: 2, width: 26, height: 26))
        // Third pinned: 85 + 26 + 2 = 113
        XCTAssertEqual(plan.pinnedButtonFrames[2], CGRect(x: 113, y: 2, width: 26, height: 26))
        
        XCTAssertTrue(plan.taskButtonFrames.isEmpty)
        XCTAssertNil(plan.overflowButtonFrame)
    }
    
    func testStandardTaskbarLayoutAmpleSpace() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 1000, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 2,
            taskItemCount: 3,
            minButtonWidth: 80,
            maxButtonWidth: 160,
            buttonSpacing: 4
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        XCTAssertEqual(plan.visibleTaskCount, 3)
        XCTAssertFalse(plan.hasOverflow)
        XCTAssertNil(plan.overflowButtonFrame)
        XCTAssertEqual(plan.taskButtonWidth, 160.0)
        XCTAssertTrue(plan.showTitle)
        XCTAssertEqual(plan.taskButtonFrames.count, 3)
        
        // Pinned section ends at: 3 (start leading) + 50 + 4 (start trailing) = 57
        // Pinned 0: 57, w=26. Next: 57 + 26 + 2 = 85
        // Pinned 1: 85, w=26. Trailing: 85 + 26 + 2 (added) + (6 - 2) = 117
        XCTAssertEqual(plan.taskButtonFrames[0].minX, 117.0)
        XCTAssertEqual(plan.taskButtonFrames[0].width, 160.0)
        XCTAssertEqual(plan.taskButtonFrames[1].minX, 117.0 + 160.0 + 4.0)
        XCTAssertEqual(plan.taskButtonFrames[2].minX, 117.0 + (160.0 + 4.0) * 2.0)
    }
    
    func testCompressedTaskbarLayout() {
        // Available width for tasks: 400. 4 tasks at max 160 would need ~650.
        // They should compress evenly without overflowing.
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 450, height: 30),
            startButtonWidth: 40,
            pinnedItemCount: 0,
            taskItemCount: 4,
            minButtonWidth: 80,
            maxButtonWidth: 160,
            buttonSpacing: 2
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        XCTAssertEqual(plan.visibleTaskCount, 4)
        XCTAssertFalse(plan.hasOverflow)
        XCTAssertNil(plan.overflowButtonFrame)
        XCTAssertGreaterThanOrEqual(plan.taskButtonWidth, 80.0)
        XCTAssertLessThanOrEqual(plan.taskButtonWidth, 160.0)
        XCTAssertTrue(plan.showTitle)
    }
    
    func testOverflowActivationAndReservation() {
        // Container width 300, 5 tasks with min 80 -> needs at least 5 * 80 = 400 + margins
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 300, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 0,
            taskItemCount: 5,
            minButtonWidth: 80,
            maxButtonWidth: 160,
            buttonSpacing: 2
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        XCTAssertTrue(plan.hasOverflow)
        XCTAssertNotNil(plan.overflowButtonFrame)
        XCTAssertLessThan(plan.visibleTaskCount, 5)
        
        // Overflow button placed on trailing edge
        let expectedOverflowX = 300.0 - params.overflowButtonWidth - params.overflowButtonTrailingMargin
        XCTAssertEqual(plan.overflowButtonFrame?.minX, expectedOverflowX)
        XCTAssertEqual(plan.overflowButtonFrame?.width, params.overflowButtonWidth)
        XCTAssertEqual(plan.overflowButtonFrame?.height, 26.0)
        
        // Task button frames beyond visible count are CGRect.zero
        for i in plan.visibleTaskCount..<5 {
            XCTAssertEqual(plan.taskButtonFrames[i], .zero)
        }
    }
    
    func testZeroOrConstrainedContainerSize() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 0, height: 0),
            startButtonWidth: 50,
            pinnedItemCount: 2,
            taskItemCount: 3
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        // Enforces minimumButtonHeight (18.0)
        XCTAssertEqual(plan.buttonHeight, 18.0)
        XCTAssertEqual(plan.visibleTaskCount, 0)
        XCTAssertEqual(plan.taskButtonFrames.count, 3)
    }
    
    func testSlotIndexHitTesting() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 800, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 0,
            taskItemCount: 3,
            minButtonWidth: 100,
            maxButtonWidth: 100,
            buttonSpacing: 10
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        XCTAssertEqual(plan.visibleTaskCount, 3)
        let slot0X = plan.taskButtonFrames[0].midX
        let slot1X = plan.taskButtonFrames[1].midX
        let slot2X = plan.taskButtonFrames[2].midX
        
        XCTAssertEqual(plan.slotIndex(atX: slot0X), 0)
        XCTAssertEqual(plan.slotIndex(atX: slot1X), 1)
        XCTAssertEqual(plan.slotIndex(atX: slot2X), 2)
        
        // Points before or between/after buttons
        XCTAssertNil(plan.slotIndex(atX: 10.0)) // Within Start button region
        XCTAssertNil(plan.slotIndex(atX: 799.0)) // Past tasks
    }
    
    // MARK: - TC-UNIT-014: Primary Axis Slot Calculation (Horizontal Layout)
    
    func testHorizontalTaskbarLayoutSlotCalculations() {
        // Vertical layout is quarantined until v0.4.0; layout engine strictly operates horizontally.
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 800, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 2,
            taskItemCount: 3,
            edge: .bottom,
            minButtonWidth: 80,
            maxButtonWidth: 160,
            buttonSpacing: 4
        )
        
        XCTAssertEqual(params.primaryDimension, 800.0)
        XCTAssertEqual(params.crossDimension, 30.0)
        
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        // Button cross thickness: 30 - 2*2 = 26
        XCTAssertEqual(plan.buttonHeight, 26.0)
        
        // Start button: x = 3 (leadingMargin), y = 2 (padCross), width = 50, height = 26
        XCTAssertEqual(plan.startButtonFrame, CGRect(x: 3, y: 2, width: 50, height: 26))
        
        // Pinned buttons: square 26x26
        // Pinned 0: x = 3 + 50 + 4 = 57
        XCTAssertEqual(plan.pinnedButtonFrames.count, 2)
        XCTAssertEqual(plan.pinnedButtonFrames[0], CGRect(x: 57, y: 2, width: 26, height: 26))
        // Pinned 1: 57 + 26 + 2 = 85
        XCTAssertEqual(plan.pinnedButtonFrames[1], CGRect(x: 85, y: 2, width: 26, height: 26))
        
        // Task buttons along horizontal axis X
        XCTAssertEqual(plan.visibleTaskCount, 3)
        XCTAssertEqual(plan.taskButtonFrames.count, 3)
        for frame in plan.taskButtonFrames {
            XCTAssertEqual(frame.minY, 2.0)
            XCTAssertEqual(frame.height, 26.0)
        }
        
        // Hit-testing along horizontal axis X
        let task0MidX = plan.taskButtonFrames[0].midX
        let task1MidX = plan.taskButtonFrames[1].midX
        let task2MidX = plan.taskButtonFrames[2].midX
        
        XCTAssertEqual(plan.slotIndex(forPosition: task0MidX, edge: .bottom), 0)
        XCTAssertEqual(plan.slotIndex(forPosition: task1MidX, edge: .bottom), 1)
        XCTAssertEqual(plan.slotIndex(forPosition: task2MidX, edge: .bottom), 2)
        XCTAssertEqual(TaskbarLayoutEngine.slotIndex(forPosition: Double(task1MidX), edge: .bottom, in: plan), 1)
        
        // Insertion slots along horizontal axis
        XCTAssertEqual(plan.taskInsertionSlot(forPosition: plan.taskButtonFrames[0].minX - 1, edge: .bottom), 0)
        XCTAssertEqual(plan.taskInsertionSlot(forPosition: plan.taskButtonFrames[2].maxX + 10, edge: .bottom), 3)
        
        // Insertion indicator position along horizontal axis
        let indicator0 = plan.taskInsertionIndicatorPosition(forSlot: 0, buttonSpacing: 4, edge: .bottom)
        XCTAssertNotNil(indicator0)
        XCTAssertEqual(indicator0!, plan.taskButtonFrames[0].minX - 2.0)
        
        let indicator3 = plan.taskInsertionIndicatorPosition(forSlot: 3, buttonSpacing: 4, edge: .bottom)
        XCTAssertNotNil(indicator3)
        XCTAssertEqual(indicator3!, plan.taskButtonFrames[2].maxX + 2.0)
        
        // Pinned insertion slots along horizontal axis
        XCTAssertEqual(plan.pinnedInsertionSlot(forPosition: plan.pinnedButtonFrames[0].minX - 1, edge: .bottom), 0)
        XCTAssertEqual(plan.pinnedInsertionSlot(forPosition: plan.pinnedButtonFrames[1].maxX + 1, edge: .bottom), 2)
        
        // Pinned insertion indicator position along horizontal axis
        let pinnedIndicator0 = plan.pinnedInsertionIndicatorPosition(forSlot: 0, pinnedSpacing: 2, edge: .bottom)
        XCTAssertNotNil(pinnedIndicator0)
        XCTAssertEqual(pinnedIndicator0!, plan.pinnedButtonFrames[0].minX - 1.0)
    }
}
