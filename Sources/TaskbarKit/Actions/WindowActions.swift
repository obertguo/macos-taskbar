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
        switch action {
        case .focus:
            focusWindow(key)
        case .minimize:
            minimizeWindow(key)
        case .restoreAndFocus:
            restoreAndFocusWindow(key)
        }
    }
    
    private struct PSN {
        var highLongOfPSN: UInt32 = 0
        var lowLongOfPSN: UInt32 = 0
    }
    
    private typealias GetProcessForPIDFunc = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus
    private typealias SetFrontProcessWithOptionsFunc = @convention(c) (UnsafeMutableRawPointer, UInt32) -> OSStatus
    private typealias SLPSSetFrontProcessWithOptionsFunc = @convention(c) (
        UnsafeMutableRawPointer,
        UInt32,
        UInt32
    ) -> CGError
    
    private static let getProcessForPIDFn: GetProcessForPIDFunc? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "GetProcessForPID") else { return nil }
        return unsafeBitCast(sym, to: GetProcessForPIDFunc.self)
    }()
    
    private static let setFrontProcessWithOptionsFn: SetFrontProcessWithOptionsFunc? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(sym, to: SetFrontProcessWithOptionsFunc.self)
    }()
    
    private static let slpsSetFrontProcessWithOptionsFn: SLPSSetFrontProcessWithOptionsFunc? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(sym, to: SLPSSetFrontProcessWithOptionsFunc.self)
    }()
    
    /// Activates the owning process and focuses only the target window, preventing
    /// WindowServer from raising all other windows belonging to that application.
    @discardableResult
    private static func activateSingleWindow(key: WindowKey) -> Bool {
        guard let getPID = getProcessForPIDFn,
              let setFront = slpsSetFrontProcessWithOptionsFn else {
            return false
        }
        var psn = PSN()
        let pidStatus = getPID(key.pid, &psn)
        guard pidStatus == 0 else {
            return false
        }
        
        // 1. kSetFrontProcessFrontWindowOnly = 0x0001: Bring the application's front window to the front
        // without pulling other windows of the application forward.
        if let setFrontProcess = setFrontProcessWithOptionsFn {
            _ = setFrontProcess(&psn, 1)
        }
        
        // 2. 0x200 corresponds to kCPSUserGenerated, targeting the specific window ID.
        let status = setFront(&psn, UInt32(key.id), 0x200)
        return status == .success
    }
    
    public static func focusWindow(_ key: WindowKey) {
        AXThread.shared.async {
            guard let winElement = findWindowElement(for: key) else {
                DispatchQueue.main.async {
                    NSRunningApplication(processIdentifier: key.pid)?.activate()
                }
                return
            }
            
            // 1. Raise the target window via AX
            AXUIElementPerformAction(winElement, kAXRaiseAction as CFString)
            
            // 2. Set as main window
            AXUIElementSetAttributeValue(winElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            
            // 3. Focus specific window immediately via WindowServer SPI without raising other windows
            if !activateSingleWindow(key: key) {
                DispatchQueue.main.async {
                    NSRunningApplication(processIdentifier: key.pid)?.activate(options: [])
                }
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
            
            // 3. Focus specific window immediately via WindowServer SPI without raising other windows
            if !activateSingleWindow(key: key) {
                DispatchQueue.main.async {
                    NSRunningApplication(processIdentifier: key.pid)?.activate(options: [])
                }
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
