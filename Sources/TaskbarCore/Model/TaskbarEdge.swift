// Sources/TaskbarCore/Model/TaskbarEdge.swift

import Foundation

/// Defines the screen edge where the taskbar is anchored.
public enum TaskbarEdge: String, CaseIterable, Codable, Sendable {
    case bottom
    case top
    case left
    case right
    
    /// Returns `true` if the taskbar is positioned along a horizontal edge (bottom or top).
    public var isHorizontal: Bool {
        self == .bottom || self == .top
    }
    
    /// Returns `true` if the taskbar is positioned along a vertical edge (left or right).
    public var isVertical: Bool {
        self == .left || self == .right
    }
}
