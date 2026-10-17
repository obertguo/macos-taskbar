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
        
        // If the owning application is frontmost and this specific window is currently focused,
        // clicking the taskbar button minimizes it (standard taskbar toggle behavior).
        if isFrontmostApp {
            if let focusedKey = focusedKey {
                if focusedKey == window.key {
                    return .minimize
                }
            } else if window.isMain {
                return .minimize
            }
        }
        
        return .focus
    }
}
