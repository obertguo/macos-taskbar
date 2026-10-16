// Tests/TaskbarCoreTests/WindowFilterTests.swift

import CoreGraphics
import Testing
@testable import TaskbarCore

@Suite("Window Filter Tests")
struct WindowFilterTests {
    @Test("Accept standard regular window")
    func testAcceptStandardWindow() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let accepted = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true
        )
        #expect(accepted)
    }
    
    @Test("Accept minimized window with zero size")
    func testAcceptMinimizedWindowWithZeroSize() {
        // When Finder or Settings minimizes, Cocoa sets frame to 0x0
        let zeroFrame = CGRect.zero
        let accepted = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: zeroFrame,
            bundleID: "com.apple.finder",
            isAppRegular: true,
            isMinimized: true
        )
        #expect(accepted)
    }
    
    @Test("Reject dialogs and sheets")
    func testRejectDialogsAndSheets() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(!WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXDialog",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true
        ))
        
        #expect(!WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXSheet",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true
        ))
    }
    
    @Test("Reject tiny zero sized non-minimized windows")
    func testRejectTinyZeroSizedNonMinimizedWindows() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(!WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true,
            isMinimized: false
        ))
    }
    
    @Test("Reject non-regular apps and system overlays")
    func testRejectNonRegularAppsAndSystemOverlays() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        // Background helper app
        #expect(!WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.some.helper",
            isAppRegular: false
        ))
        
        // System Dock
        #expect(!WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.apple.dock",
            isAppRegular: true
        ))
    }
}
