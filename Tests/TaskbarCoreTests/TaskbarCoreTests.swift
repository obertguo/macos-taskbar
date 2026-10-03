// Tests/TaskbarCoreTests/TaskbarCoreTests.swift

import XCTest
@testable import TaskbarCore

final class TaskbarCoreTests: XCTestCase {
    func testVersionAndInitialization() {
        XCTAssertEqual(TaskbarCoreInfo.version, "0.1.0")
        XCTAssertEqual(TaskbarCoreInfo.name, "TaskbarCore")
    }
}
