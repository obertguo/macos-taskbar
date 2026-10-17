// Sources/TaskbarCore/Config/Theme/ThemeDefinition.swift

import Foundation

public struct RGBAColor: Equatable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    private enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.red = try container.decode(Double.self, forKey: .red)
        self.green = try container.decode(Double.self, forKey: .green)
        self.blue = try container.decode(Double.self, forKey: .blue)
        self.alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1.0
    }
    
    public static let white = RGBAColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = RGBAColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let clear = RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
}

public struct ThemePalette: Codable, Equatable, Sendable {
    public let backgroundColor: RGBAColor
    public let topBorderColor: RGBAColor?
    public let textNormal: RGBAColor
    public let textPressed: RGBAColor
    public let buttonNormal: RGBAColor
    public let buttonHover: RGBAColor
    public let buttonPressed: RGBAColor
    public let buttonBorderNormal: RGBAColor
    public let buttonBorderPressed: RGBAColor
    public let bevelHighlight: RGBAColor?
    public let bevelShadow: RGBAColor?
    public let bevelDarkShadow: RGBAColor?
    public let startButtonNormal: RGBAColor?
    public let startButtonHover: RGBAColor?
    public let startButtonPressed: RGBAColor?
    public let startButtonText: RGBAColor?

    public init(
        backgroundColor: RGBAColor,
        topBorderColor: RGBAColor? = nil,
        textNormal: RGBAColor,
        textPressed: RGBAColor,
        buttonNormal: RGBAColor,
        buttonHover: RGBAColor,
        buttonPressed: RGBAColor,
        buttonBorderNormal: RGBAColor,
        buttonBorderPressed: RGBAColor,
        bevelHighlight: RGBAColor? = nil,
        bevelShadow: RGBAColor? = nil,
        bevelDarkShadow: RGBAColor? = nil,
        startButtonNormal: RGBAColor? = nil,
        startButtonHover: RGBAColor? = nil,
        startButtonPressed: RGBAColor? = nil,
        startButtonText: RGBAColor? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.topBorderColor = topBorderColor
        self.textNormal = textNormal
        self.textPressed = textPressed
        self.buttonNormal = buttonNormal
        self.buttonHover = buttonHover
        self.buttonPressed = buttonPressed
        self.buttonBorderNormal = buttonBorderNormal
        self.buttonBorderPressed = buttonBorderPressed
        self.bevelHighlight = bevelHighlight
        self.bevelShadow = bevelShadow
        self.bevelDarkShadow = bevelDarkShadow
        self.startButtonNormal = startButtonNormal
        self.startButtonHover = startButtonHover
        self.startButtonPressed = startButtonPressed
        self.startButtonText = startButtonText
    }
}

public struct ThemeMetrics: Codable, Equatable, Sendable {
    public let buttonCornerRadius: Double
    public let is3DBeveled: Bool
    public let fontBold: Bool
    public let fontSize: Double
    public let iconSize: Double
    public let barHeight: Double?
    public let minButtonWidth: Double?
    public let maxButtonWidth: Double?
    public let buttonSpacing: Double?

    public init(
        buttonCornerRadius: Double = 4.0,
        is3DBeveled: Bool = false,
        fontBold: Bool = false,
        fontSize: Double = TaskbarConstants.Layout.defaultFontSize,
        iconSize: Double = TaskbarConstants.Layout.defaultIconSize,
        barHeight: Double? = nil,
        minButtonWidth: Double? = nil,
        maxButtonWidth: Double? = nil,
        buttonSpacing: Double? = nil
    ) {
        self.buttonCornerRadius = buttonCornerRadius
        self.is3DBeveled = is3DBeveled
        self.fontBold = fontBold
        self.fontSize = fontSize
        self.iconSize = iconSize
        self.barHeight = barHeight
        self.minButtonWidth = minButtonWidth
        self.maxButtonWidth = maxButtonWidth
        self.buttonSpacing = buttonSpacing
    }
    
    private enum CodingKeys: String, CodingKey {
        case buttonCornerRadius, is3DBeveled, fontBold, fontSize, iconSize
        case barHeight, minButtonWidth, maxButtonWidth, buttonSpacing
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.buttonCornerRadius = try container.decodeIfPresent(Double.self, forKey: .buttonCornerRadius) ?? 4.0
        self.is3DBeveled = try container.decodeIfPresent(Bool.self, forKey: .is3DBeveled) ?? false
        self.fontBold = try container.decodeIfPresent(Bool.self, forKey: .fontBold) ?? false
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? TaskbarConstants.Layout.defaultFontSize
        self.iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? TaskbarConstants.Layout.defaultIconSize
        self.barHeight = try container.decodeIfPresent(Double.self, forKey: .barHeight)
        self.minButtonWidth = try container.decodeIfPresent(Double.self, forKey: .minButtonWidth)
        self.maxButtonWidth = try container.decodeIfPresent(Double.self, forKey: .maxButtonWidth)
        self.buttonSpacing = try container.decodeIfPresent(Double.self, forKey: .buttonSpacing)
    }
}

public struct ThemeMaterials: Codable, Equatable, Sendable {
    public let useTranslucency: Bool
    public let material: String?
    public let blendingMode: String?

    public init(
        useTranslucency: Bool = true,
        material: String? = nil,
        blendingMode: String? = nil
    ) {
        self.useTranslucency = useTranslucency
        self.material = material
        self.blendingMode = blendingMode
    }
    
