// Sources/TaskbarApp/System/Launcher.swift

import AppKit
import TaskbarCore

@MainActor
public enum Launcher {
    public static func launch(_ action: LauncherAction) {
        switch action {
        case .spotlight:
            // Try activating Spotlight directly or fall back to AppleScript command
            let spotlightURL = URL(fileURLWithPath: "/System/Library/CoreServices/Spotlight.app")
            if FileManager.default.fileExists(atPath: spotlightURL.path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: spotlightURL, configuration: config, completionHandler: nil)
            } else {
                // Fallback: trigger Spotlight keyboard event via AppleScript
                let script = "tell application \"System Events\" to key code 49 using command down"
                if let appleScript = NSAppleScript(source: script) {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                }
            }
            
        case .raycast:
            if let url = URL(string: "raycast://"), NSWorkspace.shared.open(url) {
                return
            }
            // Fall back to opening Raycast app bundle if URL scheme failed
            let raycastURL = URL(fileURLWithPath: "/Applications/Raycast.app")
            if FileManager.default.fileExists(atPath: raycastURL.path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: raycastURL, configuration: config, completionHandler: nil)
            } else {
                // Fall back to Spotlight if Raycast isn't installed
                launch(.spotlight)
            }
            
        case .customPath(let path):
            let appURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: appURL.path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            } else {
                launch(.spotlight)
            }
        }
    }
}
