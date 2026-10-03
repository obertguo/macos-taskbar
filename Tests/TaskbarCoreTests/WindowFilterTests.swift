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
    
    func testRejectTinyZeroSizedWindows() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertFalse(WindowFilter.shouldInclude(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            bundleID: "com.apple.Safari",
            isAppRegular: true
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
