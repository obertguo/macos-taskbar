// Sources/TaskbarCore/Config/Theme.swift

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
    
    public static let white = RGBAColor(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = RGBAColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let clear = RGBAColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
    
    // Retro Windows classic palette
    public static let retroGray = RGBAColor(red: 192.0 / 255.0, green: 192.0 / 255.0, blue: 192.0 / 255.0)
    public static let retroLightGray = RGBAColor(red: 220.0 / 255.0, green: 220.0 / 255.0, blue: 220.0 / 255.0)
    public static let retroShadow = RGBAColor(red: 128.0 / 255.0, green: 128.0 / 255.0, blue: 128.0 / 255.0)
    public static let retroDarkShadow = RGBAColor(red: 64.0 / 255.0, green: 64.0 / 255.0, blue: 64.0 / 255.0)
    public static let retroNavy = RGBAColor(red: 0.0, green: 0.0, blue: 128.0 / 255.0)
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
        bevelDarkShadow: RGBAColor? = nil
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
    }
}

public struct ThemeMetrics: Codable, Equatable, Sendable {
    public let buttonCornerRadius: Double
    public let is3DBeveled: Bool
    public let fontBold: Bool
    public let fontSize: Double
    public let iconSize: Double

    public init(
        buttonCornerRadius: Double,
        is3DBeveled: Bool,
        fontBold: Bool,
        fontSize: Double = TaskbarConstants.Layout.defaultFontSize,
        iconSize: Double = TaskbarConstants.Layout.defaultIconSize
    ) {
        self.buttonCornerRadius = buttonCornerRadius
        self.is3DBeveled = is3DBeveled
        self.fontBold = fontBold
        self.fontSize = fontSize
        self.iconSize = iconSize
    }
}

public struct ThemeMaterials: Codable, Equatable, Sendable {
    public let useTranslucency: Bool

    public init(useTranslucency: Bool) {
        self.useTranslucency = useTranslucency
    }
}

public struct ThemeDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let isCustom: Bool
    public let palette: ThemePalette
    public let metrics: ThemeMetrics
    public let materials: ThemeMaterials
    
    // Legacy & convenience accessors for seamless AppKit view consumption
    public var style: ThemeStyle {
        (id == ThemeDefinition.retroClassic.id) ? .retroClassic : .modernHybrid
    }
    public var useTranslucency: Bool { materials.useTranslucency }
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
            iconSize: iconSize
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
    
    // Built-in Static Presets
    public static let modernHybrid = ThemeDefinition(
        id: "modern-hybrid",
        displayName: TaskbarStrings.Themes.modernHybrid,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: .clear,
            topBorderColor: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15),
            textNormal: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95),
            textPressed: .white,
            buttonNormal: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08),
            buttonHover: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16),
            buttonPressed: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28),
            buttonBorderNormal: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12),
            buttonBorderPressed: RGBAColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.6)
        ),
        metrics: ThemeMetrics(
            buttonCornerRadius: 4.0,
            is3DBeveled: false,
            fontBold: false,
            fontSize: TaskbarConstants.Layout.defaultFontSize,
            iconSize: TaskbarConstants.Layout.defaultIconSize
        ),
        materials: ThemeMaterials(useTranslucency: true)
    )

    public static let retroClassic = ThemeDefinition(
        id: "retro-classic",
        displayName: TaskbarStrings.Themes.retroClassic,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: .retroGray,
            topBorderColor: .white,
            textNormal: .black,
            textPressed: .black,
            buttonNormal: .retroGray,
            buttonHover: .retroGray,
            buttonPressed: .retroLightGray,
            buttonBorderNormal: .retroDarkShadow,
            buttonBorderPressed: .black,
            bevelHighlight: .white,
            bevelShadow: .retroShadow,
            bevelDarkShadow: .retroDarkShadow
        ),
        metrics: ThemeMetrics(
            buttonCornerRadius: 0.0,
            is3DBeveled: true,
            fontBold: true,
            fontSize: TaskbarConstants.Layout.defaultFontSize,
            iconSize: TaskbarConstants.Layout.defaultIconSize
        ),
        materials: ThemeMaterials(useTranslucency: false)
    )
    
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
        }
    }
}
