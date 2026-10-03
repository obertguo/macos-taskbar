// Sources/TaskbarCore/Logic/ClickPolicy.swift

import Foundation

public enum ClickAction: Equatable, Sendable {
    case focus
    case minimize
    case restoreAndFocus
}

public enum ClickPolicy {
    /// Determines the action to take when the user left-clicks a taskbar button.
    public static func leftClickAction(
        for window: WindowInfo,
        focusedKey: WindowKey?,
        isFrontmostApp: Bool
    ) -> ClickAction {
        if window.isMinimized || window.isAppHidden {
            return .restoreAndFocus
        }
        
        // If the owning application is frontmost, clicking the window minimizes it if:
        // 1. It matches the focused window key, OR
        // 2. It is marked as the app's main window (kAXMainAttribute), OR
        // 3. No specific focused key was resolved (Chromium/Electron apps often report nil for focusedWindow)
        if isFrontmostApp {
            if focusedKey == window.key || window.isMain || focusedKey == nil {
                return .minimize
            }
        }
        
        return .focus
    }
}
