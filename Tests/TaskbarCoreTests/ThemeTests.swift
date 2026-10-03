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
    }
    
    func testRetroClassicTheme() {
        let theme = ThemeDefinition.forStyle(.retroClassic)
        XCTAssertEqual(theme.style, .retroClassic)
        XCTAssertFalse(theme.useTranslucency)
        XCTAssertTrue(theme.is3DBeveled)
        XCTAssertEqual(theme.buttonCornerRadius, 0.0)
        XCTAssertEqual(theme.backgroundColor, .retroGray)
    }
}
