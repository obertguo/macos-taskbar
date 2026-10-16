// Tests/TaskbarCoreTests/TaskbarLayoutEngineDragTests.swift

import CoreGraphics
import Testing
@testable import TaskbarCore

@Suite("Taskbar Layout Engine Drag Tests")
struct TaskbarLayoutEngineDragTests {
    
    // TC-UNIT-012: Validates drag slot math and boundary clamping
    @Test("Task insertion slot calculation and boundary clamping")
    func testTaskInsertionSlotCalculation() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 1000, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 0,
            taskItemCount: 3,
            minButtonWidth: 100,
            maxButtonWidth: 100,
            buttonSpacing: 4
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        #expect(plan.visibleTaskCount == 3)
        #expect(plan.taskButtonFrames.count == 3)
        
        let f0 = plan.taskButtonFrames[0]
        let f1 = plan.taskButtonFrames[1]
        let f2 = plan.taskButtonFrames[2]
        
        // Slot 0: Dragging to the left of button 0 midX
        #expect(plan.taskInsertionSlot(atX: f0.minX - 20) == 0)
        #expect(plan.taskInsertionSlot(atX: f0.midX - 1) == 0)
        
        // Slot 1: Dragging between button 0 midX and button 1 midX
        #expect(plan.taskInsertionSlot(atX: f0.midX + 1) == 1)
        #expect(plan.taskInsertionSlot(atX: f1.midX - 1) == 1)
        
        // Slot 2: Dragging between button 1 midX and button 2 midX
        #expect(plan.taskInsertionSlot(atX: f1.midX + 1) == 2)
        #expect(plan.taskInsertionSlot(atX: f2.midX - 1) == 2)
        
        // Slot 3: Dragging beyond button 2 midX
        #expect(plan.taskInsertionSlot(atX: f2.midX + 1) == 3)
        #expect(plan.taskInsertionSlot(atX: f2.maxX + 50) == 3)
    }
    
    @Test("Pinned insertion slot calculation")
    func testPinnedInsertionSlotCalculation() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 1000, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 2,
            taskItemCount: 0,
            pinnedButtonSpacing: 4
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        #expect(plan.pinnedButtonFrames.count == 2)
        
        let p0 = plan.pinnedButtonFrames[0]
        let p1 = plan.pinnedButtonFrames[1]
        
        // Slot 0: Left of p0 midX
        #expect(plan.pinnedInsertionSlot(atX: p0.minX - 10) == 0)
        #expect(plan.pinnedInsertionSlot(atX: p0.midX - 0.5) == 0)
        
        // Slot 1: Between p0 midX and p1 midX
        #expect(plan.pinnedInsertionSlot(atX: p0.midX + 0.5) == 1)
        #expect(plan.pinnedInsertionSlot(atX: p1.midX - 0.5) == 1)
        
        // Slot 2: Right of p1 midX
        #expect(plan.pinnedInsertionSlot(atX: p1.midX + 0.5) == 2)
        #expect(plan.pinnedInsertionSlot(atX: p1.maxX + 20) == 2)
    }
    
    @Test("Task insertion indicator X positions")
    func testTaskInsertionIndicatorXPositions() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 1000, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 0,
            taskItemCount: 3,
            minButtonWidth: 100,
            maxButtonWidth: 100,
            buttonSpacing: 4
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        let f0 = plan.taskButtonFrames[0]
        let f1 = plan.taskButtonFrames[1]
        let f2 = plan.taskButtonFrames[2]
        
        // Slot 0: Left of first button
        let ind0 = plan.taskInsertionIndicatorX(forSlot: 0, buttonSpacing: 4)
        #expect(ind0 != nil)
        if let ind0 {
            #expect(abs(ind0 - (f0.minX - 2.0)) < 0.001)
        }
        
        // Slot 1: Between button 0 and button 1
        let ind1 = plan.taskInsertionIndicatorX(forSlot: 1, buttonSpacing: 4)
        #expect(ind1 != nil)
        if let ind1 {
            #expect(abs(ind1 - ((f0.maxX + f1.minX) / 2.0)) < 0.001)
        }
        
        // Slot 2: Between button 1 and button 2
        let ind2 = plan.taskInsertionIndicatorX(forSlot: 2, buttonSpacing: 4)
        #expect(ind2 != nil)
        if let ind2 {
            #expect(abs(ind2 - ((f1.maxX + f2.minX) / 2.0)) < 0.001)
        }
        
        // Slot 3: Right of last button
        let ind3 = plan.taskInsertionIndicatorX(forSlot: 3, buttonSpacing: 4)
        #expect(ind3 != nil)
        if let ind3 {
            #expect(abs(ind3 - (f2.maxX + 2.0)) < 0.001)
        }
        
        // Clamping check: Slot -5 clamps to 0; Slot 99 clamps to 3
        #expect(plan.taskInsertionIndicatorX(forSlot: -5, buttonSpacing: 4) == ind0)
        #expect(plan.taskInsertionIndicatorX(forSlot: 99, buttonSpacing: 4) == ind3)
    }
    
    @Test("Pinned insertion indicator X positions")
    func testPinnedInsertionIndicatorXPositions() {
        let params = TaskbarLayoutParameters(
            containerSize: CGSize(width: 1000, height: 30),
            startButtonWidth: 50,
            pinnedItemCount: 2,
            taskItemCount: 0,
            pinnedButtonSpacing: 6
        )
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        let p0 = plan.pinnedButtonFrames[0]
        let p1 = plan.pinnedButtonFrames[1]
        
        // Slot 0: Left of p0
        let ind0 = plan.pinnedInsertionIndicatorX(forSlot: 0, pinnedSpacing: 6)
        #expect(ind0 != nil)
        if let ind0 {
            #expect(abs(ind0 - (p0.minX - 3.0)) < 0.001)
        }
        
        // Slot 1: Between p0 and p1
        let ind1 = plan.pinnedInsertionIndicatorX(forSlot: 1, pinnedSpacing: 6)
        #expect(ind1 != nil)
        if let ind1 {
            #expect(abs(ind1 - ((p0.maxX + p1.minX) / 2.0)) < 0.001)
        }
        
        // Slot 2: Right of p1
        let ind2 = plan.pinnedInsertionIndicatorX(forSlot: 2, pinnedSpacing: 6)
        #expect(ind2 != nil)
        if let ind2 {
            #expect(abs(ind2 - (p1.maxX + 3.0)) < 0.001)
        }
    }
    
    @Test("Empty frames indicator returns nil")
    func testEmptyFramesIndicatorReturnsNil() {
        let emptyPlan = TaskbarLayoutEngine.computeLayout(
            params: TaskbarLayoutParameters(
                containerSize: CGSize(width: 800, height: 30),
                startButtonWidth: 50,
                pinnedItemCount: 0,
                taskItemCount: 0
            )
        )
        #expect(emptyPlan.taskInsertionSlot(atX: 100) == 0)
        #expect(emptyPlan.pinnedInsertionSlot(atX: 100) == 0)
        #expect(emptyPlan.taskInsertionIndicatorX(forSlot: 0) == nil)
        #expect(emptyPlan.pinnedInsertionIndicatorX(forSlot: 0) == nil)
    }
}
