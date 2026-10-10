// Tests/TaskbarCoreTests/AutoHideStateMachineTests.swift

import XCTest
@testable import TaskbarCore

final class AutoHideStateMachineTests: XCTestCase {
    
    // MARK: - TC-UNIT-016: AutoHide State Machine Transitions
    
    func testInitialState() {
        let machine = AutoHideStateMachine()
        XCTAssertEqual(machine.state, .visible)
        XCTAssertFalse(machine.isAutoHideEnabled)
        XCTAssertFalse(machine.isMouseInside)
        XCTAssertFalse(machine.isPopupActive)
        XCTAssertFalse(machine.isDragActive)
        XCTAssertTrue(machine.shouldStayVisible)
    }
    
    func testEnablingAutoHideTriggersHiding() {
        var machine = AutoHideStateMachine(initialState: .visible, isAutoHideEnabled: false)
        
        // Enabling auto-hide with mouse outside should trigger transition to .hiding
        let transition = machine.setAutoHideEnabled(true)
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.fromState, .visible)
        XCTAssertEqual(transition?.toState, .hiding)
        XCTAssertTrue(transition?.animated ?? false)
        XCTAssertEqual(machine.state, .hiding)
        
        // Completing animation should transition to .hidden
        let completion = machine.onAnimationCompleted()
        XCTAssertNotNil(completion)
        XCTAssertEqual(completion?.fromState, .hiding)
        XCTAssertEqual(completion?.toState, .hidden)
        XCTAssertEqual(machine.state, .hidden)
    }
    
    func testMouseHoverLifecycle() {
        var machine = AutoHideStateMachine(initialState: .hidden, isAutoHideEnabled: true)
        
        // Mouse enter from hidden -> revealing
        let revealTransition = machine.onMouseEntered()
        XCTAssertNotNil(revealTransition)
        XCTAssertEqual(revealTransition?.fromState, .hidden)
        XCTAssertEqual(revealTransition?.toState, .revealing)
        XCTAssertEqual(machine.state, .revealing)
        XCTAssertTrue(machine.isMouseInside)
        
        // Animation completes -> visible
        let visibleTransition = machine.onAnimationCompleted()
        XCTAssertNotNil(visibleTransition)
        XCTAssertEqual(visibleTransition?.fromState, .revealing)
        XCTAssertEqual(visibleTransition?.toState, .visible)
        XCTAssertEqual(machine.state, .visible)
        
        // Mouse exit -> hiding
        let hideTransition = machine.onMouseExited()
        XCTAssertNotNil(hideTransition)
        XCTAssertEqual(hideTransition?.fromState, .visible)
        XCTAssertEqual(hideTransition?.toState, .hiding)
        XCTAssertEqual(machine.state, .hiding)
        XCTAssertFalse(machine.isMouseInside)
        
        // Animation completes -> hidden
        let hiddenTransition = machine.onAnimationCompleted()
        XCTAssertNotNil(hiddenTransition)
        XCTAssertEqual(hiddenTransition?.fromState, .hiding)
        XCTAssertEqual(hiddenTransition?.toState, .hidden)
        XCTAssertEqual(machine.state, .hidden)
    }
    
    func testPopupLockPreventsHiding() {
        var machine = AutoHideStateMachine(initialState: .visible, isAutoHideEnabled: true)
        
        // Present popup
        let popupTrans = machine.onPopupPresented()
        XCTAssertNil(popupTrans) // Already visible
        XCTAssertTrue(machine.isPopupActive)
        XCTAssertTrue(machine.shouldStayVisible)
        
        // Mouse exits while popup is active -> MUST NOT hide!
        let exitTrans = machine.onMouseExited()
        XCTAssertNil(exitTrans)
        XCTAssertEqual(machine.state, .visible)
        
        // Dismiss popup while mouse is outside -> triggers hiding
        let dismissTrans = machine.onPopupDismissed()
        XCTAssertNotNil(dismissTrans)
        XCTAssertEqual(dismissTrans?.fromState, .visible)
        XCTAssertEqual(dismissTrans?.toState, .hiding)
        XCTAssertEqual(machine.state, .hiding)
    }
    
    func testDragLockPreventsHiding() {
        var machine = AutoHideStateMachine(initialState: .visible, isAutoHideEnabled: true)
        
        // Start dragging
        machine.onDragStarted()
        XCTAssertTrue(machine.isDragActive)
        XCTAssertTrue(machine.shouldStayVisible)
        
        // Mouse exits taskbar bounds while dragging -> MUST NOT hide!
        let exitTrans = machine.onMouseExited()
        XCTAssertNil(exitTrans)
        XCTAssertEqual(machine.state, .visible)
        
        // End drag -> triggers hiding
        let endDragTrans = machine.onDragEnded()
        XCTAssertNotNil(endDragTrans)
        XCTAssertEqual(endDragTrans?.fromState, .visible)
        XCTAssertEqual(endDragTrans?.toState, .hiding)
        XCTAssertEqual(machine.state, .hiding)
    }
    
    func testPopupFromHiddenRevealsBar() {
        var machine = AutoHideStateMachine(initialState: .hidden, isAutoHideEnabled: true)
        
        let trans = machine.onPopupPresented()
        XCTAssertNotNil(trans)
        XCTAssertEqual(trans?.fromState, .hidden)
        XCTAssertEqual(trans?.toState, .revealing)
        XCTAssertEqual(machine.state, .revealing)
    }
    
    func testDragFromHiddenRevealsBar() {
        var machine = AutoHideStateMachine(initialState: .hidden, isAutoHideEnabled: true)
        
        let trans = machine.onDragStarted()
        XCTAssertNotNil(trans)
        XCTAssertEqual(trans?.fromState, .hidden)
        XCTAssertEqual(trans?.toState, .revealing)
        XCTAssertEqual(machine.state, .revealing)
    }
    
    func testDisablingAutoHideForcesVisible() {
        var machine = AutoHideStateMachine(initialState: .hidden, isAutoHideEnabled: true)
        
        let trans = machine.setAutoHideEnabled(false)
        XCTAssertNotNil(trans)
        XCTAssertEqual(trans?.fromState, .hidden)
        XCTAssertEqual(trans?.toState, .visible)
        XCTAssertEqual(machine.state, .visible)
        XCTAssertFalse(machine.isAutoHideEnabled)
    }
}
