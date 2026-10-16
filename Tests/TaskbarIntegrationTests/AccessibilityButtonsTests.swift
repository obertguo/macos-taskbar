// Tests/TaskbarIntegrationTests/AccessibilityButtonsTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("Accessibility Buttons Integration Suite")
@MainActor
struct AccessibilityButtonsTests {

    @Test("BaseTaskbarButton accessibility element, role, label, and performPress")
    func testBaseTaskbarButtonAccessibility() {
        let button = BaseTaskbarButton(frame: NSRect(x: 0, y: 0, width: 40, height: 26))
        button.toolTip = "Generic Button"
        
        #expect(button.isAccessibilityElement() == true)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == "Generic Button")
        
        var clicked = false
        button.onClick = { clicked = true }
        
        let pressResult = button.accessibilityPerformPress()
        #expect(pressResult == true)
        #expect(clicked == true)
    }

    @Test("TaskButton accessibility element, role, label, and performPress")
    func testTaskButtonAccessibility() {
        let win = WindowInfo(
            key: WindowKey(id: 1, pid: 100),
            pid: 100,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "Apple Homepage",
            frame: .zero,
            isMinimized: false
        )
        let button = TaskButton(
            windowInfo: win,
            isFocused: false,
            showTitle: true,
            theme: ModernHybridTheme.definition
        )
        
        #expect(button.isAccessibilityElement() == true)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == button.group.displayTitle)
        
        var clicked = false
        button.onClick = { clicked = true }
        
        let pressResult = button.accessibilityPerformPress()
        #expect(pressResult == true)
        #expect(clicked == true)
        
        // Grouped window accessibility label verification
        let win2 = WindowInfo(
            key: WindowKey(id: 2, pid: 100),
            pid: 100,
            appName: "Safari",
            bundleID: "com.apple.Safari",
            title: "WebKit",
            frame: .zero,
            isMinimized: false
        )
        let group = WindowGroup.applicationGroup(
            bundleID: "com.apple.Safari",
            appName: "Safari",
            windows: [win, win2]
        )
        let groupedButton = TaskButton(
            group: group,
            isFocused: false,
            showTitle: true,
            theme: ModernHybridTheme.definition
        )
        #expect(groupedButton.isAccessibilityElement() == true)
        #expect(groupedButton.accessibilityRole() == .button)
        #expect(groupedButton.accessibilityLabel() == group.displayTitle)
    }

    @Test("PinnedButton accessibility element, role, label, and performPress")
    func testPinnedButtonAccessibility() {
        let pinnedApp = PinnedApp(bundleIdentifier: "com.apple.finder", displayName: "Finder")
        let button = PinnedButton(
            pinnedApp: pinnedApp,
            isRunning: false,
            theme: ModernHybridTheme.definition
        )
        
        #expect(button.isAccessibilityElement() == true)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == pinnedApp.displayName)
        
        var clicked = false
        button.onClick = { clicked = true }
        
        let pressResult = button.accessibilityPerformPress()
        #expect(pressResult == true)
        #expect(clicked == true)
        
        // Dynamic update check when pinnedApp changes
        let updatedApp = PinnedApp(bundleIdentifier: "com.apple.mail", displayName: "Mail")
        button.pinnedApp = updatedApp
        #expect(button.accessibilityLabel() == "Mail")
    }

    @Test("StartButton accessibility element, role, label, and performPress")
    func testStartButtonAccessibility() {
        let button = StartButton(theme: ModernHybridTheme.definition)
        
        #expect(button.isAccessibilityElement() == true)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == "Start")
        
        var clicked = false
        button.onClick = { clicked = true }
        
        let pressResult = button.accessibilityPerformPress()
        #expect(pressResult == true)
        #expect(clicked == true)
    }

    @Test("OverflowButton accessibility element, role, label, and performPress")
    func testOverflowButtonAccessibility() {
        let button = OverflowButton(theme: ModernHybridTheme.definition)
        
        #expect(button.isAccessibilityElement() == true)
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == "Overflow Items")
        
        var clicked = false
        button.onClick = { clicked = true }
        
        let pressResult = button.accessibilityPerformPress()
        #expect(pressResult == true)
        #expect(clicked == true)
    }
}
