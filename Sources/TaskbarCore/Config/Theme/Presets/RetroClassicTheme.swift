// Sources/TaskbarCore/Config/Theme/Presets/RetroClassicTheme.swift

import Foundation

public enum RetroClassicTheme {
    public static let id = "retro-classic"
    
    public static let definition = ThemeDefinition(
        id: id,
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
}
