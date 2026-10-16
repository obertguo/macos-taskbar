// Sources/TaskbarKit/UI/Panels/BevelDrawing.swift

import AppKit
import TaskbarCore

public enum BevelDrawing {
    /// Draws a classic 3D raised border (Windows 95/2000 style button in normal state)
    public static func drawRaisedBevel(
        in rect: NSRect,
        highlight: NSColor = .white,
        shadow: NSColor = NSColor(white: 128.0 / 255.0, alpha: 1.0),
        darkShadow: NSColor = NSColor(white: 64.0 / 255.0, alpha: 1.0)
    ) {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        
        // Outer top and left: Highlight
        highlight.setStroke()
        let topPath = NSBezierPath()
        topPath.move(to: NSPoint(x: x, y: y))
        topPath.line(to: NSPoint(x: x, y: y + h))
        topPath.line(to: NSPoint(x: x + w - 1, y: y + h))
        topPath.lineWidth = 1.0
        topPath.stroke()
        
        // Outer bottom and right: Dark shadow
        darkShadow.setStroke()
        let bottomPath = NSBezierPath()
        bottomPath.move(to: NSPoint(x: x, y: y))
        bottomPath.line(to: NSPoint(x: x + w - 1, y: y))
        bottomPath.line(to: NSPoint(x: x + w - 1, y: y + h))
        bottomPath.lineWidth = 1.0
        bottomPath.stroke()
        
        // Inner bottom and right: Medium shadow
        shadow.setStroke()
        let innerBottomPath = NSBezierPath()
        innerBottomPath.move(to: NSPoint(x: x + 1, y: y + 1))
        innerBottomPath.line(to: NSPoint(x: x + w - 2, y: y + 1))
        innerBottomPath.line(to: NSPoint(x: x + w - 2, y: y + h - 1))
        innerBottomPath.lineWidth = 1.0
        innerBottomPath.stroke()
    }
    
    /// Draws a classic 3D sunken border (pressed button / active window state)
    public static func drawSunkenBevel(
        in rect: NSRect,
        darkShadow: NSColor = NSColor(white: 64.0 / 255.0, alpha: 1.0),
        shadow: NSColor = NSColor(white: 128.0 / 255.0, alpha: 1.0),
        highlight: NSColor = .white
    ) {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        
        // Outer top and left: Dark shadow
        darkShadow.setStroke()
        let topPath = NSBezierPath()
        topPath.move(to: NSPoint(x: x, y: y))
        topPath.line(to: NSPoint(x: x, y: y + h))
        topPath.line(to: NSPoint(x: x + w - 1, y: y + h))
        topPath.lineWidth = 1.0
        topPath.stroke()
        
        // Inner top and left: Medium shadow
        shadow.setStroke()
        let innerTopPath = NSBezierPath()
        innerTopPath.move(to: NSPoint(x: x + 1, y: y + 1))
        innerTopPath.line(to: NSPoint(x: x + 1, y: y + h - 1))
        innerTopPath.line(to: NSPoint(x: x + w - 2, y: y + h - 1))
        innerTopPath.lineWidth = 1.0
        innerTopPath.stroke()
        
        // Bottom and right: Highlight
        highlight.setStroke()
        let bottomPath = NSBezierPath()
        bottomPath.move(to: NSPoint(x: x, y: y))
        bottomPath.line(to: NSPoint(x: x + w - 1, y: y))
        bottomPath.line(to: NSPoint(x: x + w - 1, y: y + h))
        bottomPath.lineWidth = 1.0
        bottomPath.stroke()
    }
    
    /// Draws a classic 3D raised border using palette bevel colors with standard fallbacks
    public static func drawRaisedBevel(in rect: NSRect, palette: ThemePalette) {
        let highlight = palette.bevelHighlight.map(NSColor.init(rgba:)) ?? .white
        let shadow = palette.bevelShadow.map(NSColor.init(rgba:)) ?? NSColor(white: 128.0 / 255.0, alpha: 1.0)
        let darkShadow = palette.bevelDarkShadow.map(NSColor.init(rgba:)) ?? NSColor(white: 64.0 / 255.0, alpha: 1.0)
        drawRaisedBevel(in: rect, highlight: highlight, shadow: shadow, darkShadow: darkShadow)
    }
    
    /// Draws a classic 3D sunken border using palette bevel colors with standard fallbacks
    public static func drawSunkenBevel(in rect: NSRect, palette: ThemePalette) {
        let darkShadow = palette.bevelDarkShadow.map(NSColor.init(rgba:)) ?? NSColor(white: 64.0 / 255.0, alpha: 1.0)
        let shadow = palette.bevelShadow.map(NSColor.init(rgba:)) ?? NSColor(white: 128.0 / 255.0, alpha: 1.0)
        let highlight = palette.bevelHighlight.map(NSColor.init(rgba:)) ?? .white
        drawSunkenBevel(in: rect, darkShadow: darkShadow, shadow: shadow, highlight: highlight)
    }
    
    /// Draws a classic 3D raised border using precomputed `ResolvedTheme` colors
    @MainActor
    public static func drawRaisedBevel(in rect: NSRect, theme: ResolvedTheme) {
        drawRaisedBevel(in: rect, highlight: theme.bevelHighlight, shadow: theme.bevelShadow, darkShadow: theme.bevelDarkShadow)
    }
    
    /// Draws a classic 3D sunken border using precomputed `ResolvedTheme` colors
    @MainActor
    public static func drawSunkenBevel(in rect: NSRect, theme: ResolvedTheme) {
        drawSunkenBevel(in: rect, darkShadow: theme.bevelDarkShadow, shadow: theme.bevelShadow, highlight: theme.bevelHighlight)
    }
}
