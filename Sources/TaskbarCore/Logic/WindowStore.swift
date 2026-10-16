// Sources/TaskbarCore/Logic/WindowStore.swift

import Foundation
import CoreGraphics

@MainActor public final class WindowStore {
    private var windows: [WindowKey: WindowInfo] = [:]
    private var customOrders: [UInt32: [OrderKey: Int]] = [:]
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
        let removedWindow = windows.removeValue(forKey: key)
        if focusedWindowKey == key {
            focusedWindowKey = nil
        }
        
        let bundleID = removedWindow?.bundleID
        let hasRemainingWindowsForApp: Bool
        if let bundleID = bundleID {
            hasRemainingWindowsForApp = windows.values.contains { $0.bundleID == bundleID }
        } else {
            hasRemainingWindowsForApp = true
        }
        
        for (screenID, order) in customOrders {
            var updated = order
            let removedWin = updated.removeValue(forKey: .window(key)) != nil
            var removedApp = false
            if let bundleID = bundleID, !hasRemainingWindowsForApp {
                removedApp = updated.removeValue(forKey: .app(bundleID)) != nil
            }
            if removedWin || removedApp {
                customOrders[screenID] = updated
            }
        }
    }
    
    public func removeWindows(forPID pid: pid_t) {
        let removedWindows = windows.values.filter { $0.pid == pid }
        let removedBundleIDs = Set(removedWindows.map { $0.bundleID })
        windows = windows.filter { $0.value.pid != pid }
        
        if let focused = focusedWindowKey, focused.pid == pid {
            focusedWindowKey = nil
        }
        
        let remainingBundleIDs = Set(windows.values.map { $0.bundleID })
        let orphanedBundleIDs = removedBundleIDs.subtracting(remainingBundleIDs)
        
        for (screenID, order) in customOrders {
            var updated = order
            var changed = false
            for orderKey in order.keys {
                switch orderKey {
                case let .window(key) where key.pid == pid:
                    updated.removeValue(forKey: orderKey)
                    changed = true
                case let .app(bundleID) where orphanedBundleIDs.contains(bundleID):
                    updated.removeValue(forKey: orderKey)
                    changed = true
                default:
                    break
                }
            }
            if changed {
                customOrders[screenID] = updated
            }
        }
    }
    
    @discardableResult
    public func setFocusedWindow(key: WindowKey?) -> Bool {
        if self.focusedWindowKey == key {
            return false
        }
        self.focusedWindowKey = key
        guard let key = key else { return true }
        if var win = windows[key] {
            focusOrderCounter += 1
            win.focusOrder = focusOrderCounter
            win.lastFocusedAt = Date()
            windows[key] = win
        }
        return true
    }
    
    @discardableResult
    public func setFrontmostPID(_ pid: pid_t?) -> Bool {
        if self.frontmostPID == pid {
            return false
        }
        self.frontmostPID = pid
        return true
    }
    
    public func setAppHidden(pid: pid_t, isHidden: Bool) {
        for (key, var win) in windows where win.pid == pid {
            win.isAppHidden = isHidden
            windows[key] = win
        }
    }
    
    /// Synchronizes the list of windows for a specific application PID.
    @discardableResult
    public func syncSnapshot(forPID pid: pid_t, currentWindows: [WindowInfo]) -> Bool {
        let previousWindows = windows.filter { $0.value.pid == pid }
        
        var didChange = false
        if previousWindows.count != currentWindows.count {
            didChange = true
        } else {
            var seenKeys = Set<WindowKey>()
            for current in currentWindows {
                if !seenKeys.insert(current.key).inserted {
                    didChange = true
                    break
                }
                guard let prev = previousWindows[current.key] else {
                    didChange = true
                    break
                }
                if prev.title != current.title ||
                   prev.isMinimized != current.isMinimized ||
                   prev.isAppHidden != current.isAppHidden ||
                   prev.isMain != current.isMain ||
                   prev.isFullScreen != current.isFullScreen {
                    didChange = true
                    break
                }
            }
        }
        
        let currentKeys = Set(currentWindows.map { $0.key })
        let closedWindows = previousWindows.filter { !currentKeys.contains($0.key) }
        let closedKeys = Set(closedWindows.keys)
        let closedBundleIDs = Set(closedWindows.values.map { $0.bundleID })
        
        // Remove windows for this PID that are no longer reported
        windows = windows.filter { key, info in
            info.pid != pid || currentKeys.contains(key)
        }
        
        // Update or insert current windows
        for window in currentWindows {
            addOrUpdateWindow(window)
        }
        
        // Clear focusedWindowKey if the previously focused window is no longer present in windows
        if let focused = focusedWindowKey, windows[focused] == nil {
            focusedWindowKey = nil
        }
        
        // Check if any closed window belonged to an app with no remaining windows
        let remainingBundleIDs = Set(windows.values.map { $0.bundleID })
        let orphanedBundleIDs = closedBundleIDs.subtracting(remainingBundleIDs)
        
        if !closedKeys.isEmpty || !orphanedBundleIDs.isEmpty {
            for (screenID, order) in customOrders {
                var updated = order
                var changed = false
                for closedKey in closedKeys {
                    if updated.removeValue(forKey: .window(closedKey)) != nil {
                        changed = true
                    }
                }
                for bundleID in orphanedBundleIDs {
                    if updated.removeValue(forKey: .app(bundleID)) != nil {
                        changed = true
                    }
                }
                if changed {
                    customOrders[screenID] = updated
                }
            }
        }
        
        return didChange
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
        
        // Single-pass Decorate-Sort-Undecorate using OrderKey
        let decorated: [(offset: Int, window: WindowInfo, slot: Int?)] = naturalOrder.enumerated().map { offset, win in
            let slot = screenOrder[.window(win.key)] ?? screenOrder[.app(win.bundleID)]
            return (offset, win, slot)
        }
        
        let sorted = decorated.sorted { left, right in
            switch (left.slot, right.slot) {
            case let (l?, r?):
                return l != r ? l < r : left.offset < right.offset
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.offset < right.offset
            }
        }
        
        return sorted.map { $0.window }
    }
    
    /// Retrieves the custom order slot mapping for a specific display, if set.
    public func customOrder(forScreenID screenID: UInt32) -> [OrderKey: Int] {
        customOrders[screenID] ?? [:]
    }
    
    /// Commits a new custom order slot mapping for a specific display.
    public func setCustomOrder(_ order: [OrderKey: Int], forScreenID screenID: UInt32) {
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
