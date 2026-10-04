// Sources/TaskbarCore/Config/Theme/Presets/WindowsXPLunaTheme.swift

import Foundation

public enum WindowsXPLunaTheme {
    public static let id = "windows-xp-luna"
    
    public static let definition = ThemeDefinition(
        id: id,
        displayName: TaskbarStrings.Themes.windowsXPLuna,
        isCustom: false,
        palette: ThemePalette(
            // Classic Luna taskbar blue
            backgroundColor: RGBAColor(red: 36.0 / 255.0, green: 94.0 / 255.0, blue: 220.0 / 255.0),
            topBorderColor: RGBAColor(red: 64.0 / 255.0, green: 140.0 / 255.0, blue: 242.0 / 255.0),
            textNormal: .white,
            textPressed: RGBAColor(red: 1.0, green: 0.95, blue: 0.80),
            buttonNormal: RGBAColor(red: 56.0 / 255.0, green: 119.0 / 255.0, blue: 232.0 / 255.0),
            buttonHover: RGBAColor(red: 74.0 / 255.0, green: 135.0 / 255.0, blue: 242.0 / 255.0),
            buttonPressed: RGBAColor(red: 25.0 / 255.0, green: 65.0 / 255.0, blue: 165.0 / 255.0),
            buttonBorderNormal: RGBAColor(red: 38.0 / 255.0, green: 89.0 / 255.0, blue: 191.0 / 255.0),
            buttonBorderPressed: RGBAColor(red: 20.0 / 255.0, green: 46.0 / 255.0, blue: 128.0 / 255.0),
            bevelHighlight: nil,
            bevelShadow: nil,
            bevelDarkShadow: nil,
            // Signature Windows XP Green Start button
            startButtonNormal: RGBAColor(red: 56.0 / 255.0, green: 142.0 / 255.0, blue: 60.0 / 255.0),
            startButtonHover: RGBAColor(red: 67.0 / 255.0, green: 160.0 / 255.0, blue: 71.0 / 255.0),
            startButtonPressed: RGBAColor(red: 46.0 / 255.0, green: 125.0 / 255.0, blue: 50.0 / 255.0),
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
