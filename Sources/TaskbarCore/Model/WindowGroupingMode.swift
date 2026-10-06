// Sources/TaskbarCore/Model/WindowGroupingMode.swift

import Foundation

/// Defines how multiple windows belonging to the same application are grouped on the taskbar.
public enum WindowGroupingMode: String, Codable, CaseIterable, Sendable {
    /// Always group multiple windows of the same application into a single button.
    case always = "always"
    
    /// Group multiple windows only when the taskbar is crowded (insufficient width for all windows).
    case whenCrowded = "whenCrowded"
    
    /// Never group windows; every window always has its own separate taskbar button.
    case never = "never"
    
    public var displayName: String {
        switch self {
        case .always: return TaskbarStrings.WindowGrouping.modeAlwaysShort
        case .whenCrowded: return TaskbarStrings.WindowGrouping.modeWhenCrowdedShort
        case .never: return TaskbarStrings.WindowGrouping.modeNeverShort
        }
    }
}
