// Sources/TaskbarApp/System/Launcher.swift

import AppKit
import ApplicationServices
import TaskbarCore

@MainActor
public enum Launcher {
    public static func launch(_ action: LauncherAction) {
        switch action {
        case .spotlight:
            triggerSpotlight()
            
        case .raycast:
            if let url = URL(string: TaskbarConstants.Launcher.raycastScheme), NSWorkspace.shared.open(url) {
                return
            }
            let raycastURL = URL(fileURLWithPath: TaskbarConstants.Launcher.raycastAppPath)
            if FileManager.default.fileExists(atPath: raycastURL.path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: raycastURL, configuration: config, completionHandler: nil)
            } else {
                triggerSpotlight()
            }
            
        case .customPath(let path):
            let appURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: appURL.path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            } else {
                triggerSpotlight()
            }
        }
    }
    
    private static func triggerSpotlight() {
        // Ensure Accessibility permission is granted, otherwise prompt user
        if !AccessibilityPermission.isGranted() {
            print("[Launcher] Accessibility permission required to trigger Spotlight keystroke. Prompting...")
            AccessibilityPermission.promptIfNecessary()
            AccessibilityPermission.openSystemSettings()
            return
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdKey: CGKeyCode = 0x37  // Command
        let spaceKey: CGKeyCode = 0x31 // Space
        
        // 1. Post Command Down
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        // 2. Post Space Down with Command flag
        let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: spaceKey, keyDown: true)
        spaceDown?.flags = .maskCommand
        spaceDown?.post(tap: .cghidEventTap)
        
        // 3. Post Space Up and Command Up after a brief hardware pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: spaceKey, keyDown: false)
            spaceUp?.flags = .maskCommand
            spaceUp?.post(tap: .cghidEventTap)
            
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)
            cmdUp?.post(tap: .cghidEventTap)
        }
    }
}
