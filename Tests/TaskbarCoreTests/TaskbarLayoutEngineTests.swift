// Tests/TaskbarCoreTests/TaskbarLayoutEngineTests.swift

import CoreGraphics
import Testing
@testable import TaskbarCore

@Suite("Taskbar Layout Engine Tests")
struct TaskbarLayoutEngineTests {
    
    @Test("Empty taskbar layout")
    func testEmptyTaskbarLayout() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 800, height: 30),
            startButtonWidth: 60,
            pinnedItemCount: 0,
            taskItemCount: 0
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        #expect(plan.buttonHeight == 26.0) // 30 - 2*2
        #expect(plan.startButtonFrame == CGRect(x: 3, y: 2, width: 60, height: 26))
        #expect(plan.pinnedButtonFrames.isEmpty)
        #expect(plan.taskButtonFrames.isEmpty)
        #expect(plan.overflowButtonFrame == nil)
        #expect(plan.visibleTaskCount == 0)
        #expect(!plan.hasOverflow)
    }
    
    @Test("Pinned only layout")
    func testPinnedOnlyLayout() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 800, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 3,
            taskItemCount: 0
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        #expect(plan.pinnedButtonFrames.count == 3)
        // btnH is 26. First pinned button starts at startBtn.maxX (53) + 4 = 57
        #expect(plan.pinnedButtonFrames[0] == CGRect(x: 57, y: 2, width: 26, height: 26))
        // Second pinned: 57 + 26 + 2 = 85
        #expect(plan.pinnedButtonFrames[1] == CGRect(x: 85, y: 2, width: 26, height: 26))
        // Third pinned: 85 + 26 + 2 = 113
        #expect(plan.pinnedButtonFrames[2] == CGRect(x: 113, y: 2, width: 26, height: 26))
        
        #expect(plan.taskButtonFrames.isEmpty)
        #expect(plan.overflowButtonFrame == nil)
    }
    
    @Test("Standard taskbar layout with ample space")
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
        
        #expect(plan.visibleTaskCount == 3)
        #expect(!plan.hasOverflow)
        #expect(plan.overflowButtonFrame == nil)
        #expect(plan.taskButtonWidth == 160.0)
        #expect(plan.showTitle)
        #expect(plan.taskButtonFrames.count == 3)
        
        // Pinned section ends at: 3 (start leading) + 50 + 4 (start trailing) = 57
        // Pinned 0: 57, w=26. Next: 57 + 26 + 2 = 85
        // Pinned 1: 85, w=26. Trailing: 85 + 26 + 2 (added) + (6 - 2) = 117
        #expect(abs(plan.taskButtonFrames[0].minX - 117.0) < 0.001)
        #expect(abs(plan.taskButtonFrames[0].width - 160.0) < 0.001)
        #expect(abs(plan.taskButtonFrames[1].minX - (117.0 + 160.0 + 4.0)) < 0.001)
        #expect(abs(plan.taskButtonFrames[2].minX - (117.0 + (160.0 + 4.0) * 2.0)) < 0.001)
    }
    
    @Test("Compressed taskbar layout")
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
        
        #expect(plan.visibleTaskCount == 4)
        #expect(!plan.hasOverflow)
        #expect(plan.overflowButtonFrame == nil)
        #expect(plan.taskButtonWidth >= 80.0)
        #expect(plan.taskButtonWidth <= 160.0)
        #expect(plan.showTitle)
    }
    
    @Test("Overflow activation and reservation")
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
        
        #expect(plan.hasOverflow)
        #expect(plan.overflowButtonFrame != nil)
        #expect(plan.visibleTaskCount < 5)
        
        // Overflow button placed on trailing edge
        let expectedOverflowX = 300.0 - params.overflowButtonWidth - params.overflowButtonTrailingMargin
        #expect(plan.overflowButtonFrame?.minX == expectedOverflowX)
        #expect(plan.overflowButtonFrame?.width == params.overflowButtonWidth)
        #expect(plan.overflowButtonFrame?.height == 26.0)
        
        // Task button frames beyond visible count are CGRect.zero
        for i in plan.visibleTaskCount..<5 {
            #expect(plan.taskButtonFrames[i] == .zero)
        }
    }
    
    @Test("Zero or constrained container size")
    func testZeroOrConstrainedContainerSize() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 0, height: 0),
            startButtonWidth: 50,
            pinnedItemCount: 2,
            taskItemCount: 3
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        // Enforces minimumButtonHeight (18.0)
        #expect(plan.buttonHeight == 18.0)
        #expect(plan.visibleTaskCount == 0)
        #expect(plan.taskButtonFrames.count == 3)
    }
    
    @Test("Slot index hit testing")
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
        
        #expect(plan.visibleTaskCount == 3)
        let slot0X = plan.taskButtonFrames[0].midX
        let slot1X = plan.taskButtonFrames[1].midX
        let slot2X = plan.taskButtonFrames[2].midX
        
        #expect(plan.slotIndex(atX: slot0X) == 0)
        #expect(plan.slotIndex(atX: slot1X) == 1)
        #expect(plan.slotIndex(atX: slot2X) == 2)
        
        // Points before or between/after buttons
        #expect(plan.slotIndex(atX: 10.0) == nil) // Within Start button region
        #expect(plan.slotIndex(atX: 799.0) == nil) // Past tasks
    }
    
    // MARK: - TC-UNIT-014: Primary Axis Slot Calculation (Horizontal Layout)
    
    @Test("Horizontal taskbar layout slot calculations")
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
        
        #expect(params.primaryDimension == 800.0)
        #expect(params.crossDimension == 30.0)
        
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        // Button cross thickness: 30 - 2*2 = 26
        #expect(plan.buttonHeight == 26.0)
        
        // Start button: x = 3 (leadingMargin), y = 2 (padCross), width = 50, height = 26
        #expect(plan.startButtonFrame == CGRect(x: 3, y: 2, width: 50, height: 26))
        
        // Pinned buttons: square 26x26
        // Pinned 0: x = 3 + 50 + 4 = 57
        #expect(plan.pinnedButtonFrames.count == 2)
        #expect(plan.pinnedButtonFrames[0] == CGRect(x: 57, y: 2, width: 26, height: 26))
        // Pinned 1: 57 + 26 + 2 = 85
        #expect(plan.pinnedButtonFrames[1] == CGRect(x: 85, y: 2, width: 26, height: 26))
        
        // Task buttons along horizontal axis X
        #expect(plan.visibleTaskCount == 3)
        #expect(plan.taskButtonFrames.count == 3)
        for frame in plan.taskButtonFrames {
            #expect(frame.minY == 2.0)
            #expect(frame.height == 26.0)
        }
        
        // Hit-testing along horizontal axis X
        let task0MidX = plan.taskButtonFrames[0].midX
        let task1MidX = plan.taskButtonFrames[1].midX
        let task2MidX = plan.taskButtonFrames[2].midX
        
        #expect(plan.slotIndex(forPosition: task0MidX, edge: .bottom) == 0)
        #expect(plan.slotIndex(forPosition: task1MidX, edge: .bottom) == 1)
        #expect(plan.slotIndex(forPosition: task2MidX, edge: .bottom) == 2)
        #expect(TaskbarLayoutEngine.slotIndex(forPosition: Double(task1MidX), edge: .bottom, in: plan) == 1)
        
        // Insertion slots along horizontal axis
        #expect(plan.taskInsertionSlot(forPosition: plan.taskButtonFrames[0].minX - 1, edge: .bottom) == 0)
        #expect(plan.taskInsertionSlot(forPosition: plan.taskButtonFrames[2].maxX + 10, edge: .bottom) == 3)
        
        // Insertion indicator position along horizontal axis
        let indicator0 = plan.taskInsertionIndicatorPosition(forSlot: 0, buttonSpacing: 4, edge: .bottom)
        #expect(indicator0 != nil)
        if let indicator0 {
            #expect(abs(indicator0 - (plan.taskButtonFrames[0].minX - 2.0)) < 0.001)
        }
        
        let indicator3 = plan.taskInsertionIndicatorPosition(forSlot: 3, buttonSpacing: 4, edge: .bottom)
        #expect(indicator3 != nil)
        if let indicator3 {
            #expect(abs(indicator3 - (plan.taskButtonFrames[2].maxX + 2.0)) < 0.001)
        }
        
        // Pinned insertion slots along horizontal axis
        #expect(plan.pinnedInsertionSlot(forPosition: plan.pinnedButtonFrames[0].minX - 1, edge: .bottom) == 0)
        #expect(plan.pinnedInsertionSlot(forPosition: plan.pinnedButtonFrames[1].maxX + 1, edge: .bottom) == 2)
        
        // Pinned insertion indicator position along horizontal axis
        let pinnedIndicator0 = plan.pinnedInsertionIndicatorPosition(forSlot: 0, pinnedSpacing: 2, edge: .bottom)
        #expect(pinnedIndicator0 != nil)
        if let pinnedIndicator0 {
            #expect(abs(pinnedIndicator0 - (plan.pinnedButtonFrames[0].minX - 1.0)) < 0.001)
        }
    }
}
