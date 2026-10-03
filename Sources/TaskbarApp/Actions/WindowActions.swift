// Sources/TaskbarApp/Actions/WindowActions.swift

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
            
            // 1. Raise the window
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            
            // 2. Set as main window
            AXUIElementSetAttributeValue(winElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            
            // 3. Make owning application frontmost via AX
            let appElement = AXUIElementCreateApplication(key.pid)
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            
            // 4. Activate via NSRunningApplication
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: key.pid)?.activate()
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
            
            // 2. Raise and focus
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(winElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            
            let appElement = AXUIElementCreateApplication(key.pid)
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            
            // 3. Activate app
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: key.pid)?.activate()
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
}
