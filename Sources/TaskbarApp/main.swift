// Sources/TaskbarApp/main.swift

import AppKit
import Darwin
import Dispatch
import TaskbarCore

// Install C atexit() hook for fail-safe Dock restoration
atexit {
    DockController.restoreDockSync()
}

// Retain signal sources so they remain active for the process lifetime
private var signalSources: [DispatchSourceSignal] = []

@MainActor
func installSignalHandlers() {
    let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]
    for sig in signals {
        signal(sig, SIG_IGN) // Ignore default kernel termination so DispatchSource handles it
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            print("\n[\(BuildConfiguration.appName)] Received termination signal (\(sig)). Restoring system Dock...")
            DockController.restoreDockSync()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
}

installSignalHandlers()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