    private enum CodingKeys: String, CodingKey {
        case useTranslucency, material, blendingMode
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.useTranslucency = try container.decodeIfPresent(Bool.self, forKey: .useTranslucency) ?? true
        self.material = try container.decodeIfPresent(String.self, forKey: .material)
        self.blendingMode = try container.decodeIfPresent(String.self, forKey: .blendingMode)
    }
}

public struct ThemeDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let isCustom: Bool
    public let palette: ThemePalette
    public let metrics: ThemeMetrics
    public let materials: ThemeMaterials
    
    private enum CodingKeys: String, CodingKey {
        case id, displayName, isCustom, palette, metrics, materials
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? self.id
        self.isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? true
        self.palette = try container.decode(ThemePalette.self, forKey: .palette)
        self.metrics = try container.decodeIfPresent(ThemeMetrics.self, forKey: .metrics) ?? ThemeMetrics()
        self.materials = try container.decodeIfPresent(ThemeMaterials.self, forKey: .materials) ?? ThemeMaterials()
    }
    
    public func asCustom(_ isCustom: Bool = true, id: String? = nil, displayName: String? = nil) -> ThemeDefinition {
        let finalId = (id ?? self.id).trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDisplayName = (displayName ?? self.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        return ThemeDefinition(
            id: finalId,
            displayName: finalDisplayName,
            isCustom: isCustom,
            palette: palette,
            metrics: metrics,
            materials: materials
        )
    }
    
    // Style enum mapping for backward compatibility and fast categorization
    public var style: ThemeStyle {
        switch id {
        case RetroClassicTheme.id: return .retroClassic
        case WindowsXPLunaTheme.id: return .windowsXPLuna
        case DarkMinimalTheme.id: return .darkMinimal
        default: return .modernHybrid
        }
    }
    
    // Convenience token accessors
    public var useTranslucency: Bool { materials.useTranslucency }
    public var material: String? { materials.material }
    public var blendingMode: String? { materials.blendingMode }
    public var backgroundColor: RGBAColor { palette.backgroundColor }
    public var topBorderColor: RGBAColor? { palette.topBorderColor }
    public var buttonCornerRadius: Double { metrics.buttonCornerRadius }
    public var is3DBeveled: Bool { metrics.is3DBeveled }
    public var buttonNormalBackground: RGBAColor { palette.buttonNormal }
    public var buttonHoverBackground: RGBAColor { palette.buttonHover }
    public var buttonPressedBackground: RGBAColor { palette.buttonPressed }
    public var buttonBorderNormal: RGBAColor { palette.buttonBorderNormal }
    public var buttonBorderPressed: RGBAColor { palette.buttonBorderPressed }
    public var bevelHighlight: RGBAColor? { palette.bevelHighlight }
    public var bevelShadow: RGBAColor? { palette.bevelShadow }
    public var bevelDarkShadow: RGBAColor? { palette.bevelDarkShadow }
    public var textColor: RGBAColor { palette.textNormal }
    public var textPressedColor: RGBAColor { palette.textPressed }
    public var fontBold: Bool { metrics.fontBold }
    public var fontSize: Double { metrics.fontSize }
    public var iconSize: Double { metrics.iconSize }
    
    public init(
        id: String,
        displayName: String,
        isCustom: Bool = false,
        palette: ThemePalette,
        metrics: ThemeMetrics,
        materials: ThemeMaterials
    ) {
        self.id = id
        self.displayName = displayName
        self.isCustom = isCustom
        self.palette = palette
        self.metrics = metrics
        self.materials = materials
    }
    
    /// Creates a customized copy of this theme with modified typography or icon dimensions.
    public func withCustomMetrics(fontSize: Double, iconSize: Double) -> ThemeDefinition {
        let updatedMetrics = ThemeMetrics(
            buttonCornerRadius: metrics.buttonCornerRadius,
            is3DBeveled: metrics.is3DBeveled,
            fontBold: metrics.fontBold,
            fontSize: fontSize,
            iconSize: iconSize,
            barHeight: metrics.barHeight,
            minButtonWidth: metrics.minButtonWidth,
            maxButtonWidth: metrics.maxButtonWidth,
            buttonSpacing: metrics.buttonSpacing
        )
        return ThemeDefinition(
            id: id,
            displayName: displayName,
            isCustom: isCustom,
            palette: palette,
            metrics: updatedMetrics,
            materials: materials
        )
    }
    
    // Static Built-in Presets
    public static var modernHybrid: ThemeDefinition {
        ModernHybridTheme.definition
    }

    public static var retroClassic: ThemeDefinition {
        RetroClassicTheme.definition
    }

    public static var windowsXPLuna: ThemeDefinition {
        WindowsXPLunaTheme.definition
    }

    public static var darkMinimal: ThemeDefinition {
        DarkMinimalTheme.definition
    }
    
    /// Factory helper mapping style string/id to definition.
    public static func forStyle(
        _ style: ThemeStyle,
        fontSize: Double = TaskbarConstants.Layout.defaultFontSize,
        iconSize: Double = TaskbarConstants.Layout.defaultIconSize
    ) -> ThemeDefinition {
        switch style {
        case .modernHybrid:
            return modernHybrid.withCustomMetrics(fontSize: fontSize, iconSize: iconSize)
        case .retroClassic:
            return retroClassic.withCustomMetrics(fontSize: fontSize, iconSize: iconSize)
        case .windowsXPLuna:
            return windowsXPLuna.withCustomMetrics(fontSize: fontSize, iconSize: iconSize)
        case .darkMinimal:
            return darkMinimal.withCustomMetrics(fontSize: fontSize, iconSize: iconSize)
        }
    }
}
