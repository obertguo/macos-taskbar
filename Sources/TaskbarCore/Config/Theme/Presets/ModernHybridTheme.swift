// Sources/TaskbarCore/Config/Theme/Presets/ModernHybridTheme.swift

import Foundation

public enum ModernHybridTheme {
    public static let id = "modern-hybrid"
    
    // Local Palette Colors
    private static let topBorder = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15)
    private static let textNormal = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95)
    private static let textPressed = RGBAColor.white
    private static let buttonNormal = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08)
    private static let buttonHover = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16)
    private static let buttonPressed = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28)
    private static let buttonBorderNormal = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12)
    private static let buttonBorderPressed = RGBAColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.6)
    
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
