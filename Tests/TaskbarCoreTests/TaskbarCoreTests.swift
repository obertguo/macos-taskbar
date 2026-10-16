// Tests/TaskbarCoreTests/TaskbarCoreTests.swift

import Foundation
import Testing
@testable import TaskbarCore

@Suite("TaskbarCore Build Configuration Tests")
struct TaskbarCoreTests {
    @Test("Build configuration properties")
    func testBuildConfiguration() {
        #expect(TaskbarCoreInfo.version == BuildConfiguration.appVersion)
        #expect(TaskbarCoreInfo.name == BuildConfiguration.appName)
        #expect(TaskbarCoreInfo.bundleID == BuildConfiguration.bundleID)
        #expect(!BuildConfiguration.appName.isEmpty)
        #expect(!BuildConfiguration.bundleID.isEmpty)
        #expect(!BuildConfiguration.appVersion.isEmpty)
    }
}
