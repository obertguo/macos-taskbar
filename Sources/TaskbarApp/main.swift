// Sources/TaskbarApp/main.swift

import AppKit
import TaskbarCore

@MainActor
final class MinimalAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[\(BuildConfiguration.appName)] v\(BuildConfiguration.appVersion) (\(BuildConfiguration.bundleID)) initialized successfully.")
    }
}

let app = NSApplication.shared
let delegate = MinimalAppDelegate()
app.delegate = delegate
_ = TaskbarCoreInfo()
