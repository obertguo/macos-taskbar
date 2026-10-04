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

public struct ThemeDefinition: Equatable, Sendable {
    public let style: ThemeStyle
    public let useTranslucency: Bool
    public let backgroundColor: RGBAColor
    public let topBorderColor: RGBAColor?
    
    // Button styling
    public let buttonCornerRadius: Double
    public let is3DBeveled: Bool
    public let buttonNormalBackground: RGBAColor
    public let buttonHoverBackground: RGBAColor
    public let buttonPressedBackground: RGBAColor
    public let buttonBorderNormal: RGBAColor
    public let buttonBorderPressed: RGBAColor
    
    // 3D bevel specifics
    public let bevelHighlight: RGBAColor?
    public let bevelShadow: RGBAColor?
    public let bevelDarkShadow: RGBAColor?
    
    // Typography & Metrics
    public let textColor: RGBAColor
    public let textPressedColor: RGBAColor
    public let fontSize: Double
    public let fontBold: Bool
    public let iconSize: Double

    public static func forStyle(
        _ style: ThemeStyle,
        fontSize: Double = TaskbarConstants.Layout.defaultFontSize,
        iconSize: Double = TaskbarConstants.Layout.defaultIconSize
    ) -> ThemeDefinition {
        switch style {
        case .modernHybrid:
            return ThemeDefinition(
                style: .modernHybrid,
                useTranslucency: true,
                backgroundColor: .clear,
                topBorderColor: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15),
                buttonCornerRadius: 4.0,
                is3DBeveled: false,
                buttonNormalBackground: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08),
                buttonHoverBackground: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16),
                buttonPressedBackground: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28),
                buttonBorderNormal: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12),
                buttonBorderPressed: RGBAColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.6),
                bevelHighlight: nil,
                bevelShadow: nil,
                bevelDarkShadow: nil,
                textColor: RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95),
                textPressedColor: .white,
                fontSize: fontSize,
                fontBold: false,
                iconSize: iconSize
            )
            
        case .retroClassic:
            return ThemeDefinition(
                style: .retroClassic,
                useTranslucency: false,
                backgroundColor: .retroGray,
                topBorderColor: .white,
                buttonCornerRadius: 0.0,
                is3DBeveled: true,
                buttonNormalBackground: .retroGray,
                buttonHoverBackground: .retroGray,
                buttonPressedBackground: .retroLightGray,
                buttonBorderNormal: .retroDarkShadow,
                buttonBorderPressed: .black,
                bevelHighlight: .white,
                bevelShadow: .retroShadow,
                bevelDarkShadow: .retroDarkShadow,
                textColor: .black,
                textPressedColor: .black,
                fontSize: fontSize,
                fontBold: true,
                iconSize: iconSize
            )
        }
    }
}
