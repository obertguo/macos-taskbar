// Tests/TaskbarCoreTests/WorkAreaMathTests.swift

import XCTest
import CoreGraphics
@testable import TaskbarCore

final class WorkAreaMathTests: XCTestCase {
    
    let primaryScreen = ScreenDescriptor(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        isPrimary: true
    )
    
    let secondaryScreen = ScreenDescriptor(
        id: 2,
        frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080),
        isPrimary: false
    )
    
    func testNoOverlap() {
        // Window centered in primary screen (y: 200, height: 400 => maxY: 600)
        // Taskbar top is 900 - 30 = 870. No overlap.
        let frame = CGRect(x: 100, y: 200, width: 800, height: 400)
        let result = WorkAreaMath.clampedFrame(windowFrame: frame, screenBounds: primaryScreen.frame, barDimension: 30, edge: .bottom)
        XCTAssertNil(result)
    }
    
    func testWindowFlushWithTaskbar() {
        // Window ends exactly at taskbar top (maxY: 870)
        let frame = CGRect(x: 100, y: 100, width: 800, height: 770)
        let result = WorkAreaMath.clampedFrame(windowFrame: frame, screenBounds: primaryScreen.frame, barDimension: 30, edge: .bottom)
        XCTAssertNil(result)
    }
    
    func testSubpixelOverlapWithinThreshold() {
        // Overlap is 1.5pt (maxY is 871.5, threshold is 2.0pt)
        let frame = CGRect(x: 100, y: 100, width: 800, height: 771.5)
        let result = WorkAreaMath.clampedFrame(windowFrame: frame, screenBounds: primaryScreen.frame, barDimension: 30, edge: .bottom)
        XCTAssertNil(result)
    }
    
    func testMaximizedWindowClamping() {
        // Maximized window: top at 25 (menu bar), height 875 => maxY = 900 (bottom of screen)
        // Overlap = 900 - (900 - 30) = 30pt
        let frame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let clamped = WorkAreaMath.clampedFrame(windowFrame: frame, screenBounds: primaryScreen.frame, barDimension: 30, edge: .bottom)
        
        XCTAssertNotNil(clamped)
        guard let clamped = clamped else { return }
        
        XCTAssertEqual(clamped.origin.x, 0)
        XCTAssertEqual(clamped.origin.y, 25)
        XCTAssertEqual(clamped.width, 1440)
        XCTAssertEqual(clamped.height, 845) // 875 - 30
        XCTAssertEqual(clamped.maxY, 870) // Exactly flush with taskbar top!
    }
    
    func testMultiMonitorClampingOnSecondaryScreen() {
        // Secondary screen: y = -180, height = 1080 => maxY = 900.
        // Taskbar top is 900 - 30 = 870.
        // Maximized window on secondary: x = 1440, y = -155, width = 1920, height = 1055 => maxY = 900.
        let screens = [primaryScreen, secondaryScreen]
        let frame = CGRect(x: 1440, y: -155, width: 1920, height: 1055)
        
        let clamped = WorkAreaMath.clampedFrameForWindow(frame, across: screens, barDimension: 30, edge: .bottom)
        XCTAssertNotNil(clamped)
        guard let clamped = clamped else { return }
        
        XCTAssertEqual(clamped.origin.x, 1440)
        XCTAssertEqual(clamped.origin.y, -155)
        XCTAssertEqual(clamped.width, 1920)
        XCTAssertEqual(clamped.height, 1025) // 1055 - 30
        XCTAssertEqual(clamped.maxY, 870)
    }
    
    func testWindowBelowTaskbarRejected() {
        // Window origin is already inside or below the taskbar
        let frame = CGRect(x: 100, y: 880, width: 300, height: 100)
        let result = WorkAreaMath.clampedFrame(windowFrame: frame, screenBounds: primaryScreen.frame, barDimension: 30, edge: .bottom)
        XCTAssertNil(result)
    }
    
    func testWindowTooSmallAfterClamping() {
        // Window at y: 800, height: 100 => maxY: 900.
        // Clamping to 870 would give height: 70 (< minimumWindowHeight of 100)
        let frame = CGRect(x: 100, y: 800, width: 300, height: 100)
        let result = WorkAreaMath.clampedFrame(windowFrame: frame, screenBounds: primaryScreen.frame, barDimension: 30, edge: .bottom)
        XCTAssertNil(result)
    }
    
    func testZeroTaskbarHeight() {
        let frame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let result = WorkAreaMath.clampedFrame(windowFrame: frame, screenBounds: primaryScreen.frame, barDimension: 0, edge: .bottom)
        XCTAssertNil(result)
    }
    
    func testIsVerticallyMaximized() {
        let screen = primaryScreen.frame
        let fullMaximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertTrue(WorkAreaMath.isVerticallyMaximized(fullMaximized, screenFrame: screen))
        
        let halfTiled = CGRect(x: 720, y: 25, width: 720, height: 875)
        XCTAssertTrue(WorkAreaMath.isVerticallyMaximized(halfTiled, screenFrame: screen))
        
        // MacBook notch display test (menu bar ~52pt, window ends at 875pt overlapping taskbar by 5pt)
        let notchWindow = CGRect(x: 0, y: 52, width: 1440, height: 823) // maxY: 875
        XCTAssertTrue(WorkAreaMath.isVerticallyMaximized(notchWindow, screenFrame: screen, taskbarHeight: 30))
        
        let smallCenter = CGRect(x: 200, y: 200, width: 500, height: 400)
        XCTAssertFalse(WorkAreaMath.isVerticallyMaximized(smallCenter, screenFrame: screen))
        
        let bottomWindow = CGRect(x: 100, y: 600, width: 500, height: 300) // maxY: 900, but minY: 600 (not near top)
        XCTAssertFalse(WorkAreaMath.isVerticallyMaximized(bottomWindow, screenFrame: screen))
    }
    
    func testAllowNonMaximizedFlag() {
        let screen = primaryScreen.frame
        let bottomWindow = CGRect(x: 100, y: 600, width: 500, height: 300) // maxY: 900
        
        // When allowNonMaximized is false (e.g. on window moved), it should NOT clamp small window
        let movedResult = WorkAreaMath.clampedFrame(windowFrame: bottomWindow, screenBounds: screen, barDimension: 30, edge: .bottom, allowNonMaximized: false)
        XCTAssertNil(movedResult)
        
        // When allowNonMaximized is true (e.g. on window resized), it clamps
        let resizedResult = WorkAreaMath.clampedFrame(windowFrame: bottomWindow, screenBounds: screen, barDimension: 30, edge: .bottom, allowNonMaximized: true)
        XCTAssertNotNil(resizedResult)
        XCTAssertEqual(resizedResult?.height, 270)
        
        // For maximized window, allowNonMaximized: false STILL clamps
        let fullMaximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let maxResult = WorkAreaMath.clampedFrame(windowFrame: fullMaximized, screenBounds: screen, barDimension: 30, edge: .bottom, allowNonMaximized: false)
        XCTAssertNotNil(maxResult)
        XCTAssertEqual(maxResult?.height, 845)
    }
    
    // MARK: - TC-UNIT-013: Multi-Edge Screen Clamping Geometry
    
    func testMultiEdgeClampingTopEdge() {
        let screen = primaryScreen.frame // 0, 0, 1440, 900
        
        // Window starting at top of screen (y = 0) overlapping 30pt top bar
        let window = CGRect(x: 100, y: 0, width: 800, height: 700)
        let clamped = WorkAreaMath.clampedFrame(
            windowFrame: window,
            screenBounds: screen,
            barDimension: 30,
            edge: .top,
            allowNonMaximized: true
        )
        
        XCTAssertNotNil(clamped)
        XCTAssertEqual(clamped?.origin.y, 30)
        XCTAssertEqual(clamped?.height, 670)
        XCTAssertEqual(clamped?.maxY, 700)
        
        // Sub-pixel overlap: window starting at y = 29.0 (overlap is 1.0pt <= 2.0pt threshold)
        let subpixelWindow = CGRect(x: 100, y: 29.0, width: 800, height: 600)
        let subpixelResult = WorkAreaMath.clampedFrame(
            windowFrame: subpixelWindow,
            screenBounds: screen,
            barDimension: 30,
            edge: .top,
            allowNonMaximized: true
        )
        XCTAssertNil(subpixelResult)
    }
    
    func testMultiEdgeClampingLeftEdge() {
        let screen = primaryScreen.frame
        
        // Window at left edge (x = 0) overlapping 40pt left bar
        let window = CGRect(x: 0, y: 100, width: 1000, height: 600)
        let clamped = WorkAreaMath.clampedFrame(
            windowFrame: window,
            screenBounds: screen,
            barDimension: 40,
            edge: .left,
            allowNonMaximized: true
        )
        
        XCTAssertNotNil(clamped)
        XCTAssertEqual(clamped?.origin.x, 40)
        XCTAssertEqual(clamped?.width, 960)
        XCTAssertEqual(clamped?.maxX, 1000)
        
        // Sub-pixel overlap: window starting at x = 39.0 (overlap is 1.0pt <= 2.0pt)
        let subpixelWindow = CGRect(x: 39.0, y: 100, width: 800, height: 600)
        let subpixelResult = WorkAreaMath.clampedFrame(
            windowFrame: subpixelWindow,
            screenBounds: screen,
            barDimension: 40,
            edge: .left,
            allowNonMaximized: true
        )
        XCTAssertNil(subpixelResult)
    }
    
    func testMultiEdgeClampingRightEdge() {
        let screen = primaryScreen.frame // width: 1440. Right bar: 40pt -> reserved x: 1400...1440
        
        // Window extending to screen right edge (x: 500, width: 940 => maxX: 1440)
        let window = CGRect(x: 500, y: 100, width: 940, height: 600)
        let clamped = WorkAreaMath.clampedFrame(
            windowFrame: window,
            screenBounds: screen,
            barDimension: 40,
            edge: .right,
            allowNonMaximized: true
        )
        
        XCTAssertNotNil(clamped)
        XCTAssertEqual(clamped?.origin.x, 500)
        XCTAssertEqual(clamped?.width, 900)
        XCTAssertEqual(clamped?.maxX, 1400)
        
        // Sub-pixel overlap: maxX is 1401.5 (overlap is 1.5pt <= 2.0pt threshold)
        let subpixelWindow = CGRect(x: 500, y: 100, width: 901.5, height: 600)
        let subpixelResult = WorkAreaMath.clampedFrame(
            windowFrame: subpixelWindow,
            screenBounds: screen,
            barDimension: 40,
            edge: .right,
            allowNonMaximized: true
        )
        XCTAssertNil(subpixelResult)
    }
    
    func testMultiEdgeClampingNonMaximizedFiltering() {
        let screen = primaryScreen.frame
        
        // Small floating window at left edge (width 300, < 45% screen width)
        let smallLeftWindow = CGRect(x: 0, y: 200, width: 300, height: 400)
        let ignoredLeft = WorkAreaMath.clampedFrame(
            windowFrame: smallLeftWindow,
            screenBounds: screen,
            barDimension: 40,
            edge: .left,
            allowNonMaximized: false
        )
        XCTAssertNil(ignoredLeft)
        
        // Horizontally maximized window at left edge (width 1440 >= 45% screen width)
        let wideWindow = CGRect(x: 0, y: 200, width: 1440, height: 400)
        let clampedWide = WorkAreaMath.clampedFrame(
            windowFrame: wideWindow,
            screenBounds: screen,
            barDimension: 40,
            edge: .left,
            allowNonMaximized: false
        )
        XCTAssertNotNil(clampedWide)
        XCTAssertEqual(clampedWide?.origin.x, 40)
        XCTAssertEqual(clampedWide?.width, 1400)
    }
}
