// Sources/TaskbarApp/System/AccessibilityPermission.swift

import ApplicationServices
import AppKit

@MainActor
public enum AccessibilityPermission {
    public static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }
    
    @discardableResult
    public static func promptIfNecessary() -> Bool {
        if isGranted() {
            return true
        }
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    public static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
