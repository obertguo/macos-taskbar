// Tests/TaskbarIntegrationTests/EdgeCasesIntegrationTests.swift

import Foundation
import Testing
import CoreGraphics
import TaskbarCore
import TaskbarKit

@Suite("Edge Cases Integration Suite")
@MainActor
struct EdgeCasesIntegrationTests {
    
    @Test("TC-EDGE-001: Zero-size (0x0) frame filtering behavior")
    func testZeroSizeWindowFiltering() {
        let zeroFrame = CGRect(x: 0, y: 0, width: 0, height: 0)
        let standardFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
        
        // Minimized 0x0 window (Chromium docked window) -> MUST be included
        let minimizedZero = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: zeroFrame,
            bundleID: "com.google.Chrome",
            isAppRegular: true,
            isMinimized: true
        )
        #expect(minimizedZero == true, "Minimized 0x0 window must be included")
        
        // Non-minimized 0x0 window (invisible tracking window) -> MUST be rejected
        let invisibleZero = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: zeroFrame,
            bundleID: "com.google.Chrome",
            isAppRegular: true,
            isMinimized: false
        )
        #expect(invisibleZero == false, "Non-minimized 0x0 window must be rejected")
        
        // Standard normal window -> MUST be included
        let standardNormal = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: standardFrame,
            bundleID: "com.apple.Safari",
            isAppRegular: true,
            isMinimized: false
        )
        #expect(standardNormal == true, "Standard normal window must be included")
    }
    
    @Test("TC-EDGE-002: Modal sheets and system dialog subrole rejection")
    func testModalSheetRejection() {
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        
        // Modal Sheet (e.g. Save As sheet)
        let sheetIncluded = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXSheet",
            frame: frame,
            bundleID: "com.apple.TextEdit",
            isAppRegular: true,
            isMinimized: false
        )
        #expect(sheetIncluded == false, "AXSheet subrole must be rejected")
        
        // Modal Dialog
        let dialogIncluded = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXDialog",
            frame: frame,
            bundleID: "com.apple.TextEdit",
            isAppRegular: true,
            isMinimized: false
        )
        #expect(dialogIncluded == false, "AXDialog subrole must be rejected")
        
        // System Dialog
        let sysDialogIncluded = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXSystemDialog",
            frame: frame,
            bundleID: "com.apple.TextEdit",
            isAppRegular: true,
            isMinimized: false
        )
        #expect(sysDialogIncluded == false, "AXSystemDialog subrole must be rejected")
    }
    
    @Test("TC-EDGE-003: Rapid title churn and debounce coalescing")
    func testRapidTitleChurnDebouncing() async throws {
        let store = WindowStore()
        let tracker = AppTracker(store: store)
        defer { tracker.stopTracking() }
        
        var refreshCount = 0
        tracker.onWindowsChanged = {
            refreshCount += 1
        }
        
        // Rapidly schedule 25 reconciliations within a tight burst (< 20ms)
        for _ in 0..<25 {
            tracker.scheduleReconcile(delay: TaskbarConstants.Timing.frameRenderDebounce)
        }
        
        // Wait for debounce timer to settle
        try await Task.sleep(nanoseconds: 150_000_000)
        
        // Debouncer should coalesce into at most 1 or 2 reconciliation calls
        #expect(refreshCount <= 2, "Rapid burst calls should be coalesced by debounce timer")
    }
    
    @Test("TC-EDGE-004: Screen boundary and display partitioning")
    func testScreenBoundaryPartitioning() {
        let primaryScreen = ScreenDescriptor(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            isPrimary: true
        )
        let secondaryScreen = ScreenDescriptor(
            id: 2,
            frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            isPrimary: false
        )
        
        // Window on primary screen
        let winPrimaryFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let assignedPrimary = ScreenAssignment.assignScreen(for: winPrimaryFrame, across: [primaryScreen, secondaryScreen])
        #expect(assignedPrimary == 1, "Window should be assigned to primary screen (ID 1)")
        
        // Window on secondary screen
        let winSecondaryFrame = CGRect(x: 2000, y: 200, width: 1000, height: 800)
        let assignedSecondary = ScreenAssignment.assignScreen(for: winSecondaryFrame, across: [primaryScreen, secondaryScreen])
        #expect(assignedSecondary == 2, "Window should be assigned to secondary screen (ID 2)")
    }
}
