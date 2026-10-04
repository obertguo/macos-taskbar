// Tests/TaskbarCoreTests/ButtonLayoutTests.swift

import XCTest
@testable import TaskbarCore

final class ButtonLayoutTests: XCTestCase {
    func testSpaciousLayout() {
        let result = ButtonLayout.computeLayout(
            availableWidth: 1000.0,
            itemCount: 3,
            maxButtonWidth: 160.0,
            minButtonWidth: 28.0,
            spacing: 2.0
        )
        XCTAssertEqual(result.buttonWidth, 160.0)
        XCTAssertEqual(result.visibleCount, 3)
        XCTAssertTrue(result.showTitle)
        XCTAssertFalse(result.hasOverflow)
    }
    
    func testCompressingLayout() {
        // 500px for 5 buttons -> ~98px each (below max 160, above min 28)
        let result = ButtonLayout.computeLayout(
            availableWidth: 500.0,
            itemCount: 5,
            maxButtonWidth: 160.0,
            minButtonWidth: 28.0,
            spacing: 2.0
        )
        XCTAssertLessThan(result.buttonWidth, 160.0)
        XCTAssertGreaterThan(result.buttonWidth, 28.0)
        XCTAssertEqual(result.visibleCount, 5)
        XCTAssertTrue(result.showTitle)
        XCTAssertFalse(result.hasOverflow)
    }
    
    func testIconOnlyLayout() {
        // 100px for 2 buttons -> ~49px each (below 50 -> showTitle is false)
        let result = ButtonLayout.computeLayout(
            availableWidth: 100.0,
            itemCount: 2,
            maxButtonWidth: 160.0,
            minButtonWidth: 28.0,
            spacing: 2.0
        )
        XCTAssertFalse(result.showTitle)
        XCTAssertEqual(result.visibleCount, 2)
        XCTAssertFalse(result.hasOverflow)
    }
    
    func testOverflowLayout() {
        // 80px for 10 buttons (min 28px each -> only 2 fit: 28 + 2 + 28 = 58)
        let result = ButtonLayout.computeLayout(
            availableWidth: 80.0,
            itemCount: 10,
            maxButtonWidth: 160.0,
            minButtonWidth: 28.0,
            spacing: 2.0
        )
        XCTAssertEqual(result.buttonWidth, 28.0)
        XCTAssertEqual(result.visibleCount, 2)
        XCTAssertFalse(result.showTitle)
        XCTAssertTrue(result.hasOverflow)
    }
    
    func testOverflowLayoutWithWideButtons() {
        // 500px for 10 buttons with minButtonWidth 80px -> 6 fit: 6 * 80 + 5 * 2 = 490px
        let result = ButtonLayout.computeLayout(
            availableWidth: 500.0,
            itemCount: 10,
            maxButtonWidth: 160.0,
            minButtonWidth: 80.0,
            spacing: 2.0
        )
        XCTAssertEqual(result.buttonWidth, 80.0)
        XCTAssertEqual(result.visibleCount, 6)
        XCTAssertTrue(result.showTitle)
        XCTAssertTrue(result.hasOverflow)
    }

    func testCustomTitleVisibilityThreshold() {
        // 100px for 2 buttons -> ~49px each. With threshold 40.0, title should be shown
        let result = ButtonLayout.computeLayout(
            availableWidth: 100.0,
            itemCount: 2,
            maxButtonWidth: 160.0,
            minButtonWidth: 28.0,
            spacing: 2.0,
            titleVisibilityThreshold: 40.0
        )
        XCTAssertTrue(result.showTitle)
        XCTAssertEqual(result.visibleCount, 2)
    }
}

