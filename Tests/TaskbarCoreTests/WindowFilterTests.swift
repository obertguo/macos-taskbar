// Tests/TaskbarCoreTests/WindowFilterTests.swift

import XCTest
import CoreGraphics
@testable import TaskbarCore

final class WindowFilterTests: XCTestCase {
    func testAcceptStandardWindow() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let accepted = WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true
        )
        XCTAssertTrue(accepted)
    }
    
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
        XCTAssertTrue(accepted, "Minimized windows must never be rejected even if their frame is 0x0")
    }
    
    func testRejectDialogsAndSheets() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertFalse(WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXDialog",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true
        ))
        
        XCTAssertFalse(WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXSheet",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true
        ))
    }
    
    func testRejectTinyZeroSizedNonMinimizedWindows() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertFalse(WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true,
            isMinimized: false
        ))
    }
    
    func testRejectNonRegularAppsAndSystemOverlays() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        // Background helper app
        XCTAssertFalse(WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.some.helper",
            isAppRegular: false
        ))
        
        // System Dock
        XCTAssertFalse(WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.apple.dock",
            isAppRegular: true
        ))
    }
}
