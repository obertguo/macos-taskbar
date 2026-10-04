// Sources/TaskbarCore/Config/Theme/Presets/ModernHybridTheme.swift

import Foundation

public enum ModernHybridTheme {
    public static let id = "modern-hybrid"
    
    // Color Palette Tokens
    private static let translucentWhite15 = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15)
    private static let translucentWhite95 = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95)
    private static let translucentWhite08 = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08)
    private static let translucentWhite16 = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16)
    private static let translucentWhite28 = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.28)
    private static let translucentWhite12 = RGBAColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.12)
    private static let translucentAccentBlue = RGBAColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.6)
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.modernHybrid,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: .clear,
            topBorderColor: translucentWhite15,
            textNormal: translucentWhite95,
            textPressed: .white,
            buttonNormal: translucentWhite08,
            buttonHover: translucentWhite16,
            buttonPressed: translucentWhite28,
            buttonBorderNormal: translucentWhite12,
            buttonBorderPressed: translucentAccentBlue
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
