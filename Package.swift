// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Taskbar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskbarApp", targets: ["TaskbarApp"]),
        .library(name: "TaskbarCore", targets: ["TaskbarCore"]),
        .library(name: "TaskbarKit", targets: ["TaskbarKit"])
    ],
    targets: [
        .target(
            name: "TaskbarCore",
            dependencies: [],
            path: "Sources/TaskbarCore"
        ),
        .target(
            name: "TaskbarKit",
            dependencies: ["TaskbarCore"],
            path: "Sources/TaskbarKit",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "TaskbarApp",
            dependencies: ["TaskbarCore", "TaskbarKit"],
            path: "Sources/TaskbarApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "TaskbarCoreTests",
            dependencies: ["TaskbarCore"],
            path: "Tests/TaskbarCoreTests"
        ),
        .testTarget(
            name: "TaskbarIntegrationTests",
            dependencies: ["TaskbarKit", "TaskbarCore"],
            path: "Tests/TaskbarIntegrationTests"
        )
    ]
)
