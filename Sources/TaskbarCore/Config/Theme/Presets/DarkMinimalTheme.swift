// Sources/TaskbarCore/Config/Theme/Presets/DarkMinimalTheme.swift

import Foundation

public enum DarkMinimalTheme {
    public static let id = "dark-minimal"
    
    // Color Palette Tokens
    private static let nearBlack = RGBAColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 18.0 / 255.0)
    private static let darkCharcoal = RGBAColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 28.0 / 255.0)
    private static let charcoal = RGBAColor(red: 30.0 / 255.0, green: 30.0 / 255.0, blue: 30.0 / 255.0)
    private static let slateCharcoal = RGBAColor(red: 40.0 / 255.0, green: 40.0 / 255.0, blue: 40.0 / 255.0)
    private static let darkBorderGray = RGBAColor(red: 42.0 / 255.0, green: 42.0 / 255.0, blue: 42.0 / 255.0)
    private static let mediumCharcoal = RGBAColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 44.0 / 255.0)
    private static let lightCharcoal = RGBAColor(red: 50.0 / 255.0, green: 50.0 / 255.0, blue: 50.0 / 255.0)
    private static let deepGray = RGBAColor(red: 56.0 / 255.0, green: 56.0 / 255.0, blue: 56.0 / 255.0)
    private static let offWhite = RGBAColor(red: 224.0 / 255.0, green: 224.0 / 255.0, blue: 224.0 / 255.0)
    private static let translucentCyan = RGBAColor(red: 0.0, green: 188.0 / 255.0, blue: 212.0 / 255.0, alpha: 0.9)
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.darkMinimal,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: nearBlack,
            topBorderColor: mediumCharcoal,
            textNormal: offWhite,
            textPressed: .white,
            buttonNormal: charcoal,
            buttonHover: mediumCharcoal,
            buttonPressed: deepGray,
            buttonBorderNormal: darkBorderGray,
            buttonBorderPressed: translucentCyan,
            bevelHighlight: nil,
            bevelShadow: nil,
            bevelDarkShadow: nil,
            startButtonNormal: darkCharcoal,
            startButtonHover: slateCharcoal,
            startButtonPressed: lightCharcoal,
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
