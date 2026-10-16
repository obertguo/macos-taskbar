// Sources/TaskbarKit/UI/Panels/ResolvedTheme.swift

import AppKit
import TaskbarCore

/// Precomputed AppKit resources (colors, fonts, paragraph styles, text attribute dictionaries)
/// for a given `ThemeDefinition`. Caches expensive objects to eliminate allocations inside `draw(_:)`.
@MainActor
public final class ResolvedTheme: Equatable {
    nonisolated public let theme: ThemeDefinition
    
    // MARK: - Colors
    public let backgroundColor: NSColor
    public let buttonNormalBackground: NSColor
    public let buttonHoverBackground: NSColor
    public let buttonPressedBackground: NSColor
    public let buttonBorderNormal: NSColor
    public let buttonBorderPressed: NSColor
    public let textColor: NSColor
    public let textPressedColor: NSColor
    public let bevelHighlight: NSColor
    public let bevelShadow: NSColor
    public let bevelDarkShadow: NSColor
    public let startButtonNormal: NSColor
    public let startButtonHover: NSColor
    public let startButtonPressed: NSColor
    public let startButtonText: NSColor
    
    // MARK: - Fonts & Metrics
    public let buttonFont: NSFont
    public let fontBold: NSFont
    public let boldFont: NSFont
    public let regularFont: NSFont
    public let mediumFont: NSFont
    public let semiboldFont: NSFont
    public let fontSize: CGFloat
    
    // MARK: - Paragraph Styles & Text Attributes
    public let paragraphStyle: NSParagraphStyle
    public let normalTextAttributes: [NSAttributedString.Key: Any]
    public let pressedTextAttributes: [NSAttributedString.Key: Any]
    public let boldTextAttributes: [NSAttributedString.Key: Any]
    public let boldPressedTextAttributes: [NSAttributedString.Key: Any]
    public let semiboldTextAttributes: [NSAttributedString.Key: Any]
    public let semiboldPressedTextAttributes: [NSAttributedString.Key: Any]
    public let startButtonTextAttributes: [NSAttributedString.Key: Any]
    
    // MARK: - Layout Precomputations
    public let startButtonPreferredWidth: CGFloat
    
    // MARK: - Cache
    private static var cache: [String: ResolvedTheme] = [:]
    
