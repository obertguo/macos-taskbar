// Tests/TaskbarIntegrationTests/WorkAreaEnforcerTests.swift

import Foundation
import Testing
import CoreGraphics
import ApplicationServices
import TaskbarCore
@testable import TaskbarKit

private final class TestBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { self._value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
    func mutate(_ block: (inout T) -> Void) {
        lock.withLock { block(&_value) }
    }
}

@Suite("WorkAreaEnforcer Integration Suite", .serialized)
struct WorkAreaEnforcerTests {
    
    private func makeScreenDescriptor() -> ScreenDescriptor {
        ScreenDescriptor(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isPrimary: true
        )
    }
    
    // MARK: - 1. Drag-Event Timer Coalescing
    
    @Test("Verify rapid drag events coalesce into single per-window timer progressing through passes")
    func testDragEventTimerCoalescing() {
        let clock = TestClock(initialTime: 100.0)
        let scheduler = TestScheduler(initialTime: 100.0)
        AppEnvironment.current = AppEnvironment(clock: clock, scheduler: scheduler)
        defer { AppEnvironment.reset() }
        
        let enforcer = WorkAreaEnforcer.shared
        enforcer.resetForTesting()
        defer { enforcer.resetForTesting() }
        
        let screen = makeScreenDescriptor()
        enforcer.configure(isEnabled: true, barHeight: 30.0, screens: [screen])
        
        let dummyElement = AXUIElementCreateSystemWide()
        let winID: UInt64 = 1001
        let pid: pid_t = 2001
        
        let currentFrame = TestBox(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        enforcer.frameResolver = { _ in currentFrame.value }
        
        let clampEvaluatedCount = TestBox(0)
        enforcer.onClampEvaluated = { _, _ in
            clampEvaluatedCount.mutate { $0 += 1 }
        }
        
        let passesExecuted = TestBox<[Int]>([])
        enforcer.onPassExecuted = { id, pass in
            if id == winID {
                passesExecuted.mutate { $0.append(pass) }
            }
        }
        
        // Rapid drag burst: 10 notifications across 50ms
        for i in 1...10 {
            clock.advance(by: 0.005)
            scheduler.advance(by: 0.005)
            currentFrame.mutate { $0.origin.y = CGFloat(i) }
            enforcer.handleWindowMovedOrResized(
                element: dummyElement,
                pid: pid,
                isResize: true,
                winID: winID
            )
            #expect(enforcer.activeTimersCount == 1, "Only 1 timer must be active during rapid dragging")
        }
        
        #expect(enforcer.generationCount(for: winID) == 10)
        #expect(passesExecuted.value.isEmpty, "No passes executed before debounce delay completes")
        
        // Pass 0 fires after 0.100s
        clock.advance(by: 0.100)
        scheduler.advance(by: 0.100)
        #expect(passesExecuted.value == [0], "Pass 0 must execute")
        #expect(enforcer.activeTimersCount == 1, "Pass 1 timer must be active")
        
        // Pass 1 fires after 0.120s
        clock.advance(by: 0.120)
        scheduler.advance(by: 0.120)
        #expect(passesExecuted.value == [0, 1], "Pass 1 must execute")
        #expect(enforcer.activeTimersCount == 1, "Pass 2 timer must be active")
        
        // Pass 2 fires after 0.280s
        clock.advance(by: 0.280)
        scheduler.advance(by: 0.280)
        #expect(passesExecuted.value == [0, 1, 2], "Pass 2 must execute")
        #expect(enforcer.activeTimersCount == 0, "Timer must be cleaned up after Pass 2")
    }
    
    // MARK: - 2. Self-Nudge Suppression
    
    @Test("Verify self-nudge notifications within 500ms are suppressed")
    func testSelfNudgeSuppression() {
        let clock = TestClock(initialTime: 500.0)
        let scheduler = TestScheduler(initialTime: 500.0)
        AppEnvironment.current = AppEnvironment(clock: clock, scheduler: scheduler)
        defer { AppEnvironment.reset() }
        
        let enforcer = WorkAreaEnforcer.shared
        enforcer.resetForTesting()
        defer { enforcer.resetForTesting() }
        
        let screen = makeScreenDescriptor()
        enforcer.configure(isEnabled: true, barHeight: 30.0, screens: [screen])
        
        let dummyElement = AXUIElementCreateSystemWide()
        let winID: UInt64 = 1002
        let pid: pid_t = 2002
        
        // Initial window that extends into taskbar: height 1080 -> clamped to 1050
        let currentFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        enforcer.frameResolver = { _ in currentFrame }
        
        let appliedSizes = TestBox<[CGSize]>([])
        enforcer.setSizeHandler = { _, size in
            appliedSizes.mutate { $0.append(size) }
            return true
        }
        
        // Evaluate clamp directly to simulate programmatic nudge
        enforcer.evaluateAndClamp(element: dummyElement, pid: pid, winID: winID, isResize: true)
        #expect(appliedSizes.value.count == 1)
        #expect(appliedSizes.value.first?.height == 1050.0)
        
        let lastNudge = enforcer.lastSelfNudge(for: winID)
        #expect(lastNudge != nil)
        #expect(lastNudge?.size.height == 1050.0)
        #expect(lastNudge?.timestamp == 500.0)
        
        // Window manager sends resize event 200ms later with the same clamped frame
        clock.advance(by: 0.200)
        scheduler.advance(by: 0.200)
        enforcer.frameResolver = { _ in CGRect(x: 0, y: 0, width: 1920, height: 1050.2) } // Sub-pixel delta
        
        let initialGen = enforcer.generationCount(for: winID)
        enforcer.handleWindowMovedOrResized(
            element: dummyElement,
            pid: pid,
            isResize: true,
            winID: winID
        )
        
        #expect(enforcer.activeTimersCount == 0, "Self-inflicted notification must be ignored without scheduling timer")
        #expect(enforcer.generationCount(for: winID) == initialGen, "Generation must not increment for self-nudge")
        
        // After 501ms (> 500ms window), legitimate event with same size is accepted
        clock.advance(by: 0.350) // Total elapsed: 550ms
        scheduler.advance(by: 0.350)
        
        enforcer.handleWindowMovedOrResized(
            element: dummyElement,
            pid: pid,
            isResize: true,
            winID: winID
        )
        #expect(enforcer.activeTimersCount == 1, "Notification after 500ms window must not be suppressed")
    }
    
    // MARK: - 3. Recursion Guard
    
    @Test("Verify recursion guard blocks nudging after 2 resistant resizes within recursion window")
    func testRecursionGuardBlocksAfterTwoResistantAttempts() {
        let clock = TestClock(initialTime: 1000.0)
        let scheduler = TestScheduler(initialTime: 1000.0)
        AppEnvironment.current = AppEnvironment(clock: clock, scheduler: scheduler)
        defer { AppEnvironment.reset() }
        
        let enforcer = WorkAreaEnforcer.shared
        enforcer.resetForTesting()
        defer { enforcer.resetForTesting() }
        
        let screen = makeScreenDescriptor()
        enforcer.configure(isEnabled: true, barHeight: 30.0, screens: [screen])
        
        let dummyElement = AXUIElementCreateSystemWide()
        let winID: UInt64 = 1003
        let pid: pid_t = 2003
        
        // Window constantly resets to height 1080 (resistant app)
        let resistantFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        enforcer.frameResolver = { _ in resistantFrame }
        
        let setSizeCalls = TestBox(0)
        enforcer.setSizeHandler = { _, _ in
            setSizeCalls.mutate { $0 += 1 }
            return true
        }
        
        // Attempt 1 at t = 1000.0
        enforcer.evaluateAndClamp(element: dummyElement, pid: pid, winID: winID, isResize: true)
        #expect(setSizeCalls.value == 1, "First nudge attempt must be allowed")
        #expect(enforcer.nudgeRecord(for: winID)?.attempts == 1)
        
        // Attempt 2 at t = 1000.2 (200ms < 800ms)
        clock.advance(by: 0.200)
        scheduler.advance(by: 0.200)
        enforcer.evaluateAndClamp(element: dummyElement, pid: pid, winID: winID, isResize: true)
        #expect(setSizeCalls.value == 2, "Second nudge attempt must be allowed")
        #expect(enforcer.nudgeRecord(for: winID)?.attempts == 2)
        
        // Attempt 3 at t = 1000.4 (400ms < 800ms): Must be BLOCKED
        clock.advance(by: 0.200)
        scheduler.advance(by: 0.200)
        enforcer.evaluateAndClamp(element: dummyElement, pid: pid, winID: winID, isResize: true)
        #expect(setSizeCalls.value == 2, "Third nudge attempt within recursion window must be blocked")
        
        // Advance clock past nudgeRecursionWindow (0.8s) -> 1.0s elapsed
        clock.advance(by: 1.0)
        scheduler.advance(by: 1.0)
        enforcer.evaluateAndClamp(element: dummyElement, pid: pid, winID: winID, isResize: true)
        #expect(setSizeCalls.value == 3, "Nudge attempt after recursion window expires must be permitted")
        #expect(enforcer.nudgeRecord(for: winID)?.attempts == 1)
    }
    
    // MARK: - 4. Active Mouse-Down Deferral & Generation Gating
    
    @Test("Verify mouse-down deferral gates retries on generation and discards stale retry on new move")
    func testMouseDownDeferralAndGenerationGating() {
        let clock = TestClock(initialTime: 2000.0)
        let scheduler = TestScheduler(initialTime: 2000.0)
        AppEnvironment.current = AppEnvironment(clock: clock, scheduler: scheduler)
        defer { AppEnvironment.reset() }
        
        let enforcer = WorkAreaEnforcer.shared
        enforcer.resetForTesting()
        defer { enforcer.resetForTesting() }
        
        let screen = makeScreenDescriptor()
        enforcer.configure(isEnabled: true, barHeight: 30.0, screens: [screen])
        
        let dummyElement = AXUIElementCreateSystemWide()
        let winID: UInt64 = 1004
        let pid: pid_t = 2004
        
        let currentFrame = TestBox(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        enforcer.frameResolver = { _ in currentFrame.value }
        
        let isMouseDownState = TestBox(true)
        enforcer.isLeftMouseDown = { isMouseDownState.value }
        
        let evaluatedClamps = TestBox<[CGRect]>([])
        enforcer.onClampEvaluated = { _, frame in
            evaluatedClamps.mutate { $0.append(frame) }
        }
        
        // First move event schedules debounce timer
        enforcer.handleWindowMovedOrResized(element: dummyElement, pid: pid, isResize: true, winID: winID)
        #expect(enforcer.generationCount(for: winID) == 1)
        
        // Debounce expires (Pass 0 fires): evaluateAndClamp sees mouse is down
        clock.advance(by: 0.100)
        scheduler.advance(by: 0.100)
        #expect(enforcer.mouseDownRetryTimersCount == 1, "Must schedule mouse-down retry timer")
        #expect(evaluatedClamps.value.isEmpty, "Clamp must be deferred while mouse is down")
        
        // User continues dragging: New move event increments generation to 2
        clock.advance(by: 0.050)
        scheduler.advance(by: 0.050)
        currentFrame.mutate { $0.origin.y = 50.0 }
        enforcer.handleWindowMovedOrResized(element: dummyElement, pid: pid, isResize: true, winID: winID)
        #expect(enforcer.generationCount(for: winID) == 2)
        #expect(enforcer.mouseDownRetryTimersCount == 0, "Old retry timer was cancelled on new move")
        
        // Mouse is released
        isMouseDownState.value = false
        
        // Advance so generation 2's Pass 0 fires (0.100s after generation 2 arrived): mouse is up, clamp succeeds
        clock.advance(by: 0.100)
        scheduler.advance(by: 0.100)
        #expect(evaluatedClamps.value.count == 1, "Current generation clamp must succeed after mouse release")
    }
    
    // MARK: - 5. State Cleanup (removeWindow & removeApp)
    
    @Test("Verify removeWindow and removeApp clean up all timers, records, and PID associations")
    func testStateCleanup() {
        let clock = TestClock(initialTime: 3000.0)
        let scheduler = TestScheduler(initialTime: 3000.0)
        AppEnvironment.current = AppEnvironment(clock: clock, scheduler: scheduler)
        defer { AppEnvironment.reset() }
        
        let enforcer = WorkAreaEnforcer.shared
        enforcer.resetForTesting()
        defer { enforcer.resetForTesting() }
        
        let screen = makeScreenDescriptor()
        enforcer.configure(isEnabled: true, barHeight: 30.0, screens: [screen])
        
        let dummyElement = AXUIElementCreateSystemWide()
        enforcer.frameResolver = { _ in CGRect(x: 0, y: 0, width: 1920, height: 1080) }
        
        let win1: UInt64 = 5001
        let win2: UInt64 = 5002
        let app1PID: pid_t = 6001
        
        let win3: UInt64 = 5003
        let app2PID: pid_t = 6002
        
        // Start timers on win1, win2 (app1) and win3 (app2)
        enforcer.handleWindowMovedOrResized(element: dummyElement, pid: app1PID, isResize: true, winID: win1)
        enforcer.handleWindowMovedOrResized(element: dummyElement, pid: app1PID, isResize: true, winID: win2)
        enforcer.handleWindowMovedOrResized(element: dummyElement, pid: app2PID, isResize: true, winID: win3)
        
        #expect(enforcer.activeTimersCount == 3)
        #expect(enforcer.isWindowTracked(winID: win1))
        #expect(enforcer.isWindowTracked(winID: win2))
        #expect(enforcer.isWindowTracked(winID: win3))
        
        // 1. removeWindow on win1
        enforcer.removeWindow(winID: win1)
        #expect(!enforcer.isWindowTracked(winID: win1), "win1 must be completely untracked")
        #expect(enforcer.activeTimersCount == 2, "win1's timer must be cancelled")
        #expect(enforcer.isWindowTracked(winID: win2), "win2 must remain intact")
        #expect(enforcer.isWindowTracked(winID: win3), "win3 must remain intact")
        
        // Also verify removeWindow(WindowKey)
        let key2 = WindowKey(id: win2, pid: app1PID)
        enforcer.removeWindow(key2)
        #expect(!enforcer.isWindowTracked(winID: win2), "win2 must be cleaned up via WindowKey")
        #expect(enforcer.activeTimersCount == 1)
        
        // 2. removeApp on app2PID
        enforcer.removeApp(pid: app2PID)
        #expect(!enforcer.isWindowTracked(winID: win3), "win3 must be cleaned up via removeApp")
        #expect(enforcer.activeTimersCount == 0, "All timers must be cleared")
    }
    
    // MARK: - 6. Position and Size Enforcement
    
    @Test("Verify position and size adjustments are applied when clamping requires them")
    func testPositionAndSizeEnforcement() {
        let clock = TestClock(initialTime: 4000.0)
        let scheduler = TestScheduler(initialTime: 4000.0)
        AppEnvironment.current = AppEnvironment(clock: clock, scheduler: scheduler)
        defer { AppEnvironment.reset() }
        
        let enforcer = WorkAreaEnforcer.shared
        enforcer.resetForTesting()
        defer { enforcer.resetForTesting() }
        
        let screen = makeScreenDescriptor()
        enforcer.configure(isEnabled: true, barHeight: 30.0, screens: [screen])
        
        let dummyElement = AXUIElementCreateSystemWide()
        let winID: UInt64 = 7001
        let pid: pid_t = 8001
        
        // Window extends into taskbar: height 1080 -> 1050
        enforcer.frameResolver = { _ in CGRect(x: 100, y: 0, width: 800, height: 1080) }
        
        let appliedPositions = TestBox<[CGPoint]>([])
        let appliedSizes = TestBox<[CGSize]>([])
        enforcer.setPositionHandler = { _, pos in
            appliedPositions.mutate { $0.append(pos) }
            return true
        }
        enforcer.setSizeHandler = { _, size in
            appliedSizes.mutate { $0.append(size) }
            return true
        }
        
        enforcer.evaluateAndClamp(element: dummyElement, pid: pid, winID: winID, isResize: true)
        
        // Bottom-anchored taskbar: origin does not change, size changes from 1080 to 1050
        #expect(appliedPositions.value.isEmpty, "Origin should not change for bottom taskbar clamp")
        #expect(appliedSizes.value.count == 1)
        #expect(appliedSizes.value.first?.height == 1050.0)
        #expect(appliedSizes.value.first?.width == 800.0)
    }
}
