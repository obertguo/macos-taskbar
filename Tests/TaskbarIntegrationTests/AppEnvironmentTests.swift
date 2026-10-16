// Tests/TaskbarIntegrationTests/AppEnvironmentTests.swift

import XCTest
import TaskbarCore
@testable import TaskbarKit

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    func modify(_ block: (inout T) -> Void) {
        lock.withLock { block(&value) }
    }
    
    var current: T {
        lock.withLock { value }
    }
}

final class AppEnvironmentTests: XCTestCase {
    
    // MARK: - Clocks
    
    func testSystemUptimeClockReturnsUptime() {
        let clock = SystemUptimeClock()
        let t1 = clock.now()
        XCTAssertGreaterThan(t1, 0)
    }
    
    func testTestClockAdvancementAndSetting() {
        let clock = TestClock(initialTime: 100.0)
        XCTAssertEqual(clock.now(), 100.0)
        
        clock.advance(by: 5.5)
        XCTAssertEqual(clock.now(), 105.5)
        
        clock.advance(2.0)
        XCTAssertEqual(clock.now(), 107.5)
        
        clock.setTime(200.0)
        XCTAssertEqual(clock.now(), 200.0)
        
        clock.setTime(time: 300.0)
        XCTAssertEqual(clock.now(), 300.0)
    }
    
    func testTestClockThreadSafety() {
        let clock = TestClock(initialTime: 0)
        let queue = DispatchQueue(label: "test.clock", attributes: .concurrent)
        let group = DispatchGroup()
        
        for _ in 0..<100 {
            group.enter()
            queue.async {
                clock.advance(by: 1.0)
                _ = clock.now()
                group.leave()
            }
        }
        
        group.wait()
        XCTAssertEqual(clock.now(), 100.0)
    }
    
    // MARK: - Cancellable
    
    func testAnyCancellableCancelsOnlyOnce() {
        let countBox = Box(0)
        let cancellable = AnyCancellable {
            countBox.modify { $0 += 1 }
        }
        
        cancellable.cancel()
        cancellable.cancel()
        cancellable.cancel()
        
        XCTAssertEqual(countBox.current, 1)
    }
    
    // MARK: - Schedulers
    
    func testTestSchedulerExecutionOrderAndAdvancement() {
        let scheduler = TestScheduler(initialTime: 0)
        let logBox = Box<[String]>([])
        
        scheduler.schedule(after: 10.0) {
            logBox.modify { $0.append("A:10") }
        }
        scheduler.schedule(after: 5.0) {
            logBox.modify { $0.append("B:5") }
        }
        scheduler.schedule(after: 5.0) {
            logBox.modify { $0.append("C:5") }
        }
        scheduler.schedule(after: 20.0) {
            logBox.modify { $0.append("D:20") }
        }
        
        XCTAssertEqual(scheduler.pendingCount, 4)
        
        scheduler.advance(by: 4.0)
        XCTAssertTrue(logBox.current.isEmpty)
        
        scheduler.advance(by: 1.0) // time is now 5.0
        XCTAssertEqual(logBox.current, ["B:5", "C:5"])
        
        scheduler.advance(by: 10.0) // time is now 15.0
        XCTAssertEqual(logBox.current, ["B:5", "C:5", "A:10"])
        
        scheduler.runAllPending() // runs D:20
        XCTAssertEqual(logBox.current, ["B:5", "C:5", "A:10", "D:20"])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }
    
    func testTestSchedulerCancellation() {
        let scheduler = TestScheduler(initialTime: 0)
        let executedBox = Box(false)
        
        let cancellable = scheduler.schedule(after: 5.0) {
            executedBox.modify { $0 = true }
        }
        
        XCTAssertEqual(scheduler.pendingCount, 1)
        cancellable.cancel()
        XCTAssertEqual(scheduler.pendingCount, 0)
        
        scheduler.advance(by: 10.0)
        XCTAssertFalse(executedBox.current)
    }
    
    func testMainSchedulerExecutionAndCancellation() {
        let scheduler = MainScheduler()
        let exp = expectation(description: "main scheduler executed")
        let executedBox = Box(false)
        
        scheduler.schedule(after: 0.01) {
            executedBox.modify { $0 = true }
            exp.fulfill()
        }
        
        let cancelledBox = Box(false)
        let cancellable = scheduler.schedule(after: 0.05) {
            cancelledBox.modify { $0 = true }
        }
        cancellable.cancel()
        
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(executedBox.current)
        XCTAssertFalse(cancelledBox.current)
    }
    
    func testAXThreadSchedulerExecutionAndCancellation() {
        let scheduler = AXThreadScheduler()
        let exp = expectation(description: "ax scheduler executed")
        let executedBox = Box(false)
        
        scheduler.schedule(after: 0.01) {
            executedBox.modify { $0 = true }
            exp.fulfill()
        }
        
        let cancelledBox = Box(false)
        let cancellable = scheduler.schedule(after: 0.05) {
            cancelledBox.modify { $0 = true }
        }
        cancellable.cancel()
        
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(executedBox.current)
        XCTAssertFalse(cancelledBox.current)
    }
    
