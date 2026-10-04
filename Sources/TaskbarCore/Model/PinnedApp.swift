// Sources/TaskbarCore/Model/PinnedApp.swift

import Foundation

/// Represents a pinned application shortcut displayed on the taskbar quick launch bar.
public struct PinnedApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Unique identifier for this pinned shortcut entry.
    public let id: UUID
    
    /// The application bundle identifier (e.g. "com.apple.finder").
    public let bundleIdentifier: String
    
    /// User-visible display name for tooltips and accessibility labels.
    public var displayName: String
    
    /// Optional filesystem path to the app bundle if located outside `/Applications` or `/System/Applications`.
    public var customPath: String?
    
    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        customPath: String? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.customPath = customPath
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, displayName, customPath
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? bundleIdentifier
        self.customPath = try container.decodeIfPresent(String.self, forKey: .customPath)
    }
}

extension PinnedApp {
    /// Default set of pinned applications for clean taskbar installations.
    public static let defaultPinnedApps: [PinnedApp] = [
        PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder"),
        PinnedApp(bundleIdentifier: "com.apple.Safari", displayName: "Safari"),
        PinnedApp(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")
    ]
}
