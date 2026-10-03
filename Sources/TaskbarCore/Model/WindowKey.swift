// Sources/TaskbarCore/Model/WindowKey.swift

import Foundation

public struct WindowKey: Hashable, Equatable, Sendable, CustomStringConvertible {
    public let id: UInt64
    public let pid: pid_t
    
    public init(id: UInt64, pid: pid_t) {
        self.id = id
        self.pid = pid
    }
    
    public var description: String {
        "WindowKey(pid: \(pid), id: \(id))"
    }
}