    // MARK: - WindowActionPerforming & SpyWindowActions
    
    func testSpyWindowActionsRecordsAllInvocations() async {
        let spy = SpyWindowActions()
        let key = WindowKey(id: 5678, pid: 1234)
        
        spy.performAction(.focus, for: key)
        spy.focusWindow(key)
        spy.minimizeWindow(key)
        spy.restoreAndFocusWindow(key)
        spy.closeWindow(key)
        spy.quitApplication(pid: 1234)
        spy.quitApplication(bundleIdentifier: "com.apple.finder")
        
        await MainActor.run {
            let store = WindowStore()
            spy.launchOrActivateApp(bundleIdentifier: "com.apple.calculator", customPath: "/App.app", store: store)
        }
        
        let invocations = spy.invocations
        XCTAssertEqual(invocations.count, 8)
        
        XCTAssertEqual(invocations[0], .performAction(action: .focus, key: key))
        XCTAssertEqual(invocations[1], .focusWindow(key: key))
        XCTAssertEqual(invocations[2], .minimizeWindow(key: key))
        XCTAssertEqual(invocations[3], .restoreAndFocusWindow(key: key))
        XCTAssertEqual(invocations[4], .closeWindow(key: key))
        XCTAssertEqual(invocations[5], .quitApplicationPID(pid: 1234))
        XCTAssertEqual(invocations[6], .quitApplicationBundleID(bundleIdentifier: "com.apple.finder"))
        
        if case .launchOrActivateApp(let bundleID, let path, let store) = invocations[7] {
            XCTAssertEqual(bundleID, "com.apple.calculator")
            XCTAssertEqual(path, "/App.app")
            XCTAssertNotNil(store)
        } else {
            XCTFail("Expected launchOrActivateApp invocation")
        }
        
        spy.clear()
        XCTAssertTrue(spy.invocations.isEmpty)
    }
    
    // MARK: - DockServicing & MockDockService
    
    func testMockDockServiceTracking() {
        let mockDock = MockDockService()
        XCTAssertFalse(mockDock.isDockHidden)
        XCTAssertNil(mockDock.currentAppliedDelay)
        XCTAssertEqual(mockDock.hideDockCallCount, 0)
        XCTAssertEqual(mockDock.restoreDockCallCount, 0)
        
        mockDock.hideDock(delay: 500.0)
        XCTAssertTrue(mockDock.isDockHidden)
        XCTAssertEqual(mockDock.currentAppliedDelay, 500.0)
        XCTAssertEqual(mockDock.hideDockCallCount, 1)
        
        mockDock.restoreDock()
        XCTAssertFalse(mockDock.isDockHidden)
        XCTAssertNil(mockDock.currentAppliedDelay)
        XCTAssertEqual(mockDock.restoreDockCallCount, 1)
        
        mockDock.reset()
        XCTAssertEqual(mockDock.hideDockCallCount, 0)
        XCTAssertEqual(mockDock.restoreDockCallCount, 0)
    }
    
    // MARK: - AppEnvironment
    
    func testAppEnvironmentLiveDefaults() {
        let env = AppEnvironment.live
        XCTAssertTrue(env.clock is SystemUptimeClock)
        XCTAssertTrue(env.scheduler is MainScheduler)
        XCTAssertTrue(env.windowActions is LiveWindowActions)
        XCTAssertTrue(env.dockService is LiveDockService)
    }
    
    func testAppEnvironmentCurrentMutationAndReset() {
        let _ = AppEnvironment.current
        defer { AppEnvironment.reset() }
        
        let testClock = TestClock(initialTime: 50.0)
        let testScheduler = TestScheduler()
        let spyActions = SpyWindowActions()
        let mockDock = MockDockService()
        
        AppEnvironment.current = AppEnvironment(
            clock: testClock,
            scheduler: testScheduler,
            windowActions: spyActions,
            dockService: mockDock
        )
        
        XCTAssertEqual(AppEnvironment.current.clock.now(), 50.0)
        XCTAssertTrue(AppEnvironment.current.scheduler is TestScheduler)
        XCTAssertTrue(AppEnvironment.current.windowActions is SpyWindowActions)
        XCTAssertTrue(AppEnvironment.current.dockService is MockDockService)
        
        AppEnvironment.reset()
        XCTAssertTrue(AppEnvironment.current.clock is SystemUptimeClock)
    }
    
    // MARK: - WorkAreaEnforcer Disabled in Tests
    
    func testWorkAreaEnforcerIsDisabledByDefaultInTests() {
        XCTAssertFalse(WorkAreaEnforcer.shared.isEnabled, "WorkAreaEnforcer must default to disabled during test execution")
    }
    
    // MARK: - WindowSource Conformance
    
    @MainActor
    func testAppTrackerConformsToWindowSource() {
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        let source: any WindowSource = tracker
        
        XCTAssertIdentical(source.store, store)
        source.stopTracking()
    }
}
