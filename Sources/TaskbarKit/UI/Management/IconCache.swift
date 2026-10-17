// Sources/TaskbarKit/UI/Management/IconCache.swift

import AppKit

@MainActor
public final class IconCache {
    public static let shared = IconCache()
    
    public struct CacheKey: Hashable, Sendable {
        public let appKey: String
        public let width: Int
        public let height: Int
        
        public init(appKey: String, width: Int, height: Int) {
            self.appKey = appKey
            self.width = width
            self.height = height
        }
    }
    
    private var cache: [CacheKey: NSImage] = [:]
    private let fallbackIcon: NSImage
    
    private init() {
        let defaultImg = NSWorkspace.shared.icon(for: .application)
        self.fallbackIcon = Self.rasterize(Self.prepareIcon(defaultImg, targetSize: NSSize(width: 16, height: 16)), targetSize: NSSize(width: 16, height: 16))
    }
    
    public func icon(for bundleID: String, pid: pid_t, size: NSSize = NSSize(width: 16, height: 16)) -> NSImage {
        icon(for: bundleID, customPath: nil, pid: pid, size: size)
    }
    
    public func icon(
        for bundleID: String,
        customPath: String? = nil,
        pid: pid_t? = nil,
        size: NSSize = NSSize(width: 16, height: 16)
    ) -> NSImage {
        let appKey = !bundleID.isEmpty ? bundleID : (customPath ?? (pid != nil ? "pid:\(pid!)" : ""))
        let cacheKey = CacheKey(appKey: appKey, width: Int(size.width), height: Int(size.height))
        if !appKey.isEmpty, let cached = cache[cacheKey] {
            return cached
        }
        
        var resolvedIcon: NSImage?
        
        // 1. Resolve via running application bundle URL if PID is valid
        if let pid = pid, pid > 0,
           let app = NSRunningApplication(processIdentifier: pid),
           let bundleURL = app.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            resolvedIcon = Self.rasterize(Self.prepareIcon(icon, targetSize: size), targetSize: size)
        }
        
        // 2. Resolve via custom filesystem path if provided
        if resolvedIcon == nil, let path = customPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            resolvedIcon = Self.rasterize(Self.prepareIcon(icon, targetSize: size), targetSize: size)
        }
        
        // 3. Resolve via bundle ID URL
        if resolvedIcon == nil, !bundleID.isEmpty,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            resolvedIcon = Self.rasterize(Self.prepareIcon(icon, targetSize: size), targetSize: size)
        }
        
        // If resolution succeeded, cache and return
        if let resolved = resolvedIcon {
            if !appKey.isEmpty {
                cache[cacheKey] = resolved
            }
            return resolved
        }
        
        // Do not cache fallbackIcon permanently when NSRunningApplication returns nil during app startup
        return fallback(for: size)
    }
    
    private func fallback(for size: NSSize) -> NSImage {
        if size.width == 16 && size.height == 16 {
            return fallbackIcon
        }
        let defaultImg = NSWorkspace.shared.icon(for: .application)
        return Self.rasterize(Self.prepareIcon(defaultImg, targetSize: size), targetSize: size)
    }
    
    /// Prepares an application icon to ensure crisp rendering across all display scales (1x and 2x).
    ///
    /// Some application bundles contain corrupt or uninitialized legacy 1x bitmaps (< 64px)
    /// while having clean high-resolution representations. By filtering out representations below 64px
    /// when high-resolution representations exist, AppKit downsamples smoothly from high-resolution sources.
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
    
    /// Pre-rasterizes an icon to exact backing scale pixels to eliminate downsampling overhead in draw passes.
    public static func rasterize(_ sourceIcon: NSImage, targetSize: NSSize, scale: CGFloat? = nil) -> NSImage {
        let effectiveScale = scale ?? (NSScreen.main?.backingScaleFactor ?? 2.0)
        let pixelWidth = max(1, Int(targetSize.width * effectiveScale))
        let pixelHeight = max(1, Int(targetSize.height * effectiveScale))
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            guard let copy = sourceIcon.copy() as? NSImage else {
                sourceIcon.size = targetSize
                return sourceIcon
            }
            copy.size = targetSize
            return copy
        }
        
        rep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high
        sourceIcon.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        let rasterizedImage = NSImage(size: targetSize)
        rasterizedImage.addRepresentation(rep)
        return rasterizedImage
    }
    
    /// Evicts all cached icons for the specified bundle identifier.
    public func evict(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        cache = cache.filter { $0.key.appKey != bundleID }
    }
    
    /// Evicts all cached icons for the specified process identifier.
    public func evict(pid: pid_t) {
        guard pid > 0 else { return }
        let pidPrefix = "pid:\(pid)"
        cache = cache.filter { $0.key.appKey != pidPrefix }
    }
    
    /// Clears the entire icon cache.
    public func clearCache() {
        cache.removeAll()
    }
}
