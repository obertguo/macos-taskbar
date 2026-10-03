// Sources/TaskbarCore/Model/WindowInfo.swift

import Foundation
import CoreGraphics

public struct WindowInfo: Equatable, Sendable, Identifiable {
    public let key: WindowKey
    public let pid: pid_t
    public let appName: String
    public let bundleID: String
    public var title: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isMain: Bool
    public var isFullScreen: Bool
    public var openOrder: UInt64
    
    public var id: WindowKey { key }
    
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }
    
    public init(
        key: WindowKey,
        pid: pid_t,
        appName: String,
        bundleID: String,
        title: String,
        frame: CGRect,
        isMinimized: Bool = false,
        isAppHidden: Bool = false,
        isMain: Bool = false,
        isFullScreen: Bool = false,
        openOrder: UInt64 = 0
    ) {
        self.key = key
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isMain = isMain
        self.isFullScreen = isFullScreen
        self.openOrder = openOrder
    }
}
