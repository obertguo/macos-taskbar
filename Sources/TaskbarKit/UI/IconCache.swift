// Sources/TaskbarKit/UI/IconCache.swift

import AppKit

@MainActor
public final class IconCache {
    public static let shared = IconCache()
    
    private var cache: [String: NSImage] = [:]
    private let fallbackIcon: NSImage
    
    private init() {
        let defaultImg = NSWorkspace.shared.icon(for: .application)
        self.fallbackIcon = Self.prepareIcon(defaultImg, targetSize: NSSize(width: 16, height: 16))
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
        let baseKey = !bundleID.isEmpty ? bundleID : (customPath ?? "")
        let cacheKey = baseKey.isEmpty ? "" : "\(baseKey)_\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[cacheKey], !cacheKey.isEmpty {
            return cached
        }
        
        var resolvedIcon: NSImage?
        
        // 1. Resolve via running application bundle URL if PID is valid
        if let pid = pid, pid > 0,
           let app = NSRunningApplication(processIdentifier: pid),
           let bundleURL = app.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            resolvedIcon = Self.prepareIcon(icon, targetSize: size)
        }
        
        // 2. Resolve via custom filesystem path if provided
        if resolvedIcon == nil, let path = customPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            resolvedIcon = Self.prepareIcon(icon, targetSize: size)
        }
        
        // 3. Resolve via bundle ID URL
        if resolvedIcon == nil, !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            resolvedIcon = Self.prepareIcon(icon, targetSize: size)
        }
        
        let finalIcon = resolvedIcon ?? fallbackIcon
        if !cacheKey.isEmpty {
            cache[cacheKey] = finalIcon
        }
        return finalIcon
    }
    
    /// Prepares an application icon to ensure crisp rendering across all display scales (1x and 2x).
    ///
    /// Some application bundles (such as Antigravity / Electron apps) contain corrupt or uninitialized
    /// legacy 1x bitmaps (e.g. 16x16 or 32x32) inside their `.icns` asset while having clean high-resolution
    /// representations (64px, 128px, 256px, etc.). By filtering out representations below 64px when high-resolution
    /// representations exist, AppKit's rendering engine automatically and smoothly downsamples from the clean
    /// high-resolution source for non-Retina (1x) displays, eliminating noise/glitches.
    public static func prepareIcon(_ rawIcon: NSImage, targetSize: NSSize) -> NSImage {
        let reps = rawIcon.representations
        let hasHighRes = reps.contains { $0.pixelsWide >= 64 }
        
        if hasHighRes {
            let cleanImage = NSImage(size: targetSize)
            for rep in reps where rep.pixelsWide >= 64 {
                cleanImage.addRepresentation(rep)
            }
            return cleanImage
        } else {
            guard let copy = rawIcon.copy() as? NSImage else {
                rawIcon.size = targetSize
                return rawIcon
            }
            copy.size = targetSize
            return copy
        }
    }
    
    /// Clears the icon cache.
    public func clearCache() {
        cache.removeAll()
    }
}
