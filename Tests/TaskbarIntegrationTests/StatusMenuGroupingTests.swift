// Tests/TaskbarIntegrationTests/StatusMenuGroupingTests.swift

import AppKit
import Foundation
import Testing
import TaskbarCore
import TaskbarKit

@Suite("StatusMenu Window Grouping Integration Suite")
@MainActor
struct StatusMenuGroupingTests {
    
    @Test("StatusMenu window grouping submenu contains expected mode items and initial checkmark")
    func testStatusMenuGroupingSubmenuStructure() {
        let statusMenu = StatusMenu(windowGroupingMode: .always)
        
        guard let statusItem = Mirror(reflecting: statusMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menu = statusItem.menu,
              let groupingItem = menu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.menuTitle }),
              let groupingSubmenu = groupingItem.submenu else {
            Issue.record("Failed to inspect StatusMenu window grouping submenu")
            return
        }
        
        let titles = groupingSubmenu.items.map { $0.title }
        #expect(titles.contains(TaskbarStrings.WindowGrouping.modeAlways))
        #expect(titles.contains(TaskbarStrings.WindowGrouping.modeWhenCrowded))
        #expect(titles.contains(TaskbarStrings.WindowGrouping.modeNever))
        #expect(titles.count == 3)
        
        // Default .always should have .on state, other modes .off
        let alwaysItem = groupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeAlways })
        let whenCrowdedItem = groupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeWhenCrowded })
        let neverItem = groupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeNever })
        
        #expect(alwaysItem?.state == .on)
        #expect(whenCrowdedItem?.state == .off)
        #expect(neverItem?.state == .off)
    }
    
    @Test("StatusMenu window grouping submenu reflects initial mode configuration")
    func testStatusMenuGroupingInitialModes() {
        // Test .never mode
        let neverMenu = StatusMenu(windowGroupingMode: .never)
        guard let statusItemNever = Mirror(reflecting: neverMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menuNever = statusItemNever.menu,
              let groupingSubmenuNever = menuNever.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.menuTitle })?.submenu else {
            Issue.record("Failed to inspect StatusMenu for .never mode")
            return
        }
        
        #expect(groupingSubmenuNever.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeAlways })?.state == .off)
        #expect(groupingSubmenuNever.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeWhenCrowded })?.state == .off)
        #expect(groupingSubmenuNever.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeNever })?.state == .on)
        
        // Test .whenCrowded mode
        let crowdedMenu = StatusMenu(windowGroupingMode: .whenCrowded)
        guard let statusItemCrowded = Mirror(reflecting: crowdedMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menuCrowded = statusItemCrowded.menu,
              let groupingSubmenuCrowded = menuCrowded.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.menuTitle })?.submenu else {
            Issue.record("Failed to inspect StatusMenu for .whenCrowded mode")
            return
        }
        
        #expect(groupingSubmenuCrowded.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeAlways })?.state == .off)
        #expect(groupingSubmenuCrowded.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeWhenCrowded })?.state == .on)
        #expect(groupingSubmenuCrowded.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeNever })?.state == .off)
    }
    
    @Test("Selecting a grouping mode triggers onWindowGroupingModeChanged and updates menu state")
    func testStatusMenuGroupingSelectionDispatchesCallback() {
        let statusMenu = StatusMenu(windowGroupingMode: .always)
        var dispatchedMode: WindowGroupingMode?
        statusMenu.onWindowGroupingModeChanged = { mode in
            dispatchedMode = mode
        }
        
        guard let statusItem = Mirror(reflecting: statusMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menu = statusItem.menu,
              let groupingItem = menu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.menuTitle }),
              let groupingSubmenu = groupingItem.submenu,
              let whenCrowdedItem = groupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeWhenCrowded }),
              let action = whenCrowdedItem.action,
              let target = whenCrowdedItem.target else {
            Issue.record("Failed to find whenCrowded menu item or target/action")
            return
        }
        
        _ = (target as AnyObject).perform(action, with: whenCrowdedItem)
        
        #expect(dispatchedMode == .whenCrowded)
        #expect(statusMenu.windowGroupingMode == .whenCrowded)
        
        // Re-inspect updated menu
        guard let updatedStatusItem = Mirror(reflecting: statusMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let updatedMenu = updatedStatusItem.menu,
              let updatedGroupingSubmenu = updatedMenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.menuTitle })?.submenu else {
            Issue.record("Failed to inspect updated StatusMenu")
            return
        }
        
        let alwaysItem = updatedGroupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeAlways })
        let crowdedItem = updatedGroupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeWhenCrowded })
        let neverItem = updatedGroupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeNever })
        
        #expect(alwaysItem?.state == .off)
        #expect(crowdedItem?.state == .on)
        #expect(neverItem?.state == .off)
    }
    
    @Test("Programmatic updateWindowGroupingMode synchronizes property and menu item states")
    func testStatusMenuUpdateWindowGroupingModeDynamically() {
        let statusMenu = StatusMenu(windowGroupingMode: .always)
        
        statusMenu.updateWindowGroupingMode(.never)
        #expect(statusMenu.windowGroupingMode == .never)
        
        guard let statusItem = Mirror(reflecting: statusMenu).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let menu = statusItem.menu,
              let groupingSubmenu = menu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.menuTitle })?.submenu else {
            Issue.record("Failed to inspect StatusMenu after dynamic mode update")
            return
        }
        
        let alwaysItem = groupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeAlways })
        let crowdedItem = groupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeWhenCrowded })
        let neverItem = groupingSubmenu.items.first(where: { $0.title == TaskbarStrings.WindowGrouping.modeNever })
        
        #expect(alwaysItem?.state == .off)
        #expect(crowdedItem?.state == .off)
        #expect(neverItem?.state == .on)
    }
}
