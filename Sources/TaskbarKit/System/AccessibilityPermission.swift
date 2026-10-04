// Sources/TaskbarApp/System/AccessibilityPermission.swift

import ApplicationServices
import AppKit
import TaskbarCore

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
        let promptKey = TaskbarConstants.Accessibility.promptOptionKey as CFString
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    public static func openSystemSettings() {
        if let url = URL(string: TaskbarConstants.Accessibility.systemSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
