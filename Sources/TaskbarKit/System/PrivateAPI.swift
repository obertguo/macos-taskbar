// Sources/TaskbarKit/System/PrivateAPI.swift

import Foundation
import ApplicationServices

public enum PrivateAPI {
    private typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetProcessForPIDFunc = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus
    private typealias SetFrontProcessWithOptionsFunc = @convention(c) (UnsafeMutableRawPointer, UInt32) -> OSStatus
    private typealias SLPSSetFrontProcessWithOptionsFunc = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> CGError

    private static let axUIElementGetWindowFn: AXUIElementGetWindowFunc? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: AXUIElementGetWindowFunc.self)
    }()

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

    public static func getWindowID(for element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        if let fn = axUIElementGetWindowFn, fn(element, &wid) == .success, wid != 0 {
            return wid
        }
        return nil
    }

    public static func activateSingleWindow(pid: pid_t, windowID: UInt32) -> Bool {
        struct PSN {
            var highLongOfPSN: UInt32 = 0
            var lowLongOfPSN: UInt32 = 0
        }
        guard let getPID = getProcessForPIDFn,
              let slpsSetFront = slpsSetFrontProcessWithOptionsFn else {
            return false
        }
        var psn = PSN()
        guard getPID(pid, &psn) == 0 else { return false }
        
        // 1. Designate the target window as frontmost within the owning process first
        let err = slpsSetFront(&psn, windowID, 0x200)
        guard err.rawValue == 0 else { return false }
        
        // 2. Elevate the process with option 1 (kSetFrontProcessFrontWindowOnly)
        // Since windowID was designated as the front window in step 1,
        // option 1 raises ONLY this window to the front of the display without raising other windows.
        if let setFront = setFrontProcessWithOptionsFn {
            _ = setFront(&psn, 1)
        }
        
        return true
    }
}
