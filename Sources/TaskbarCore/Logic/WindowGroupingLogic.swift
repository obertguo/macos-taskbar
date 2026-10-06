// Sources/TaskbarCore/Logic/WindowGroupingLogic.swift

import Foundation

/// Pure business logic for transforming an ordered list of `WindowInfo` into `[WindowGroup]`
/// based on the selected `WindowGroupingMode` and available geometry.
public enum WindowGroupingLogic {
    /// Groups windows according to the specified mode and horizontal width constraints.
    ///
    /// - Parameters:
    ///   - windows: The ordered collection of open windows.
    ///   - mode: The active grouping policy (`always`, `whenCrowded`, or `never`).
    ///   - availableWidth: The horizontal pixel width available for taskbar buttons.
    ///   - minButtonWidth: The minimum allowable width per button before overflow.
    ///   - buttonSpacing: The horizontal spacing between buttons.
    /// - Returns: An ordered array of `WindowGroup` items.
    public static func groupWindows(
        _ windows: [WindowInfo],
        mode: WindowGroupingMode,
        availableWidth: Double = 0,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing
    ) -> [WindowGroup] {
        guard !windows.isEmpty else { return [] }
        
        switch mode {
        case .never:
            return windows.map { WindowGroup.singleWindow($0) }
            
        case .always:
            return groupAllByApplication(windows)
            
        case .whenCrowded:
            let count = windows.count
            guard availableWidth > 0, count > 1 else {
                return windows.map { WindowGroup.singleWindow($0) }
            }
            
            let requiredUngroupedWidth = Double(count) * minButtonWidth + Double(count - 1) * buttonSpacing
            if requiredUngroupedWidth <= availableWidth {
                // Sufficient space; keep individual window buttons
                return windows.map { WindowGroup.singleWindow($0) }
            } else {
                // Crowded: aggregate multi-window applications to save space
                return groupAllByApplication(windows)
            }
        }
    }
    
    /// Groups windows by `bundleID`, preserving the order in which each application first appears.
    private static func groupAllByApplication(_ windows: [WindowInfo]) -> [WindowGroup] {
        var appOrder: [String] = []
        var appWindows: [String: [WindowInfo]] = [:]
        var appNames: [String: String] = [:]
        
        for win in windows {
            let bundleID = win.bundleID
            if appWindows[bundleID] == nil {
                appOrder.append(bundleID)
                appWindows[bundleID] = [win]
                appNames[bundleID] = win.appName
            } else {
                appWindows[bundleID]?.append(win)
            }
        }
        
        return appOrder.compactMap { bundleID in
            guard let wins = appWindows[bundleID], !wins.isEmpty else { return nil }
            let name = appNames[bundleID] ?? wins.first?.appName ?? TaskbarStrings.WindowGrouping.defaultAppName
            return WindowGroup.applicationGroup(
                bundleID: bundleID,
                appName: name,
                windows: wins
            )
        }
    }
}
