// Sources/TaskbarCore/Logic/WindowStore.swift

import Foundation
import CoreGraphics

@MainActor public final class WindowStore {
    private var windows: [WindowKey: WindowInfo] = [:]
    private var customOrders: [UInt32: [String: Int]] = [:]
    public private(set) var focusedWindowKey: WindowKey?
    public private(set) var frontmostPID: pid_t?
    private var openOrderCounter: UInt64 = 0
    private var focusOrderCounter: UInt64 = 0
    
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
            if info.focusOrder > existing.focusOrder {
                existing.focusOrder = info.focusOrder
                existing.lastFocusedAt = info.lastFocusedAt
            }
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
        let keyString = TaskbarConstants.Identifiers.windowID(pid: key.pid, id: key.id)
        for (screenID, order) in customOrders {
            if order[keyString] != nil {
                var updated = order
                updated.removeValue(forKey: keyString)
                customOrders[screenID] = updated
            }
        }
    }
    
    public func removeWindows(forPID pid: pid_t) {
        windows = windows.filter { $0.value.pid != pid }
        if let focused = focusedWindowKey, focused.pid == pid {
            focusedWindowKey = nil
        }
        let pidPrefix = TaskbarConstants.Identifiers.windowPIDPrefix(pid: pid)
        for (screenID, order) in customOrders {
            let updated = order.filter { !$0.key.hasPrefix(pidPrefix) }
            if updated.count != order.count {
                customOrders[screenID] = updated
            }
        }
    }
    
    public func setFocusedWindow(key: WindowKey?) {
        self.focusedWindowKey = key
        guard let key = key else { return }
        if var win = windows[key] {
            focusOrderCounter += 1
            win.focusOrder = focusOrderCounter
            win.lastFocusedAt = Date()
            windows[key] = win
        }
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
        let naturalOrder = assigned.sorted { $0.openOrder < $1.openOrder }
        guard let screenOrder = customOrders[screenID], !screenOrder.isEmpty else {
            return naturalOrder
        }
        return naturalOrder.enumerated().sorted { left, right in
            let leftKey = TaskbarConstants.Identifiers.windowID(pid: left.element.key.pid, id: left.element.key.id)
            let rightKey = TaskbarConstants.Identifiers.windowID(pid: right.element.key.pid, id: right.element.key.id)
            let leftSlot = screenOrder[leftKey]
            let rightSlot = screenOrder[rightKey]
            switch (leftSlot, rightSlot) {
            case let (l?, r?):
                return l != r ? l < r : left.offset < right.offset
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.offset < right.offset
            }
        }.map { $0.element }
    }
    
    /// Retrieves the custom order slot mapping for a specific display, if set.
    public func customOrder(forScreenID screenID: UInt32) -> [String: Int] {
        customOrders[screenID] ?? [:]
    }
    
    /// Commits a new custom order slot mapping for a specific display.
    public func setCustomOrder(_ order: [String: Int], forScreenID screenID: UInt32) {
        customOrders[screenID] = order
    }
    
    /// Clears the custom order for a specific display, restoring natural open order.
    public func clearCustomOrder(forScreenID screenID: UInt32) {
        customOrders.removeValue(forKey: screenID)
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
