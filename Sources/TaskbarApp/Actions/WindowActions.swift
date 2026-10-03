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
                // If window element lookup fails, fallback to activating the running application
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
            
            // 4. Also activate via NSRunningApplication for cooperative activation compliance
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: key.pid)?.activate()
            }
        }
    }
    
    public static func minimizeWindow(_ key: WindowKey) {
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else { return }
            AXUIElementSetAttributeValue(winElement, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }
    
    public static func restoreAndFocusWindow(_ key: WindowKey) {
        AXThread.shared.async {
            // Unhide app if hidden
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: key.pid)?.unhide()
            }
            
            guard let winElement = findWindowElement(for: key) else {
                NSRunningApplication(processIdentifier: key.pid)?.activate()
                return
            }
            
            // Deminiaturize window
            AXUIElementSetAttributeValue(winElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            
            // Raise and focus
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            let appElement = AXUIElementCreateApplication(key.pid)
            AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            
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
