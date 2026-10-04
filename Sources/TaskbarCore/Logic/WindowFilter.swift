// Sources/TaskbarCore/Logic/WindowFilter.swift

import Foundation
import CoreGraphics

public enum WindowFilter {
    /// Determines whether a window candidate meets the criteria to be displayed on the taskbar.
    public static func shouldInclude(
        role: String,
        subrole: String?,
        frame: CGRect,
        bundleID: String,
        isAppRegular: Bool,
        isMinimized: Bool = false
    ) -> Bool {
        // 1. Must belong to a regular GUI application
        guard isAppRegular else { return false }
        
        // 2. Ignore self and system overlays
        if bundleID == BuildConfiguration.bundleID || TaskbarConstants.Accessibility.ignoredSystemBundleIDs.contains(bundleID) {
            return false
        }
        
        // 3. Role must be an AXWindow
        guard role == TaskbarConstants.Accessibility.windowRole else { return false }
        
        // 4. Reject modal dialogs, sheets, palettes, and popovers
        if let subrole = subrole, TaskbarConstants.Accessibility.rejectedSubroles.contains(subrole) {
            return false
        }
        
        // 5. Minimized windows are preserved regardless of frame size (docked windows shrink to 0x0)
        if isMinimized {
            return true
        }
        
        // 6. Must have visible non-zero dimensions (filters out invisible tracking windows)
        let minDim = TaskbarConstants.WorkArea.minimumWindowDimension
        guard frame.width >= minDim && frame.height >= minDim else {
            return false
        }
        
        return true
    }
}
