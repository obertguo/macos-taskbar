// Tests/TaskbarCoreTests/TaskbarCoreTests.swift

import XCTest
@testable import TaskbarCore

final class TaskbarCoreTests: XCTestCase {
    func testBuildConfiguration() {
        XCTAssertEqual(TaskbarCoreInfo.version, BuildConfiguration.appVersion)
        XCTAssertEqual(TaskbarCoreInfo.name, BuildConfiguration.appName)
        XCTAssertEqual(TaskbarCoreInfo.bundleID, BuildConfiguration.bundleID)
        XCTAssertFalse(BuildConfiguration.appName.isEmpty)
        XCTAssertFalse(BuildConfiguration.bundleID.isEmpty)
        XCTAssertFalse(BuildConfiguration.appVersion.isEmpty)
    }
}
