// Tests/TaskbarCoreTests/SettingsTests.swift

import XCTest
@testable import TaskbarCore

final class SettingsTests: XCTestCase {
    func testDefaultSettings() {
        let defaults = Settings.default
        XCTAssertEqual(defaults.themeStyle, .modernHybrid)
        XCTAssertEqual(defaults.barHeight, TaskbarConstants.Layout.defaultBarHeight)
        XCTAssertEqual(defaults.maxButtonWidth, TaskbarConstants.Layout.defaultMaxButtonWidth)
        XCTAssertEqual(defaults.minButtonWidth, TaskbarConstants.Layout.defaultMinButtonWidth)
        XCTAssertEqual(defaults.buttonSpacing, TaskbarConstants.Layout.defaultButtonSpacing)
        XCTAssertEqual(defaults.titleVisibilityThreshold, TaskbarConstants.Layout.defaultTitleVisibilityThreshold)
        XCTAssertEqual(defaults.fontSize, TaskbarConstants.Layout.defaultFontSize)
        XCTAssertEqual(defaults.iconSize, TaskbarConstants.Layout.defaultIconSize)
        XCTAssertEqual(defaults.launcherAction, .spotlight)
        XCTAssertTrue(defaults.enableAXNudger)
        XCTAssertTrue(defaults.hideSystemDock)
        XCTAssertEqual(defaults.dockHideDelay, TaskbarConstants.Dock.defaultAutohideDelaySeconds)
        XCTAssertEqual(defaults.pinnedApps, PinnedApp.defaultPinnedApps)
        XCTAssertEqual(defaults.windowGroupingMode, .always)
    }
    
