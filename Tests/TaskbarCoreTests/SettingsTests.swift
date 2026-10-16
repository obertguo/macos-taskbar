// Tests/TaskbarCoreTests/SettingsTests.swift

import Foundation
import Testing
@testable import TaskbarCore

@Suite("Settings Tests")
struct SettingsTests {
    @Test("Default settings values")
    func testDefaultSettings() {
        let defaults = Settings.default
        #expect(defaults.themeStyle == .modernHybrid)
        #expect(defaults.barHeight == TaskbarConstants.Layout.defaultBarHeight)
        #expect(defaults.maxButtonWidth == TaskbarConstants.Layout.defaultMaxButtonWidth)
        #expect(defaults.minButtonWidth == TaskbarConstants.Layout.defaultMinButtonWidth)
        #expect(defaults.buttonSpacing == TaskbarConstants.Layout.defaultButtonSpacing)
        #expect(defaults.titleVisibilityThreshold == TaskbarConstants.Layout.defaultTitleVisibilityThreshold)
        #expect(defaults.fontSize == TaskbarConstants.Layout.defaultFontSize)
        #expect(defaults.iconSize == TaskbarConstants.Layout.defaultIconSize)
        #expect(defaults.launcherAction == .spotlight)
        #expect(defaults.enableAXNudger)
        #expect(defaults.hideSystemDock)
        #expect(defaults.dockHideDelay == TaskbarConstants.Dock.defaultAutohideDelaySeconds)
        #expect(defaults.pinnedApps == PinnedApp.defaultPinnedApps)
        #expect(defaults.windowGroupingMode == .always)
    }
    
    @Test("Settings encoding and decoding round trip")
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
        