    public init(theme: ThemeDefinition) {
        self.theme = theme
        
        // Colors
        self.backgroundColor = NSColor(rgba: theme.backgroundColor)
        self.buttonNormalBackground = NSColor(rgba: theme.buttonNormalBackground)
        self.buttonHoverBackground = NSColor(rgba: theme.buttonHoverBackground)
        self.buttonPressedBackground = NSColor(rgba: theme.buttonPressedBackground)
        self.buttonBorderNormal = NSColor(rgba: theme.buttonBorderNormal)
        self.buttonBorderPressed = NSColor(rgba: theme.buttonBorderPressed)
        self.textColor = NSColor(rgba: theme.textColor)
        self.textPressedColor = NSColor(rgba: theme.textPressedColor)
        
        self.bevelHighlight = theme.palette.bevelHighlight.map(NSColor.init(rgba:)) ?? .white
        self.bevelShadow = theme.palette.bevelShadow.map(NSColor.init(rgba:)) ?? NSColor(white: 128.0 / 255.0, alpha: 1.0)
        self.bevelDarkShadow = theme.palette.bevelDarkShadow.map(NSColor.init(rgba:)) ?? NSColor(white: 64.0 / 255.0, alpha: 1.0)
        
        let sbNormal = theme.palette.startButtonNormal ?? theme.buttonNormalBackground
        self.startButtonNormal = NSColor(rgba: sbNormal)
        
        let sbHover = theme.palette.startButtonHover ?? theme.buttonHoverBackground
        self.startButtonHover = NSColor(rgba: sbHover)
        
        let sbPressed = theme.palette.startButtonPressed ?? theme.buttonPressedBackground
        self.startButtonPressed = NSColor(rgba: sbPressed)
        
        let sbText = theme.palette.startButtonText ?? theme.textColor
        self.startButtonText = NSColor(rgba: sbText)
        
        // Fonts
        let fSize = CGFloat(theme.fontSize)
        self.fontSize = fSize
        self.regularFont = NSFont.systemFont(ofSize: fSize, weight: .regular)
        self.mediumFont = NSFont.systemFont(ofSize: fSize, weight: .medium)
        self.semiboldFont = NSFont.systemFont(ofSize: fSize, weight: .semibold)
        let bold = NSFont.systemFont(ofSize: fSize, weight: .bold)
        self.fontBold = bold
        self.boldFont = bold
        
        let buttonWeight: NSFont.Weight = theme.fontBold ? .bold : (theme.is3DBeveled ? .regular : .medium)
        self.buttonFont = NSFont.systemFont(ofSize: fSize, weight: buttonWeight)
        
        // Paragraph style
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        self.paragraphStyle = para
        
        // Text attribute dictionaries
        self.normalTextAttributes = [
            .font: self.buttonFont,
            .foregroundColor: self.textColor,
            .paragraphStyle: para
        ]
        self.pressedTextAttributes = [
            .font: self.buttonFont,
            .foregroundColor: self.textPressedColor,
            .paragraphStyle: para
        ]
        self.boldTextAttributes = [
            .font: bold,
            .foregroundColor: self.textColor,
            .paragraphStyle: para
        ]
        self.boldPressedTextAttributes = [
            .font: bold,
            .foregroundColor: self.textPressedColor,
            .paragraphStyle: para
        ]
        self.semiboldTextAttributes = [
            .font: self.semiboldFont,
            .foregroundColor: self.textColor,
            .paragraphStyle: para
        ]
        self.semiboldPressedTextAttributes = [
            .font: self.semiboldFont,
            .foregroundColor: self.textPressedColor,
            .paragraphStyle: para
        ]
        
        let startFontWeight: NSFont.Weight = theme.fontBold ? .bold : (theme.is3DBeveled ? .bold : .medium)
        let startFont = NSFont.systemFont(ofSize: fSize, weight: startFontWeight)
        self.startButtonTextAttributes = [
            .font: startFont,
            .foregroundColor: self.startButtonText,
            .paragraphStyle: para
        ]
        
        // Pre-calculated Start button width
        let startWidthWeight: NSFont.Weight = theme.is3DBeveled ? .bold : .medium
        let startWidthFont = NSFont.systemFont(ofSize: fSize, weight: startWidthWeight)
        let textWidth = (TaskbarStrings.StartButton.title as NSString).size(withAttributes: [.font: startWidthFont]).width
        let iconWidth: CGFloat = theme.is3DBeveled ? 13.0 : 10.0
        let baseMin = theme.is3DBeveled
            ? TaskbarConstants.Layout.startButtonWidthRetro
            : TaskbarConstants.Layout.startButtonWidthHybrid
        let padding: CGFloat = theme.is3DBeveled ? 17.0 : 24.0
        self.startButtonPreferredWidth = max(baseMin, ceil(textWidth + iconWidth + padding))
    }
    
    /// Resolves and returns the cached `ResolvedTheme` matching `theme`, creating it if absent or changed.
    public static func resolve(_ theme: ThemeDefinition) -> ResolvedTheme {
        if let cached = cache[theme.id], cached.theme == theme {
            return cached
        }
        let resolved = ResolvedTheme(theme: theme)
        cache[theme.id] = resolved
        return resolved
    }
    
    /// Purges the resolved theme cache.
    public static func clearCache() {
        cache.removeAll()
    }
    
    // MARK: - Equatable
    nonisolated public static func == (lhs: ResolvedTheme, rhs: ResolvedTheme) -> Bool {
        lhs.theme == rhs.theme
    }
}
