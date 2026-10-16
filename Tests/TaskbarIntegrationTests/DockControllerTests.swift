// Tests/TaskbarIntegrationTests/DockControllerTests.swift

import Foundation
import Testing
import CoreFoundation
import TaskbarCore
@testable import TaskbarKit

private final class TestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var value: Int { lock.withLock { _count } }
    func increment() { lock.withLock { _count += 1 } }
}

@Suite("DockController Resilience Suite", .serialized)
struct DockControllerTests {
    private let testDomain = "com.taskbar.test.dock"
    
    init() {
        cleanTestState()
    }
    
    private func cleanTestState() {
        UserDefaults.standard.removeObject(forKey: DockController.originalStateKey)
        UserDefaults.standard.removeObject(forKey: DockController.sentinelKey)
        UserDefaults.standard.synchronize()
        
        DockController.preferencesDomain = testDomain
        DockController.dockRestartHandler = nil
        DockController.shared.resetStateForTesting()
        
        // Clear test domain preferences
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideKey as CFString,
            nil,
            testDomain as CFString
        )
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideDelayKey as CFString,
            nil,
            testDomain as CFString
        )
        CFPreferencesAppSynchronize(testDomain as CFString)
    }
    
    @Test("TC-DOCK-001: Crash recovery restores baseline and clears sentinel when user wants dock visible")
    func testCrashRecoveryRestoreWhenUserWantsDockVisible() throws {
        cleanTestState()
        defer { cleanTestState() }
        
        let restartCount = TestCounter()
        DockController.dockRestartHandler = {
            restartCount.increment()
        }
        
        // 1. Simulate an unclean exit by setting sentinel and writing mock baseline preferences
        let mockBaseline = DockController.SavedDockState(autohide: true, autohideDelay: 1.5)
        let mockData = try JSONEncoder().encode(mockBaseline)
        UserDefaults.standard.set(mockData, forKey: DockController.originalStateKey)
        UserDefaults.standard.set(true, forKey: DockController.sentinelKey)
        UserDefaults.standard.synchronize()
        
        #expect(UserDefaults.standard.bool(forKey: DockController.sentinelKey) == true)
        
        // 2. Call reconcileOnLaunch(shouldHideDock: false)
        DockController.shared.reconcileOnLaunch(shouldHideDock: false)
        DockController.shared.waitForQueue()
        
        // 3. Verify sentinel is cleared
        let sentinelAfter = UserDefaults.standard.bool(forKey: DockController.sentinelKey)
        #expect(sentinelAfter == false, "Sentinel must be cleared after crash recovery when shouldHideDock is false")
        
        // 4. Verify baseline state was restored into preferences
        #expect(DockController.shared.isDockHidden == false)
        let autohideRestored = DockController.querySystemAutohide()
        let delayRestored = DockController.querySystemAutohideDelay()
        #expect(autohideRestored == true, "Autohide should match mock baseline")
        #expect(delayRestored == 1.5, "Autohide delay should match mock baseline")
        #expect(restartCount.value == 1, "Dock restart handler should have been triggered once")
    }
    
    @Test("TC-DOCK-002: Crash recovery preserves original baseline snapshot in UserDefaults when user wants dock hidden")
    func testCrashRecoveryPreservesBaselineWhenUserWantsDockHidden() throws {
        cleanTestState()
        defer { cleanTestState() }
        
        let restartCount = TestCounter()
        DockController.dockRestartHandler = {
            restartCount.increment()
        }
        
        // 1. Simulate an unclean exit with a custom baseline snapshot
        let mockBaseline = DockController.SavedDockState(autohide: false, autohideDelay: 0.5)
        let mockData = try JSONEncoder().encode(mockBaseline)
        UserDefaults.standard.set(mockData, forKey: DockController.originalStateKey)
        UserDefaults.standard.set(true, forKey: DockController.sentinelKey)
        UserDefaults.standard.synchronize()
        
        // 2. Call reconcileOnLaunch(shouldHideDock: true) with a new hide delay
        DockController.shared.reconcileOnLaunch(shouldHideDock: true, delay: 1000.0)
        DockController.shared.waitForQueue()
        
        // 3. Verify original baseline snapshot in UserDefaults is PRESERVED and NOT overwritten
        guard let savedData = UserDefaults.standard.data(forKey: DockController.originalStateKey) else {
            Issue.record("Original state key missing from UserDefaults")
            return
        }
        let savedState = try JSONDecoder().decode(DockController.SavedDockState.self, from: savedData)
        #expect(savedState == mockBaseline, "Baseline state must not be overwritten by crash recovery")
        #expect(savedState.autohideDelay == 0.5, "Saved delay must remain original (0.5s) instead of 1000.0s")
        #expect(savedState.autohide == false, "Saved autohide must remain original false")
        
        // 4. Verify sentinel remains true and dock remains marked as hidden
        let sentinelAfter = UserDefaults.standard.bool(forKey: DockController.sentinelKey)
        #expect(sentinelAfter == true, "Sentinel must remain active while dock is overridden")
        #expect(DockController.shared.isDockHidden == true)
        
        // 5. Verify the hide settings were applied to preferences
        let currentAutohide = DockController.querySystemAutohide()
        let currentDelay = DockController.querySystemAutohideDelay()
        #expect(currentAutohide == true)
        #expect(currentDelay == 1000.0)
        #expect(restartCount.value == 1)
    }
    
    @Test("TC-DOCK-003: In-process preference reading returns values without spawning defaults processes")
    func testInProcessPreferenceReading() {
        cleanTestState()
        defer { cleanTestState() }
        
        // Test in custom domain
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideKey as CFString,
            kCFBooleanTrue,
            testDomain as CFString
        )
        let customDelay = NSNumber(value: 2.75)
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideDelayKey as CFString,
            customDelay,
            testDomain as CFString
        )
        CFPreferencesAppSynchronize(testDomain as CFString)
        
        let autohide = DockController.querySystemAutohide()
        let delay = DockController.querySystemAutohideDelay()
        
        #expect(autohide == true, "In-process read must return true for autohide")
        #expect(delay == 2.75, "In-process read must return 2.75 for autohide-delay")
        
        // Test removing key returns nil
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideDelayKey as CFString,
            nil,
            testDomain as CFString
        )
        CFPreferencesAppSynchronize(testDomain as CFString)
        
        let nilDelay = DockController.querySystemAutohideDelay()
        #expect(nilDelay == nil, "In-process read must return nil when autohide-delay is unset")
        
        // Test in-process reading from actual com.apple.dock domain executes instantaneously
        DockController.preferencesDomain = TaskbarConstants.Dock.domain
        let _ = DockController.querySystemAutohide()
        let _ = DockController.querySystemAutohideDelay()
    }
    
    @Test("TC-DOCK-004: Clean launch captures original baseline and applies hide state")
    func testCleanLaunchSnapshotsAndHides() throws {
        cleanTestState()
        defer { cleanTestState() }
        
        let restartCount = TestCounter()
        DockController.dockRestartHandler = {
            restartCount.increment()
        }
        
        // Pre-seed test domain preferences with initial user settings
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideKey as CFString,
            kCFBooleanFalse,
            testDomain as CFString
        )
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideDelayKey as CFString,
            NSNumber(value: 0.25),
            testDomain as CFString
        )
        CFPreferencesAppSynchronize(testDomain as CFString)
        
        // Fresh launch without prior sentinel
        DockController.shared.reconcileOnLaunch(shouldHideDock: true, delay: 1000.0)
        DockController.shared.waitForQueue()
        
        // Baseline should have been captured from the domain
        guard let data = UserDefaults.standard.data(forKey: DockController.originalStateKey) else {
            Issue.record("Baseline was not captured on fresh launch")
            return
        }
        let captured = try JSONDecoder().decode(DockController.SavedDockState.self, from: data)
        #expect(captured.autohide == false)
        #expect(captured.autohideDelay == 0.25)
        
        // Sentinel should now be true
        #expect(UserDefaults.standard.bool(forKey: DockController.sentinelKey) == true)
        #expect(DockController.shared.isDockHidden == true)
        #expect(restartCount.value == 1)
    }
    
    @Test("TC-DOCK-005: Synchronous restore via restoreDockSync immediately clears sentinel and restores preferences")
    func testRestoreDockSync() throws {
        cleanTestState()
        defer { cleanTestState() }
        
        let restartCount = TestCounter()
        DockController.dockRestartHandler = {
            restartCount.increment()
        }
        
        let baseline = DockController.SavedDockState(autohide: false, autohideDelay: nil)
        let data = try JSONEncoder().encode(baseline)
        UserDefaults.standard.set(data, forKey: DockController.originalStateKey)
        UserDefaults.standard.set(true, forKey: DockController.sentinelKey)
        UserDefaults.standard.synchronize()
        DockController.shared.resetStateForTesting(isDockHidden: true)
        
        // Call synchronous restore
        DockController.restoreDockSync()
        
        #expect(UserDefaults.standard.bool(forKey: DockController.sentinelKey) == false)
        #expect(DockController.shared.isDockHidden == false)
        #expect(DockController.querySystemAutohide() == false)
        #expect(DockController.querySystemAutohideDelay() == nil)
        #expect(restartCount.value == 1)
    }
}
