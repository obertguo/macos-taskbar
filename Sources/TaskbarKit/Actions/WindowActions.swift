// Sources/TaskbarKit/Actions/WindowActions.swift

import AppKit
import ApplicationServices
import TaskbarCore

public enum WindowActions {
    /// Resolves the specific AXUIElement corresponding to a WindowKey
    private static func findWindowElement(for key: WindowKey) -> AXUIElement? {
        if let cached = AppTracker.elementForWindowKey(key) {
            return cached
        }
        let appElement = AXUIElementCreateApplication(key.pid)
        appElement.setTimeout(TaskbarConstants.Timing.axTimeout)
        if let found = appElement.windows.first(where: { $0.windowID == key.id }) {
            AppTracker.cacheElement(found, for: key)
            return found
        }
        return nil
    }
    
    public static func performAction(_ action: ClickAction, for key: WindowKey) {
        switch action {
        case .focus:
            focusWindow(key)
        case .minimize:
            minimizeWindow(key)
        case .restoreAndFocus:
            restoreAndFocusWindow(key)
        }
    }
    
    /// Returns the window ID of the frontmost on-screen layer 0 window for a given process PID.
    /// Useful as a resilient fallback for Chromium and Electron apps that omit kAXFocusedWindowAttribute.
    public static func frontmostWindowID(forPID pid: pid_t) -> UInt32? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            let wid = w[kCGWindowNumber as String] as? UInt32 ?? 0
            if ownerPID == pid && layer == 0 && wid > 0 {
                if let bounds = w[kCGWindowBounds as String] as? [String: Any],
                   let width = bounds["Width"] as? Double,
                   let height = bounds["Height"] as? Double,
                   width > 20 && height > 20 {
                    return wid
                }
            }
        }
        return nil
    }
    
    /// Activates the owning process and focuses only the target window, preventing
    /// WindowServer from raising all other windows belonging to that application.
    @discardableResult
    private static func activateSingleWindow(key: WindowKey) -> Bool {
        PrivateAPI.activateSingleWindow(pid: key.pid, windowID: UInt32(key.id))
    }
    
    public static func focusWindow(_ key: WindowKey) {
        // 1. Immediately elevate target window via WindowServer SPI synchronously on click
        let activated = activateSingleWindow(key: key)
        
        // 2. Synchronize AppKit activation state
        let app = NSRunningApplication(processIdentifier: key.pid)
        if !activated || (app != nil && !app!.isActive) {
            app?.activate(options: [])
        }
        
        if AppTracker.isPIDBackedOff(key.pid) {
            return
        }
        
        // 3. Asynchronously inform AX of the main and raised window for accessibility clients
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else { return }
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(winElement, kAXMainAttribute as CFString, kCFBooleanTrue)
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
        // Unhide app if hidden
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: key.pid)?.unhide()
        }
        
        if AppTracker.isPIDBackedOff(key.pid) {
            let activated = activateSingleWindow(key: key)
            DispatchQueue.main.async {
                let app = NSRunningApplication(processIdentifier: key.pid)
                if !activated || (app != nil && !app!.isActive) {
                    app?.activate(options: [])
                }
            }
            return
        }
        
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else {
                DispatchQueue.main.async {
                    NSRunningApplication(processIdentifier: key.pid)?.activate(options: [])
                }
                return
            }
            
            // 1. Deminiaturize window
            AXUIElementSetAttributeValue(winElement, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            
            // 2. Raise and focus target window
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(winElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            
            // 3. Focus specific window immediately via WindowServer SPI without raising other windows
            let activated = activateSingleWindow(key: key)
            DispatchQueue.main.async {
                let app = NSRunningApplication(processIdentifier: key.pid)
                if !activated || (app != nil && !app!.isActive) {
                    app?.activate(options: [])
                }
            }
        }
    }
    
    public static func closeWindow(_ key: WindowKey) {
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else { return }
            
            var closeButtonValue: AnyObject?
            if AXUIElementCopyAttributeValue(winElement, kAXCloseButtonAttribute as CFString, &closeButtonValue) == .success,
               let closeButton = closeButtonValue,
               CFGetTypeID(closeButton) == AXUIElementGetTypeID() {
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
    
    @MainActor
    public static func launchOrActivateApp(
        bundleIdentifier: String,
        customPath: String? = nil,
        store: WindowStore? = nil,
        preferredWindows: [WindowInfo]? = nil
    ) {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { !$0.isTerminated }
        if let runningApp = runningApps.first {
            DispatchQueue.main.async {
                runningApp.unhide()
            }
            
            if let store = store {
                let appWindows = store.allWindows.filter { $0.bundleID == bundleIdentifier && $0.pid == runningApp.processIdentifier }
                let candidates: [WindowInfo]
                if let preferredWindows = preferredWindows {
                    let matching = preferredWindows.filter { $0.bundleID == bundleIdentifier && $0.pid == runningApp.processIdentifier }
                    candidates = matching.isEmpty ? appWindows : matching
                } else {
                    candidates = appWindows
                }
                if let targetWindow = WindowGroup.primaryWindow(from: candidates) {
                    if targetWindow.isMinimized {
                        restoreAndFocusWindow(targetWindow.key)
                    } else {
                        focusWindow(targetWindow.key)
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                runningApp.activate(options: [])
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
