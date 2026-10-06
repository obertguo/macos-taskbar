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
}
