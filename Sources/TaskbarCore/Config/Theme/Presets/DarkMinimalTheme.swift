// Sources/TaskbarCore/Config/Theme/Presets/DarkMinimalTheme.swift

import Foundation

public enum DarkMinimalTheme {
    public static let id = "dark-minimal"
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.darkMinimal,
        isCustom: false,
        palette: ThemePalette(
            // Deep OLED dark background
            backgroundColor: RGBAColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 18.0 / 255.0),
            topBorderColor: RGBAColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 44.0 / 255.0),
            textNormal: RGBAColor(red: 224.0 / 255.0, green: 224.0 / 255.0, blue: 224.0 / 255.0),
            textPressed: .white,
            buttonNormal: RGBAColor(red: 30.0 / 255.0, green: 30.0 / 255.0, blue: 30.0 / 255.0),
            buttonHover: RGBAColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 44.0 / 255.0),
            buttonPressed: RGBAColor(red: 56.0 / 255.0, green: 56.0 / 255.0, blue: 56.0 / 255.0),
            buttonBorderNormal: RGBAColor(red: 42.0 / 255.0, green: 42.0 / 255.0, blue: 42.0 / 255.0),
            buttonBorderPressed: RGBAColor(red: 0.0, green: 188.0 / 255.0, blue: 212.0 / 255.0, alpha: 0.9),
            bevelHighlight: nil,
            bevelShadow: nil,
            bevelDarkShadow: nil,
            startButtonNormal: RGBAColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 28.0 / 255.0),
            startButtonHover: RGBAColor(red: 40.0 / 255.0, green: 40.0 / 255.0, blue: 40.0 / 255.0),
            startButtonPressed: RGBAColor(red: 50.0 / 255.0, green: 50.0 / 255.0, blue: 50.0 / 255.0),
            startButtonText: .white
        ),
        metrics: ThemeMetrics(
            buttonCornerRadius: 2.0,
            is3DBeveled: false,
            fontBold: false,
            fontSize: TaskbarConstants.Layout.defaultFontSize,
            iconSize: TaskbarConstants.Layout.defaultIconSize
        ),
        materials: ThemeMaterials(useTranslucency: false)
    )
}
