// Sources/TaskbarApp/UI/IconCache.swift

import AppKit

@MainActor
public final class IconCache {
    public static let shared = IconCache()
    
    private var cache: [String: NSImage] = [:]
    private let fallbackIcon: NSImage
    
    private init() {
        let defaultImg = NSWorkspace.shared.icon(for: .application)
        defaultImg.size = NSSize(width: 16, height: 16)
        self.fallbackIcon = defaultImg
    }
    
    public func icon(for bundleID: String, pid: pid_t) -> NSImage {
        if let cached = cache[bundleID], !bundleID.isEmpty {
            return cached
        }
        
        var resolvedIcon: NSImage?
        
        // 1. Resolve via running application bundle URL
        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleURL = app.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = NSSize(width: 16, height: 16)
            resolvedIcon = icon
        }
        
        // 2. Resolve via bundle ID URL
        if resolvedIcon == nil, !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            resolvedIcon = icon
        }
        
        let finalIcon = resolvedIcon ?? fallbackIcon
        if !bundleID.isEmpty {
            cache[bundleID] = finalIcon
        }
        return finalIcon
    }
}
