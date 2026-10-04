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
        icon(for: bundleID, customPath: nil, pid: pid)
    }
    
    public func icon(
        for bundleID: String,
        customPath: String? = nil,
        pid: pid_t? = nil,
        size: NSSize = NSSize(width: 16, height: 16)
    ) -> NSImage {
        let cacheKey = !bundleID.isEmpty ? bundleID : (customPath ?? "")
        if let cached = cache[cacheKey], !cacheKey.isEmpty {
            return cached
        }
        
        var resolvedIcon: NSImage?
        
        // 1. Resolve via running application bundle URL if PID is valid
        if let pid = pid, pid > 0,
           let app = NSRunningApplication(processIdentifier: pid),
           let bundleURL = app.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            icon.size = size
            resolvedIcon = icon
        }
        
        // 2. Resolve via custom filesystem path if provided
        if resolvedIcon == nil, let path = customPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = size
            resolvedIcon = icon
        }
        
        // 3. Resolve via bundle ID URL
        if resolvedIcon == nil, !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = size
            resolvedIcon = icon
        }
        
        let finalIcon = resolvedIcon ?? fallbackIcon
        if !cacheKey.isEmpty {
            cache[cacheKey] = finalIcon
        }
        return finalIcon
    }
    
    /// Clears the icon cache.
    public func clearCache() {
        cache.removeAll()
    }
}
