// Sources/TaskbarCore/Config/Theme/Presets/WindowsXPLunaTheme.swift

import Foundation

public enum WindowsXPLunaTheme {
    public static let id = "windows-xp-luna"
    
    // Color Palette Tokens
    private static let royalBlue = RGBAColor(red: 36.0 / 255.0, green: 94.0 / 255.0, blue: 220.0 / 255.0)
    private static let skyBlue = RGBAColor(red: 64.0 / 255.0, green: 140.0 / 255.0, blue: 242.0 / 255.0)
    private static let warmGold = RGBAColor(red: 1.0, green: 0.95, blue: 0.80)
    private static let cornflowerBlue = RGBAColor(red: 56.0 / 255.0, green: 119.0 / 255.0, blue: 232.0 / 255.0)
    private static let lightAzureBlue = RGBAColor(red: 74.0 / 255.0, green: 135.0 / 255.0, blue: 242.0 / 255.0)
    private static let deepNavyBlue = RGBAColor(red: 25.0 / 255.0, green: 65.0 / 255.0, blue: 165.0 / 255.0)
    private static let steelBlue = RGBAColor(red: 38.0 / 255.0, green: 89.0 / 255.0, blue: 191.0 / 255.0)
    private static let midnightBlue = RGBAColor(red: 20.0 / 255.0, green: 46.0 / 255.0, blue: 128.0 / 255.0)
    
    // Start button tokens
    private static let emeraldGreen = RGBAColor(red: 56.0 / 255.0, green: 142.0 / 255.0, blue: 60.0 / 255.0)
    private static let brightGreen = RGBAColor(red: 67.0 / 255.0, green: 160.0 / 255.0, blue: 71.0 / 255.0)
    private static let forestGreen = RGBAColor(red: 46.0 / 255.0, green: 125.0 / 255.0, blue: 50.0 / 255.0)
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.windowsXPLuna,
        isCustom: false,
        palette: ThemePalette(
            backgroundColor: royalBlue,
            topBorderColor: skyBlue,
            textNormal: .white,
            textPressed: warmGold,
            buttonNormal: cornflowerBlue,
            buttonHover: lightAzureBlue,
            buttonPressed: deepNavyBlue,
            buttonBorderNormal: steelBlue,
            buttonBorderPressed: midnightBlue,
            bevelHighlight: nil,
            bevelShadow: nil,
            bevelDarkShadow: nil,
            startButtonNormal: emeraldGreen,
            startButtonHover: brightGreen,
            startButtonPressed: forestGreen,
            startButtonText: .white
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
