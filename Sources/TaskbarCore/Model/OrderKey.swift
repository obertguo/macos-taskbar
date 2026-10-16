// Sources/TaskbarCore/Model/OrderKey.swift

import Foundation

extension WindowKey: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case pid
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UInt64.self, forKey: .id)
        let pid = try container.decode(pid_t.self, forKey: .pid)
        self.init(id: id, pid: pid)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pid, forKey: .pid)
    }
}

/// A type-safe identifier for custom taskbar item ordering, distinguishing between
/// individual window keys and application-level grouping keys.
public enum OrderKey: Hashable, Sendable, Codable, CustomStringConvertible {
    case window(WindowKey)
    case app(String) // bundleID
    
    public var stringRepresentation: String {
        switch self {
        case let .window(key):
            return "win:\(key.pid):\(key.id)"
        case let .app(bundleID):
            return "app:\(bundleID)"
        }
    }
    
    public var description: String {
        stringRepresentation
    }
}
