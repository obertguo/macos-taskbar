// Sources/TaskbarCore/Config/Theme/Presets/RetroClassicTheme.swift

import Foundation

public enum RetroClassicTheme {
    public static let id = "retro-classic"
    
    // Local Palette Colors (Windows 95/98 Classic)
    private static let gray = RGBAColor(red: 192.0 / 255.0, green: 192.0 / 255.0, blue: 192.0 / 255.0)
    private static let lightGray = RGBAColor(red: 220.0 / 255.0, green: 220.0 / 255.0, blue: 220.0 / 255.0)
    private static let shadow = RGBAColor(red: 128.0 / 255.0, green: 128.0 / 255.0, blue: 128.0 / 255.0)
    private static let darkShadow = RGBAColor(red: 64.0 / 255.0, green: 64.0 / 255.0, blue: 64.0 / 255.0)
    private static let navy = RGBAColor(red: 0.0, green: 0.0, blue: 128.0 / 255.0)
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.retroClassic,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: gray,
            topBorderColor: .white,
            textNormal: .black,
            textPressed: .black,
            buttonNormal: gray,
            buttonHover: gray,
            buttonPressed: lightGray,
            buttonBorderNormal: darkShadow,
            buttonBorderPressed: .black,
            bevelHighlight: .white,
            bevelShadow: shadow,
            bevelDarkShadow: darkShadow
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
