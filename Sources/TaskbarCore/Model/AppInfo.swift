// Sources/TaskbarCore/Model/AppInfo.swift

import Foundation

public struct AppInfo: Equatable, Sendable, Identifiable {
    public let pid: pid_t
    public let name: String
    public let bundleID: String
    public var isHidden: Bool
    
    public var id: pid_t { pid }
    
    public init(pid: pid_t, name: String, bundleID: String, isHidden: Bool = false) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.isHidden = isHidden
    }
}
