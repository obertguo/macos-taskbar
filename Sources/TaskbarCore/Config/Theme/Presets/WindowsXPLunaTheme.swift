// Sources/TaskbarCore/Config/Theme/Presets/WindowsXPLunaTheme.swift

import Foundation

public enum WindowsXPLunaTheme {
    public static let id = "windows-xp-luna"
    
    // Named Palette Colors (Windows XP Luna Blue)
    public static let taskbarBlue = RGBAColor(red: 36.0 / 255.0, green: 94.0 / 255.0, blue: 220.0 / 255.0)
    public static let topBorderBlue = RGBAColor(red: 64.0 / 255.0, green: 140.0 / 255.0, blue: 242.0 / 255.0)
    public static let textNormal = RGBAColor.white
    public static let textPressedGold = RGBAColor(red: 1.0, green: 0.95, blue: 0.80)
    public static let buttonNormal = RGBAColor(red: 56.0 / 255.0, green: 119.0 / 255.0, blue: 232.0 / 255.0)
    public static let buttonHover = RGBAColor(red: 74.0 / 255.0, green: 135.0 / 255.0, blue: 242.0 / 255.0)
    public static let buttonPressed = RGBAColor(red: 25.0 / 255.0, green: 65.0 / 255.0, blue: 165.0 / 255.0)
    public static let buttonBorderNormal = RGBAColor(red: 38.0 / 255.0, green: 89.0 / 255.0, blue: 191.0 / 255.0)
    public static let buttonBorderPressed = RGBAColor(red: 20.0 / 255.0, green: 46.0 / 255.0, blue: 128.0 / 255.0)
    
    // Signature Windows XP Green Start button
    public static let startButtonNormal = RGBAColor(red: 56.0 / 255.0, green: 142.0 / 255.0, blue: 60.0 / 255.0)
    public static let startButtonHover = RGBAColor(red: 67.0 / 255.0, green: 160.0 / 255.0, blue: 71.0 / 255.0)
    public static let startButtonPressed = RGBAColor(red: 46.0 / 255.0, green: 125.0 / 255.0, blue: 50.0 / 255.0)
    public static let startButtonText = RGBAColor.white
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.windowsXPLuna,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: taskbarBlue,
            topBorderColor: topBorderBlue,
            textNormal: textNormal,
            textPressed: textPressedGold,
            buttonNormal: buttonNormal,
            buttonHover: buttonHover,
            buttonPressed: buttonPressed,
            buttonBorderNormal: buttonBorderNormal,
            buttonBorderPressed: buttonBorderPressed,
            bevelHighlight: nil,
            bevelShadow: nil,
            bevelDarkShadow: nil,
            startButtonNormal: startButtonNormal,
            startButtonHover: startButtonHover,
            startButtonPressed: startButtonPressed,
            startButtonText: startButtonText
        ),
        metrics: ThemeMetrics(
            buttonCornerRadius: 3.0,
            is3DBeveled: false,
            fontBold: false,
            fontSize: TaskbarConstants.Layout.defaultFontSize,
            iconSize: TaskbarConstants.Layout.defaultIconSize
        ),
        materials: ThemeMaterials(useTranslucency: false)
    )
}
