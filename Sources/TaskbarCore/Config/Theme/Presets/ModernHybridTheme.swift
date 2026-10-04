// Sources/TaskbarCore/Config/Theme/Presets/ModernHybridTheme.swift

import Foundation

public enum ModernHybridTheme {
    public static let id = "modern-hybrid"
    
    // Named Palette Colors
    public static let topBorder = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15)
    public static let textNormal = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95)
    public static let textPressed = RGBAColor.white
    public static let buttonNormal = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08)
    public static let buttonHover = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16)
    public static let buttonPressed = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28)
    public static let buttonBorderNormal = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12)
    public static let buttonBorderPressed = RGBAColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.6)
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.modernHybrid,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: .clear,
            topBorderColor: topBorder,
            textNormal: textNormal,
            textPressed: textPressed,
            buttonNormal: buttonNormal,
            buttonHover: buttonHover,
            buttonPressed: buttonPressed,
            buttonBorderNormal: buttonBorderNormal,
            buttonBorderPressed: buttonBorderPressed
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
}
