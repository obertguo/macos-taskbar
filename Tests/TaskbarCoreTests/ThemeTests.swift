// Tests/TaskbarCoreTests/ThemeTests.swift

import XCTest
@testable import TaskbarCore

final class ThemeTests: XCTestCase {
    func testModernHybridTheme() {
        let theme = ThemeDefinition.forStyle(.modernHybrid)
        XCTAssertEqual(theme.style, .modernHybrid)
        XCTAssertTrue(theme.useTranslucency)
        XCTAssertFalse(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 4.0)
        XCTAssertEqual(theme.fontSize, TaskbarConstants.Layout.defaultFontSize)
        XCTAssertEqual(theme.iconSize, TaskbarConstants.Layout.defaultIconSize)
    }
    
    func testRetroClassicTheme() {
        let theme = ThemeDefinition.forStyle(.retroClassic, fontSize: 13.0, iconSize: 20.0)
        XCTAssertEqual(theme.style, .retroClassic)
        XCTAssertFalse(theme.useTranslucency)
        XCTAssertTrue(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 0.0)
        XCTAssertEqual(theme.backgroundColor, .retroGray)
        XCTAssertEqual(theme.fontSize, 13.0)
        XCTAssertEqual(theme.iconSize, 20.0)
    }
}
