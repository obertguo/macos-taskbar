// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Taskbar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaskbarApp", targets: ["TaskbarApp"]),
        .library(name: "TaskbarCore", targets: ["TaskbarCore"])
    ],
    targets: [
        .target(
            name: "TaskbarCore",
            dependencies: [],
            path: "Sources/TaskbarCore"
        ),
        .executableTarget(
            name: "TaskbarApp",
            dependencies: ["TaskbarCore"],
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
        )
    ]
)
