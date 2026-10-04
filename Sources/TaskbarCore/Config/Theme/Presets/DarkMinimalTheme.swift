// Sources/TaskbarCore/Config/Theme/Presets/DarkMinimalTheme.swift

import Foundation

public enum DarkMinimalTheme {
    public static let id = "dark-minimal"
    
    // Local Palette Colors (Deep OLED Dark)
    private static let backgroundDark = RGBAColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 18.0 / 255.0)
    private static let topBorderDark = RGBAColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 44.0 / 255.0)
    private static let textNormal = RGBAColor(red: 224.0 / 255.0, green: 224.0 / 255.0, blue: 224.0 / 255.0)
    private static let textPressed = RGBAColor.white
    private static let buttonNormal = RGBAColor(red: 30.0 / 255.0, green: 30.0 / 255.0, blue: 30.0 / 255.0)
    private static let buttonHover = RGBAColor(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 44.0 / 255.0)
    private static let buttonPressed = RGBAColor(red: 56.0 / 255.0, green: 56.0 / 255.0, blue: 56.0 / 255.0)
    private static let buttonBorderNormal = RGBAColor(red: 42.0 / 255.0, green: 42.0 / 255.0, blue: 42.0 / 255.0)
    private static let buttonBorderPressedCyan = RGBAColor(red: 0.0, green: 188.0 / 255.0, blue: 212.0 / 255.0, alpha: 0.9)
    
    // Start Button Colors
    private static let startButtonNormal = RGBAColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 28.0 / 255.0)
    private static let startButtonHover = RGBAColor(red: 40.0 / 255.0, green: 40.0 / 255.0, blue: 40.0 / 255.0)
    private static let startButtonPressed = RGBAColor(red: 50.0 / 255.0, green: 50.0 / 255.0, blue: 50.0 / 255.0)
    private static let startButtonText = RGBAColor.white
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.darkMinimal,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: backgroundDark,
            topBorderColor: topBorderDark,
            textNormal: textNormal,
            textPressed: textPressed,
            buttonNormal: buttonNormal,
            buttonHover: buttonHover,
            buttonPressed: buttonPressed,
            buttonBorderNormal: buttonBorderNormal,
            buttonBorderPressed: buttonBorderPressedCyan,
            bevelHighlight: nil,
            bevelShadow: nil,
            bevelDarkShadow: nil,
            startButtonNormal: startButtonNormal,
            startButtonHover: startButtonHover,
            startButtonPressed: startButtonPressed,
            startButtonText: startButtonText
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
