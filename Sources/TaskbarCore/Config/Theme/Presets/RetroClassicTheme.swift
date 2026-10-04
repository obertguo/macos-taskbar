// Sources/TaskbarCore/Config/Theme/Presets/RetroClassicTheme.swift

import Foundation

public enum RetroClassicTheme {
    public static let id = "retro-classic"
    
    // Color Palette Tokens
    private static let classicGray = RGBAColor(red: 192.0 / 255.0, green: 192.0 / 255.0, blue: 192.0 / 255.0)
    private static let silverLight = RGBAColor(red: 220.0 / 255.0, green: 220.0 / 255.0, blue: 220.0 / 255.0)
    private static let mediumGray = RGBAColor(red: 128.0 / 255.0, green: 128.0 / 255.0, blue: 128.0 / 255.0)
    private static let darkGray = RGBAColor(red: 64.0 / 255.0, green: 64.0 / 255.0, blue: 64.0 / 255.0)
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.retroClassic,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: classicGray,
            topBorderColor: .white,
            textNormal: .black,
            textPressed: .black,
            buttonNormal: classicGray,
            buttonHover: classicGray,
            buttonPressed: silverLight,
            buttonBorderNormal: darkGray,
            buttonBorderPressed: .black,
            bevelHighlight: .white,
            bevelShadow: mediumGray,
            bevelDarkShadow: darkGray
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
}
