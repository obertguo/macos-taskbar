// Sources/TaskbarCore/Config/Theme/Presets/ModernHybridTheme.swift

import Foundation

public enum ModernHybridTheme {
    public static let id = "modern-hybrid"
    
    public static let definition = ThemeDefinition(
        id: id,
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
}
