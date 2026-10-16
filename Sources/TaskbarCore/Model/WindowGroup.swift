// Sources/TaskbarCore/Model/WindowGroup.swift

import Foundation

/// Represents a taskbar item corresponding to either a single window or an aggregated group of windows
/// belonging to the same application bundle.
public struct WindowGroup: Identifiable, Equatable, Sendable {
    /// Stable identifier used for view recycling and ordering maps.
    public let id: String
    
    /// The application bundle identifier.
    public let bundleID: String
    
    /// The localized application name.
    public let appName: String
    
    /// All windows associated with this group.
    public let windows: [WindowInfo]
    
    /// Indicates whether this item represents an active multi-window grouping (`count > 1`).
    public let isGrouped: Bool
    
    /// The number of windows in this group.
    public var count: Int {
        windows.count
    }
    
    /// The primary / most recently referenced window in the group.
    public var primaryWindow: WindowInfo? {
        Self.primaryWindow(from: windows)
    }
    
    public static func primaryWindow(from windows: [WindowInfo]) -> WindowInfo? {
        let unminimized = windows.filter { !$0.isMinimized }
        if !unminimized.isEmpty {
            return unminimized.max { a, b in
                if a.focusOrder != b.focusOrder {
                    return a.focusOrder < b.focusOrder
                }
                return a.openOrder > b.openOrder
            }
        }
        return windows.max { a, b in
            if a.focusOrder != b.focusOrder {
                return a.focusOrder < b.focusOrder
            }
            return a.openOrder > b.openOrder
        }
    }
    
    /// Returns `true` if any window in this group is currently focused and frontmost.
    public func isFocused(focusedKey: WindowKey?, frontmostPID: pid_t?) -> Bool {
        guard let focusedKey = focusedKey, let frontmostPID = frontmostPID else { return false }
        return windows.contains { win in
            win.key == focusedKey && win.pid == frontmostPID && !win.isMinimized && !win.isAppHidden
        }
    }
    
    /// Returns `true` if all windows in this group are currently minimized.
    public var isMinimized: Bool {
        !windows.isEmpty && windows.allSatisfy { $0.isMinimized }
    }
    
    /// Returns `true` if all windows in this group are currently hidden.
    public var isAppHidden: Bool {
        !windows.isEmpty && windows.allSatisfy { $0.isAppHidden }
    }
    
    /// Formatted label to display on the taskbar button.
    public var displayTitle: String {
        if isGrouped {
            return TaskbarStrings.WindowGrouping.groupedTitle(appName: appName, count: windows.count)
        } else {
            return primaryWindow?.displayTitle ?? appName
        }
    }
    
    public init(
        id: String,
        bundleID: String,
        appName: String,
        windows: [WindowInfo],
        isGrouped: Bool
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.windows = windows
        self.isGrouped = isGrouped
    }
    
    /// Convenience initializer for a single, ungrouped window.
    public static func singleWindow(_ window: WindowInfo) -> WindowGroup {
        WindowGroup(
            id: TaskbarConstants.Identifiers.windowID(pid: window.key.pid, id: window.key.id),
            bundleID: window.bundleID,
            appName: window.appName,
            windows: [window],
            isGrouped: false
        )
    }
    
    /// Convenience initializer for an application group.
    public static func applicationGroup(bundleID: String, appName: String, windows: [WindowInfo]) -> WindowGroup {
        WindowGroup(
            id: TaskbarConstants.Identifiers.groupID(bundleID: bundleID),
            bundleID: bundleID,
            appName: appName,
            windows: windows,
            isGrouped: windows.count > 1
        )
    }
}
