// Tests/TaskbarIntegrationTests/StressIntegrationTests.swift

import Foundation
import Testing
import AppKit
import CoreGraphics
import TaskbarCore
import TaskbarKit

@Suite("Stress and Capacity Integration Suite")
@MainActor
struct StressIntegrationTests {
    
    @Test("TC-STRESS-001: High density window store burst (100 windows)")
    func testHighDensityWindowBurst() {
        let store = WindowStore()
        
        // Add 100 distinct windows
        for i in 1...100 {
            let pid = pid_t(1000 + i)
            let winKey = WindowKey(id: UInt64(i), pid: pid)
            let win = WindowInfo(
                key: winKey,
                pid: pid,
                appName: "StressApp",
                bundleID: "com.test.stress",
                title: "Stress Window \(i)",
                frame: CGRect(x: 100 + i * 5, y: 100 + i * 5, width: 400, height: 300),
                isMinimized: false
            )
            store.addOrUpdateWindow(win)
        }
        
        #expect(store.totalWindowCount == 100)
        #expect(store.allWindows.count == 100)
        #expect(store.allWindows.first?.key.id == 1)
        #expect(store.allWindows.last?.key.id == 100)
        
        // Remove 50 windows
        for i in 1...50 {
            store.removeWindows(forPID: pid_t(1000 + i))
        }
        
        #expect(store.totalWindowCount == 50)
        #expect(store.allWindows.first?.key.id == 51)
    }
    
    @Test("TC-STRESS-002: TaskbarView overflow button activation under load")
    func testTaskbarViewOverflowUnderLoad() {
        let taskbarView = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight)
        
        // Construct 60 windows exceeding available screen width
        var testWindows: [WindowInfo] = []
        for i in 1...60 {
            let pid = pid_t(2000 + i)
            let winKey = WindowKey(id: UInt64(i), pid: pid)
            testWindows.append(WindowInfo(
                key: winKey,
                pid: pid,
                appName: "TestApp",
                bundleID: "com.test.app",
                title: "Overflow Win \(i)",
                frame: CGRect(x: 50, y: 50, width: 600, height: 400),
                isMinimized: false
            ))
        }
        
        // Frame view to typical monitor width (1440pt)
        taskbarView.frame = CGRect(x: 0, y: 0, width: 1440, height: 38)
        taskbarView.updateWindows(windows: testWindows, focusedKey: nil, frontmostPID: nil)
        
        // Total windows (60) * minWidth (120) = 7200pt > 1440pt
        // Overflow button should be visible
        #expect(taskbarView.overflowButton.isHidden == false, "Overflow chevron must be visible when buttons exceed bar width")
        #expect(taskbarView.overflowCount > 0, "Overflow window count must be greater than zero")
    }
    
    @Test("TC-PERF-001: TaskbarView in-place button recycling under dynamic updates")
    func testButtonRecyclingPreservesViewIdentity() {
        let taskbarView = TaskbarView(theme: .modernHybrid, launcherAction: .spotlight)
        taskbarView.frame = CGRect(x: 0, y: 0, width: 1440, height: 38)
        
        let initialKey = WindowKey(id: 999, pid: 9999)
        let initialWin = WindowInfo(
            key: initialKey,
            pid: 9999,
            appName: "RecycleApp",
            bundleID: "com.test.recycle",
            title: "Original Title",
            frame: CGRect(x: 100, y: 100, width: 500, height: 400),
            isMinimized: false
        )
        
        taskbarView.updateWindows(windows: [initialWin], focusedKey: nil, frontmostPID: nil)
        let initialButton = taskbarView.button(forKey: initialWin.key)
        #expect(initialButton != nil, "TaskButton should be created for initial window")
        
        // Update the same window with a new title and minimized state
        var updatedWin = initialWin
        updatedWin.title = "Recycled Title"
        updatedWin.isMinimized = true
        
        taskbarView.updateWindows(windows: [updatedWin], focusedKey: nil, frontmostPID: nil)
        let recycledButton = taskbarView.button(forKey: updatedWin.key)
        
        // Assert that the exact same TaskButton view instance was recycled without recreation
        #expect(recycledButton === initialButton, "TaskbarView must reuse the identical TaskButton instance (pointer equality)")
        #expect(recycledButton?.windowInfo.title == "Recycled Title")
        #expect(recycledButton?.windowInfo.isMinimized == true)
    }
}
