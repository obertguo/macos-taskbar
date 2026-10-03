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
        
        if isFrontmostApp && focusedKey == window.key {
            return .minimize
        }
        
        return .focus
    }
}
