// Sources/TaskbarCore/Logic/WindowStore.swift

import Foundation
import CoreGraphics

public final class WindowStore: @unchecked Sendable {
    private var windows: [WindowKey: WindowInfo] = [:]
    public private(set) var focusedWindowKey: WindowKey?
    public private(set) var frontmostPID: pid_t?
    private var openOrderCounter: UInt64 = 0
    
    public init() {}
    
    /// Adds a new window or updates an existing window, preserving stable openOrder.
    public func addOrUpdateWindow(_ info: WindowInfo) {
        if var existing = windows[info.key] {
            existing.title = info.title
            // If window is minimized and reported frame is zero/offscreen, preserve last-known non-zero frame
            if info.frame.width > 10 && info.frame.height > 10 {
                existing.frame = info.frame
            }
            existing.isMinimized = info.isMinimized
            existing.isAppHidden = info.isAppHidden
            existing.isMain = info.isMain
            existing.isFullScreen = info.isFullScreen
            windows[info.key] = existing
        } else {
            openOrderCounter += 1
            var newWindow = info
            newWindow.openOrder = openOrderCounter
            windows[info.key] = newWindow
        }
    }
    
    public func setMinimized(key: WindowKey, isMinimized: Bool) {
        if var win = windows[key] {
            win.isMinimized = isMinimized
            windows[key] = win
            if isMinimized && focusedWindowKey == key {
                focusedWindowKey = nil
            }
        }
    }
    
    public func removeWindow(key: WindowKey) {
        windows.removeValue(forKey: key)
        if focusedWindowKey == key {
            focusedWindowKey = nil
        }
    }
    
    public func removeWindows(forPID pid: pid_t) {
        windows = windows.filter { $0.value.pid != pid }
        if let focused = focusedWindowKey, focused.pid == pid {
            focusedWindowKey = nil
        }
    }
    
    public func setFocusedWindow(key: WindowKey?) {
        self.focusedWindowKey = key
    }
    
    public func setFrontmostPID(_ pid: pid_t?) {
        self.frontmostPID = pid
    }
    
    public func setAppHidden(pid: pid_t, isHidden: Bool) {
        for (key, var win) in windows where win.pid == pid {
            win.isAppHidden = isHidden
            windows[key] = win
        }
    }
    
    /// Synchronizes the list of windows for a specific application PID.
    public func syncSnapshot(forPID pid: pid_t, currentWindows: [WindowInfo]) {
        let currentKeys = Set(currentWindows.map { $0.key })
        
        // Remove windows for this PID that are no longer reported
        windows = windows.filter { key, info in
            info.pid != pid || currentKeys.contains(key)
        }
        
        // Update or insert current windows
        for window in currentWindows {
            addOrUpdateWindow(window)
        }
    }
    
    /// Returns the ordered list of windows belonging to the specified display.
    public func windows(forScreenID screenID: UInt32, screens: [ScreenDescriptor]) -> [WindowInfo] {
        let assigned = windows.values.filter { window in
            ScreenAssignment.assignScreen(for: window.frame, across: screens) == screenID
        }
        return assigned.sorted { $0.openOrder < $1.openOrder }
    }
    
    /// Total count of tracked windows across all screens.
    public var totalWindowCount: Int {
        windows.count
    }
    
    /// Returns all tracked windows across all screens sorted by stable open order.
    public var allWindows: [WindowInfo] {
        windows.values.sorted { $0.openOrder < $1.openOrder }
    }
    
    public func window(forKey key: WindowKey) -> WindowInfo? {
        windows[key]
    }
}