    func testSettingsEncodingDecoding() throws {
        let original = Settings(
            themeStyle: .retroClassic,
            barHeight: 34.0,
            maxButtonWidth: 180.0,
            minButtonWidth: 32.0,
            buttonSpacing: 3.0,
            titleVisibilityThreshold: 45.0,
            fontSize: 12.0,
            iconSize: 20.0,
            launcherAction: .raycast,
            enableAXNudger: false,
            hideSystemDock: true,
            dockHideDelay: 1.5,
            pinnedApps: [
                PinnedApp(bundleIdentifier: "com.apple.Maps", displayName: "Maps")
            ]
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    func testBackwardCompatibleDecodingWithoutDockHideDelay() throws {
        // Simulates persisted settings from older versions lacking dockHideDelay key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "dockHideDelay")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        XCTAssertEqual(decoded.dockHideDelay, TaskbarConstants.Dock.defaultAutohideDelaySeconds)
    }
    
    func testBackwardCompatibleDecodingWithoutPinnedApps() throws {
        // Simulates persisted settings from older versions lacking pinnedApps key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "pinnedApps")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        XCTAssertEqual(decoded.pinnedApps, PinnedApp.defaultPinnedApps)
    }
    
    func testBackwardCompatibleDecodingWithoutWindowGroupingMode() throws {
        // Simulates persisted settings from older versions lacking windowGroupingMode key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "windowGroupingMode")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        XCTAssertEqual(decoded.windowGroupingMode, .always)
    }
    
    func testUserDefaultsPersistence() {
        let testDefaults = UserDefaults(suiteName: "test_settings_suite")!
        testDefaults.removePersistentDomain(forName: "test_settings_suite")
        
        var settings = Settings.load(from: testDefaults)
        XCTAssertEqual(settings, Settings.default)
        
        settings.themeStyle = .retroClassic
        settings.barHeight = 36.0
        settings.fontSize = 13.0
        settings.iconSize = 18.0
        settings.dockHideDelay = 1.0
        settings.save(to: testDefaults)
        
        let reloaded = Settings.load(from: testDefaults)
        XCTAssertEqual(reloaded.themeStyle, .retroClassic)
        XCTAssertEqual(reloaded.barHeight, 36.0)
        XCTAssertEqual(reloaded.fontSize, 13.0)
        XCTAssertEqual(reloaded.iconSize, 18.0)
        XCTAssertEqual(reloaded.dockHideDelay, 1.0)
    }
    
    func testTaskbarStringsAndPresets() {
        XCTAssertEqual(TaskbarStrings.StartButton.title, "Start")
        XCTAssertEqual(TaskbarStrings.Overflow.buttonGlyph, "»")
        XCTAssertEqual(ThemeStyle.modernHybrid.displayName, TaskbarStrings.Themes.modernHybrid)
        XCTAssertEqual(ThemeStyle.retroClassic.displayName, TaskbarStrings.Themes.retroClassic)
        
        // Ensure barHeightPresets contains the defaultBarHeight
        let heights = TaskbarConstants.Layout.barHeightPresets.map { $0.height }
        XCTAssertTrue(heights.contains(TaskbarConstants.Layout.defaultBarHeight))
        
        // Ensure buttonWidthPresets contains the defaultMinButtonWidth
        let widths = TaskbarConstants.Layout.buttonWidthPresets.map { $0.width }
        XCTAssertTrue(widths.contains(TaskbarConstants.Layout.defaultMinButtonWidth))
        
        // Ensure fontSizePresets contains the defaultFontSize
        let fontSizes = TaskbarConstants.Layout.fontSizePresets.map { $0.size }
        XCTAssertTrue(fontSizes.contains(TaskbarConstants.Layout.defaultFontSize))
        
        // Ensure iconSizePresets contains the defaultIconSize
        let iconSizes = TaskbarConstants.Layout.iconSizePresets.map { $0.size }
        XCTAssertTrue(iconSizes.contains(TaskbarConstants.Layout.defaultIconSize))
        
        // Ensure dockDelayPresets contains defaultAutohideDelaySeconds
        let dockDelays = TaskbarConstants.Dock.dockDelayPresets.map { $0.delay }
        XCTAssertTrue(dockDelays.contains(TaskbarConstants.Dock.defaultAutohideDelaySeconds))
    }
    
    // MARK: - TC-UNIT-015: TaskbarEdge Domain Serialization & Settings
    
    func testTaskbarEdgeDomainProperties() {
        XCTAssertTrue(TaskbarEdge.bottom.isHorizontal)
        XCTAssertFalse(TaskbarEdge.bottom.isVertical)
        
        XCTAssertTrue(TaskbarEdge.top.isHorizontal)
        XCTAssertFalse(TaskbarEdge.top.isVertical)
        
        XCTAssertTrue(TaskbarEdge.left.isVertical)
        XCTAssertFalse(TaskbarEdge.left.isHorizontal)
        
        XCTAssertTrue(TaskbarEdge.right.isVertical)
        XCTAssertFalse(TaskbarEdge.right.isHorizontal)
        
        XCTAssertEqual(TaskbarEdge.allCases.count, 4)
    }
    
    func testTaskbarEdgeSerialization() throws {
        var settings = Settings.default
        settings.taskbarEdge = .left
        
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        
        XCTAssertEqual(decoded.taskbarEdge, .left)
        XCTAssertEqual(settings, decoded)
    }
    
    func testBackwardCompatibleDecodingWithoutTaskbarEdge() throws {
        // Simulates persisted settings from v0.1.0-v0.3.1 lacking taskbarEdge key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "taskbarEdge")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        XCTAssertEqual(decoded.taskbarEdge, .bottom)
    }
    
    // MARK: - SettingsPersistence & SettingsStore Tests
    
    @MainActor
    func testSettingsStoreInitializationWithInMemoryPersistence() {
        var customSettings = Settings.default
        customSettings.fontSize = 16.0
        customSettings.iconSize = 22.0
        let persistence = InMemorySettingsPersistence(initial: customSettings)
        let store = SettingsStore(persistence: persistence)
        
        XCTAssertEqual(store.settings, customSettings)
        XCTAssertEqual(store.currentTheme.metrics.fontSize, 16.0)
        XCTAssertEqual(store.currentTheme.metrics.iconSize, 22.0)
        XCTAssertEqual(persistence.stored, customSettings)
    }
    
    @MainActor
    func testSettingsStoreUpdateMutatesAndNotifiesObserver() {
        let persistence = InMemorySettingsPersistence()
        let store = SettingsStore(persistence: persistence)
        
        var observerCalled = false
        var observedOld: Settings?
        var observedNew: Settings?
        
        store.addObserver { old, new in
            observerCalled = true
            observedOld = old
            observedNew = new
        }
        
        let initialSettings = store.settings
        store.update { settings in
            settings.fontSize = 17.0
            settings.iconSize = 21.0
        }
        
        XCTAssertTrue(observerCalled)
        XCTAssertEqual(observedOld, initialSettings)
        XCTAssertEqual(observedNew?.fontSize, 17.0)
        XCTAssertEqual(observedNew?.iconSize, 21.0)
        XCTAssertEqual(store.settings.fontSize, 17.0)
        XCTAssertEqual(store.settings.iconSize, 21.0)
        XCTAssertEqual(store.currentTheme.metrics.fontSize, 17.0)
        XCTAssertEqual(store.currentTheme.metrics.iconSize, 21.0)
        XCTAssertEqual(persistence.stored.fontSize, 17.0)
        XCTAssertEqual(persistence.stored.iconSize, 21.0)
    }
    
    @MainActor
    func testSettingsStoreUpdateDeduplication() {
        let persistence = InMemorySettingsPersistence()
        let store = SettingsStore(persistence: persistence)
        
        var callCount = 0
        store.addObserver { _, _ in
            callCount += 1
        }
        
        // Update that makes no changes
        store.update { _ in }
        XCTAssertEqual(callCount, 0)
        
        // Update that sets existing values
        store.update { settings in
            settings.fontSize = store.settings.fontSize
            settings.iconSize = store.settings.iconSize
        }
        XCTAssertEqual(callCount, 0)
    }
    
    func testApplyingThemeOverridesNonCustomAndCustom() {
        var settings = Settings.default
        settings.fontSize = 19.0
        settings.iconSize = 25.0
        
        // 1. Non-custom theme: overrides font and icon metrics
        let baseNonCustom = ThemeDefinition.modernHybrid
        XCTAssertFalse(baseNonCustom.isCustom)
        let overridden = settings.applyingThemeOverrides(to: baseNonCustom)
        XCTAssertEqual(overridden.metrics.fontSize, 19.0)
        XCTAssertEqual(overridden.metrics.iconSize, 25.0)
        XCTAssertFalse(overridden.isCustom)
        
        // 2. Custom theme: metrics are preserved, not overridden
        let baseCustom = ThemeDefinition.modernHybrid.asCustom(true)
        XCTAssertTrue(baseCustom.isCustom)
        let preserved = settings.applyingThemeOverrides(to: baseCustom)
        XCTAssertEqual(preserved.metrics.fontSize, baseCustom.metrics.fontSize)
        XCTAssertEqual(preserved.metrics.iconSize, baseCustom.metrics.iconSize)
        XCTAssertTrue(preserved.isCustom)
    }
    
    func testUpdateWithCustomThemeMetrics() {
        var settings = Settings.default
        let initialFontSize = settings.fontSize
        
        // Non-custom theme should not change settings
        let nonCustomTheme = ThemeDefinition.modernHybrid
        settings.updateWithCustomThemeMetrics(from: nonCustomTheme)
        XCTAssertEqual(settings.fontSize, initialFontSize)
        
        // Custom theme should update metrics
        let customMetrics = ThemeMetrics(
            buttonCornerRadius: 6.0,
            is3DBeveled: false,
            fontBold: true,
            fontSize: 18.0,
            iconSize: 26.0,
            barHeight: 48.0,
            minButtonWidth: 50.0,
            maxButtonWidth: 220.0,
            buttonSpacing: 8.0
        )
        let customTheme = ThemeDefinition(
            id: "custom.metrics.test",
            displayName: "Test Custom Theme",
            isCustom: true,
            palette: ThemePalette(
                backgroundColor: .black,
                textNormal: .white,
                textPressed: .white,
                buttonNormal: .black,
                buttonHover: .black,
                buttonPressed: .black,
                buttonBorderNormal: .white,
                buttonBorderPressed: .white
            ),
            metrics: customMetrics,
            materials: ThemeMaterials()
        )
        
        settings.updateWithCustomThemeMetrics(from: customTheme)
        XCTAssertEqual(settings.fontSize, 18.0)
        XCTAssertEqual(settings.iconSize, 26.0)
        XCTAssertEqual(settings.barHeight, 48.0)
        XCTAssertEqual(settings.minButtonWidth, 50.0)
        XCTAssertEqual(settings.maxButtonWidth, 220.0)
        XCTAssertEqual(settings.buttonSpacing, 8.0)
    }
}

