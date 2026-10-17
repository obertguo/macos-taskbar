// Tests/TaskbarIntegrationTests/AppEnvironmentTests.swift

import Foundation
import Testing
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

@Suite("AppEnvironment and DI Service Suite", .serialized)
struct AppEnvironmentTests {
    
    // MARK: - Clocks
    
    @Test("System uptime clock returns uptime")
    func testSystemUptimeClockReturnsUptime() {
        let clock = SystemUptimeClock()
        let t1 = clock.now()
        #expect(t1 > 0)
    }
    
    @Test("Test clock advancement and setting")
    func testTestClockAdvancementAndSetting() {
        let clock = TestClock(initialTime: 100.0)
        #expect(clock.now() == 100.0)
        
        clock.advance(by: 5.5)
        #expect(clock.now() == 105.5)
        
        clock.advance(2.0)
        #expect(clock.now() == 107.5)
        
        clock.setTime(200.0)
        #expect(clock.now() == 200.0)
        
        clock.setTime(time: 300.0)
        #expect(clock.now() == 300.0)
    }
    
    @Test("Test clock thread safety")
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
        #expect(clock.now() == 100.0)
    }
    
    // MARK: - Cancellable
    
    @Test("AnyCancellable cancels only once")
    func testAnyCancellableCancelsOnlyOnce() {
        let countBox = Box(0)
        let cancellable = AnyCancellable {
            countBox.modify { $0 += 1 }
        }
        
        cancellable.cancel()
        cancellable.cancel()
        cancellable.cancel()
        
        #expect(countBox.current == 1)
    }
    
    // MARK: - Schedulers
    
    @Test("Test scheduler execution order and advancement")
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
        
        #expect(scheduler.pendingCount == 4)
        
        scheduler.advance(by: 4.0)
        #expect(logBox.current.isEmpty)
        
        scheduler.advance(by: 1.0) // time is now 5.0
        #expect(logBox.current == ["B:5", "C:5"])
        
        scheduler.advance(by: 10.0) // time is now 15.0
        #expect(logBox.current == ["B:5", "C:5", "A:10"])
        
        scheduler.runAllPending() // runs D:20
        #expect(logBox.current == ["B:5", "C:5", "A:10", "D:20"])
        #expect(scheduler.pendingCount == 0)
    }
    
    @Test("Test scheduler cancellation")
    func testTestSchedulerCancellation() {
        let scheduler = TestScheduler(initialTime: 0)
        let executedBox = Box(false)
        
        let cancellable = scheduler.schedule(after: 5.0) {
            executedBox.modify { $0 = true }
        }
        
        #expect(scheduler.pendingCount == 1)
        cancellable.cancel()
        #expect(scheduler.pendingCount == 0)
        
        scheduler.advance(by: 10.0)
        #expect(!executedBox.current)
    }
    
    @Test("MainScheduler execution and cancellation")
    func testMainSchedulerExecutionAndCancellation() async {
        let scheduler = MainScheduler()
        let executedBox = Box(false)
        let cancelledBox = Box(false)
        
        let cancellable = scheduler.schedule(after: 0.05) {
            cancelledBox.modify { $0 = true }
        }
        cancellable.cancel()
        
        await withCheckedContinuation { continuation in
            scheduler.schedule(after: 0.01) {
                executedBox.modify { $0 = true }
                continuation.resume()
            }
        }
        
        try? await Task.sleep(nanoseconds: 60_000_000)
        
        #expect(executedBox.current)
        #expect(!cancelledBox.current)
    }
    
    @Test("AXThreadScheduler execution and cancellation")
    func testAXThreadSchedulerExecutionAndCancellation() async {
        let scheduler = AXThreadScheduler()
        let executedBox = Box(false)
        let cancelledBox = Box(false)
        
        let cancellable = scheduler.schedule(after: 0.05) {
            cancelledBox.modify { $0 = true }
        }
        cancellable.cancel()
        
        await withCheckedContinuation { continuation in
            scheduler.schedule(after: 0.01) {
                executedBox.modify { $0 = true }
                continuation.resume()
            }
        }
        
        try? await Task.sleep(nanoseconds: 60_000_000)
        
        #expect(executedBox.current)
        #expect(!cancelledBox.current)
    }
    
    // MARK: - WindowActionPerforming & SpyWindowActions
    
    @Test("SpyWindowActions records all invocations")
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
        #expect(invocations.count == 8)
        
        #expect(invocations[0] == .performAction(action: .focus, key: key))
        #expect(invocations[1] == .focusWindow(key: key))
        #expect(invocations[2] == .minimizeWindow(key: key))
        #expect(invocations[3] == .restoreAndFocusWindow(key: key))
        #expect(invocations[4] == .closeWindow(key: key))
        #expect(invocations[5] == .quitApplicationPID(pid: 1234))
        #expect(invocations[6] == .quitApplicationBundleID(bundleIdentifier: "com.apple.finder"))
        
        if case .launchOrActivateApp(let bundleID, let path, let store) = invocations[7] {
            #expect(bundleID == "com.apple.calculator")
            #expect(path == "/App.app")
            #expect(store != nil)
        } else {
            Issue.record("Expected launchOrActivateApp invocation")
        }
        
        spy.clear()
        #expect(spy.invocations.isEmpty)
    }
    
    // MARK: - DockServicing & MockDockService
    
    @Test("MockDockService tracking")
    func testMockDockServiceTracking() {
        let mockDock = MockDockService()
        #expect(!mockDock.isDockHidden)
        #expect(mockDock.currentAppliedDelay == nil)
        #expect(mockDock.hideDockCallCount == 0)
        #expect(mockDock.restoreDockCallCount == 0)
        
        mockDock.hideDock(delay: 500.0)
        #expect(mockDock.isDockHidden)
        #expect(mockDock.currentAppliedDelay == 500.0)
        #expect(mockDock.hideDockCallCount == 1)
        
        mockDock.restoreDock()
        #expect(!mockDock.isDockHidden)
        #expect(mockDock.currentAppliedDelay == nil)
        #expect(mockDock.restoreDockCallCount == 1)
        
        mockDock.reset()
        #expect(mockDock.hideDockCallCount == 0)
        #expect(mockDock.restoreDockCallCount == 0)
    }
    
    // MARK: - AppEnvironment
    
    @Test("AppEnvironment live defaults")
    func testAppEnvironmentLiveDefaults() {
        let env = AppEnvironment.live
        #expect(env.clock is SystemUptimeClock)
        #expect(env.scheduler is AXThreadScheduler)
        #expect(env.windowActions is LiveWindowActions)
        #expect(env.dockService is LiveDockService)
    }
    
    @Test("AppEnvironment current mutation and reset")
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
        
        #expect(AppEnvironment.current.clock.now() == 50.0)
        #expect(AppEnvironment.current.scheduler is TestScheduler)
        #expect(AppEnvironment.current.windowActions is SpyWindowActions)
        #expect(AppEnvironment.current.dockService is MockDockService)
        
        AppEnvironment.reset()
        #expect(AppEnvironment.current.clock is SystemUptimeClock)
    }
    
    // MARK: - WorkAreaEnforcer Disabled in Tests
    
    @Test("WorkAreaEnforcer is disabled by default in tests")
    func testWorkAreaEnforcerIsDisabledByDefaultInTests() {
        #expect(!WorkAreaEnforcer.shared.isEnabled, "WorkAreaEnforcer must default to disabled during test execution")
    }
    
    // MARK: - WindowSource Conformance
    
    @Test("AppTracker conforms to WindowSource")
    @MainActor
    func testAppTrackerConformsToWindowSource() {
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        let source: any WindowSource = tracker
        
        #expect(source.store === store)
        source.stopTracking()
    }
}