        #expect(original == decoded)
    }
    
    @Test("Backward compatible decoding without dockHideDelay")
    func testBackwardCompatibleDecodingWithoutDockHideDelay() throws {
        // Simulates persisted settings from older versions lacking dockHideDelay key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "dockHideDelay")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        #expect(decoded.dockHideDelay == TaskbarConstants.Dock.defaultAutohideDelaySeconds)
    }
    
    @Test("Backward compatible decoding without pinnedApps")
    func testBackwardCompatibleDecodingWithoutPinnedApps() throws {
        // Simulates persisted settings from older versions lacking pinnedApps key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "pinnedApps")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        #expect(decoded.pinnedApps == PinnedApp.defaultPinnedApps)
    }
    
    @Test("Backward compatible decoding without windowGroupingMode")
    func testBackwardCompatibleDecodingWithoutWindowGroupingMode() throws {
        // Simulates persisted settings from older versions lacking windowGroupingMode key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "windowGroupingMode")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        #expect(decoded.windowGroupingMode == .always)
    }
    
    @Test("UserDefaults persistence")
    func testUserDefaultsPersistence() {
        let suiteName = "test_settings_suite_\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        
        var settings = Settings.load(from: testDefaults)
        #expect(settings == Settings.default)
        
        settings.themeStyle = .retroClassic
        settings.barHeight = 36.0
        settings.fontSize = 13.0
        settings.iconSize = 18.0
        settings.dockHideDelay = 1.0
        settings.save(to: testDefaults)
        
        let reloaded = Settings.load(from: testDefaults)
        #expect(reloaded.themeStyle == .retroClassic)
        #expect(reloaded.barHeight == 36.0)
        #expect(reloaded.fontSize == 13.0)
        #expect(reloaded.iconSize == 18.0)
        #expect(reloaded.dockHideDelay == 1.0)
    }
    
    @Test("Taskbar strings and presets")
    func testTaskbarStringsAndPresets() {
        #expect(TaskbarStrings.StartButton.title == "Start")
        #expect(TaskbarStrings.Overflow.buttonGlyph == "»")
        #expect(ThemeStyle.modernHybrid.displayName == TaskbarStrings.Themes.modernHybrid)
        #expect(ThemeStyle.retroClassic.displayName == TaskbarStrings.Themes.retroClassic)
        
        // Ensure barHeightPresets contains the defaultBarHeight
        let heights = TaskbarConstants.Layout.barHeightPresets.map { $0.height }
        #expect(heights.contains(TaskbarConstants.Layout.defaultBarHeight))
        
        // Ensure buttonWidthPresets contains the defaultMinButtonWidth
        let widths = TaskbarConstants.Layout.buttonWidthPresets.map { $0.width }
        #expect(widths.contains(TaskbarConstants.Layout.defaultMinButtonWidth))
        
        // Ensure fontSizePresets contains the defaultFontSize
        let fontSizes = TaskbarConstants.Layout.fontSizePresets.map { $0.size }
        #expect(fontSizes.contains(TaskbarConstants.Layout.defaultFontSize))
        
        // Ensure iconSizePresets contains the defaultIconSize
        let iconSizes = TaskbarConstants.Layout.iconSizePresets.map { $0.size }
        #expect(iconSizes.contains(TaskbarConstants.Layout.defaultIconSize))
        
        // Ensure dockDelayPresets contains defaultAutohideDelaySeconds
        let dockDelays = TaskbarConstants.Dock.dockDelayPresets.map { $0.delay }
        #expect(dockDelays.contains(TaskbarConstants.Dock.defaultAutohideDelaySeconds))
    }
    
    // MARK: - TC-UNIT-015: TaskbarEdge Domain Serialization & Settings
    
    @Test("TaskbarEdge domain properties")
    func testTaskbarEdgeDomainProperties() {
        #expect(TaskbarEdge.bottom.isHorizontal)
        #expect(!TaskbarEdge.bottom.isVertical)
        
        #expect(TaskbarEdge.top.isHorizontal)
        #expect(!TaskbarEdge.top.isVertical)
        
        #expect(TaskbarEdge.left.isVertical)
        #expect(!TaskbarEdge.left.isHorizontal)
        
        #expect(TaskbarEdge.right.isVertical)
        #expect(!TaskbarEdge.right.isHorizontal)
        
        #expect(TaskbarEdge.allCases.count == 4)
    }
    
    @Test("TaskbarEdge serialization")
    func testTaskbarEdgeSerialization() throws {
        var settings = Settings.default
        settings.taskbarEdge = .left
        
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        
        #expect(decoded.taskbarEdge == .left)
        #expect(settings == decoded)
    }
    
    @Test("Backward compatible decoding without taskbarEdge")
    func testBackwardCompatibleDecodingWithoutTaskbarEdge() throws {
        // Simulates persisted settings from v0.1.0-v0.3.1 lacking taskbarEdge key
        let baseData = try JSONEncoder().encode(Settings.default)
        var dict = try JSONSerialization.jsonObject(with: baseData) as! [String: Any]
        dict.removeValue(forKey: "taskbarEdge")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)
        
        let decoded = try JSONDecoder().decode(Settings.self, from: legacyData)
        #expect(decoded.taskbarEdge == .bottom)
    }
    
    // MARK: - SettingsPersistence & SettingsStore Tests
    
    @MainActor
    @Test("SettingsStore initialization with in-memory persistence")
    func testSettingsStoreInitializationWithInMemoryPersistence() {
        var customSettings = Settings.default
        customSettings.fontSize = 16.0
        customSettings.iconSize = 22.0
        let persistence = InMemorySettingsPersistence(initial: customSettings)
        let store = SettingsStore(persistence: persistence)
        
        #expect(store.settings == customSettings)
        #expect(store.currentTheme.metrics.fontSize == 16.0)
        #expect(store.currentTheme.metrics.iconSize == 22.0)
        #expect(persistence.stored == customSettings)
    }
    
    @MainActor
    @Test("SettingsStore update mutates and notifies observer")
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
        
        #expect(observerCalled)
        #expect(observedOld == initialSettings)
        #expect(observedNew?.fontSize == 17.0)
        #expect(observedNew?.iconSize == 21.0)
        #expect(store.settings.fontSize == 17.0)
        #expect(store.settings.iconSize == 21.0)
        #expect(store.currentTheme.metrics.fontSize == 17.0)
        #expect(store.currentTheme.metrics.iconSize == 21.0)
        #expect(persistence.stored.fontSize == 17.0)
        #expect(persistence.stored.iconSize == 21.0)
    }
    
    @MainActor
    @Test("SettingsStore update deduplication")
    func testSettingsStoreUpdateDeduplication() {
        let persistence = InMemorySettingsPersistence()
        let store = SettingsStore(persistence: persistence)
        
        var callCount = 0
        store.addObserver { _, _ in
            callCount += 1
        }
        
        // Update that makes no changes
        store.update { _ in }
        #expect(callCount == 0)
        
        // Update that sets existing values
        store.update { settings in
            settings.fontSize = store.settings.fontSize
            settings.iconSize = store.settings.iconSize
        }
        #expect(callCount == 0)
    }
    
    @Test("Applying theme overrides for non-custom and custom themes")
    func testApplyingThemeOverridesNonCustomAndCustom() {
        var settings = Settings.default
        settings.fontSize = 19.0
        settings.iconSize = 25.0
        
        // 1. Non-custom theme: overrides font and icon metrics
        let baseNonCustom = ThemeDefinition.modernHybrid
        #expect(!baseNonCustom.isCustom)
        let overridden = settings.applyingThemeOverrides(to: baseNonCustom)
        #expect(overridden.metrics.fontSize == 19.0)
        #expect(overridden.metrics.iconSize == 25.0)
        #expect(!overridden.isCustom)
        
        // 2. Custom theme: metrics are preserved, not overridden
        let baseCustom = ThemeDefinition.modernHybrid.asCustom(true)
        #expect(baseCustom.isCustom)
        let preserved = settings.applyingThemeOverrides(to: baseCustom)
        #expect(preserved.metrics.fontSize == baseCustom.metrics.fontSize)
        #expect(preserved.metrics.iconSize == baseCustom.metrics.iconSize)
        #expect(preserved.isCustom)
    }
    
    @Test("Update with custom theme metrics")
    func testUpdateWithCustomThemeMetrics() {
        var settings = Settings.default
        let initialFontSize = settings.fontSize
        
        // Non-custom theme should not change settings
        let nonCustomTheme = ThemeDefinition.modernHybrid
        settings.updateWithCustomThemeMetrics(from: nonCustomTheme)
        #expect(settings.fontSize == initialFontSize)
        
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
        #expect(settings.fontSize == 18.0)
        #expect(settings.iconSize == 26.0)
        #expect(settings.barHeight == 48.0)
        #expect(settings.minButtonWidth == 50.0)
        #expect(settings.maxButtonWidth == 220.0)
        #expect(settings.buttonSpacing == 8.0)
    }
}
