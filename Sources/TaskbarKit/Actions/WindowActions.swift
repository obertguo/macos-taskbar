// Sources/TaskbarKit/Actions/WindowActions.swift

import AppKit
import ApplicationServices
import TaskbarCore

public enum WindowActions {
    /// Resolves the specific AXUIElement corresponding to a WindowKey
    private static func findWindowElement(for key: WindowKey) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(key.pid)
        appElement.setTimeout(0.3)
        return appElement.windows.first { $0.windowID == key.id }
    }
    
    public static func performAction(_ action: ClickAction, for key: WindowKey) {
        AXThread.shared.async {
            switch action {
            case .focus:
                focusWindow(key)
            case .minimize:
                minimizeWindow(key)
            case .restoreAndFocus:
                restoreAndFocusWindow(key)
            }
        }
    }
    
    public static func focusWindow(_ key: WindowKey) {
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else {
                NSRunningApplication(processIdentifier: key.pid)?.activate()
                return
            }
            
            // 1. Raise the target window
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            
            // 2. Set as main window
            AXUIElementSetAttributeValue(winElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            
            // 3. Activate application without bringing all windows forward across displays
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: key.pid)?.activate(options: [])
            }
        }
    }
    
    public static func minimizeWindow(_ key: WindowKey) {
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else { return }
            
            // 1. Try direct attribute set
            let setResult = AXUIElementSetAttributeValue(winElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            
            // 2. If direct set failed or ignored (common in Chromium/Discord), press the minimize button
            if setResult != .success || !winElement.isMinimized {
                if let minButton = winElement.minimizeButton {
                    AXUIElementPerformAction(minButton, kAXPressAction as CFString)
                }
            }
        }
    }
    
    public static func restoreAndFocusWindow(_ key: WindowKey) {
        AXThread.shared.async {
            // Unhide app if hidden
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: key.pid)?.unhide()
            }
            
            guard let winElement = findWindowElement(for: key) else {
                DispatchQueue.main.async {
                    NSRunningApplication(processIdentifier: key.pid)?.activate()
                }
                return
            }
            
            // 1. Deminiaturize window
            AXUIElementSetAttributeValue(winElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            
            // 2. Raise and focus target window
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(winElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            
            // 3. Activate application without bringing all windows forward across displays
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: key.pid)?.activate(options: [])
            }
        }
    }
    
    public static func closeWindow(_ key: WindowKey) {
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else { return }
            
            var closeButtonValue: AnyObject?
            if AXUIElementCopyAttributeValue(winElement, kAXCloseButtonAttribute as CFString, &closeButtonValue) == .success,
               let closeButton = closeButtonValue {
                AXUIElementPerformAction((closeButton as! AXUIElement), kAXPressAction as CFString)
            }
        }
    }
    
    public static func quitApplication(pid: pid_t) {
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.terminate()
        }
    }
    
    public static func quitApplication(bundleIdentifier: String) {
        DispatchQueue.main.async {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            for app in runningApps {
                app.terminate()
            }
        }
    }
    
    public static func launchOrActivateApp(
        bundleIdentifier: String,
        customPath: String? = nil,
        store: WindowStore? = nil
    ) {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { !$0.isTerminated }
        if let runningApp = runningApps.first {
            DispatchQueue.main.async {
                runningApp.unhide()
            }
            
            if let store = store {
                let appWindows = store.allWindows.filter { $0.bundleID == bundleIdentifier && $0.pid == runningApp.processIdentifier }
                if let targetWindow = appWindows.first {
                    if targetWindow.isMinimized {
                        restoreAndFocusWindow(targetWindow.key)
                    } else {
                        focusWindow(targetWindow.key)
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                runningApp.activate()
            }
        } else {
            var targetURL: URL?
            if let customPath = customPath, !customPath.isEmpty, FileManager.default.fileExists(atPath: customPath) {
                targetURL = URL(fileURLWithPath: customPath)
            } else {
                targetURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            }
            
            guard let url = targetURL else {
                TaskbarLogger.ui.error("Cannot resolve launch URL for app: \(bundleIdentifier)")
                return
            }
            
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
}
