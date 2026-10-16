// Tests/TaskbarCoreTests/ScreenAssignmentTests.swift

import CoreGraphics
import Testing
@testable import TaskbarCore

@Suite("Screen Assignment Tests")
struct ScreenAssignmentTests {
    let screen1 = ScreenDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true)
    let screen2 = ScreenDescriptor(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: false)
    
    @Test("Window wholly inside screen assignment")
    func testWindowWhollyInsideScreen() {
        let win = CGRect(x: 200, y: 200, width: 800, height: 600)
        let assigned = ScreenAssignment.assignScreen(for: win, across: [screen1, screen2])
        #expect(assigned == 1)
        
        let win2 = CGRect(x: 2100, y: 200, width: 800, height: 600)
        let assigned2 = ScreenAssignment.assignScreen(for: win2, across: [screen1, screen2])
        #expect(assigned2 == 2)
    }
    
    @Test("Window spanning both screens assignment based on majority overlap")
    func testWindowSpanningBothScreens() {
        // Window from x: 1500 to x: 2300 (800 wide). Overlaps Screen 1 by 420px, Screen 2 by 380px.
        let win = CGRect(x: 1500, y: 200, width: 800, height: 600)
        let assigned = ScreenAssignment.assignScreen(for: win, across: [screen1, screen2])
        #expect(assigned == 1)
        
        // Window from x: 1700 to x: 2500 (800 wide). Overlaps Screen 1 by 220px, Screen 2 by 580px.
        let win2 = CGRect(x: 1700, y: 200, width: 800, height: 600)
        let assigned2 = ScreenAssignment.assignScreen(for: win2, across: [screen1, screen2])
        #expect(assigned2 == 2)
    }
    
    @Test("Offscreen window fallback to closest screen")
    func testOffscreenFallback() {
        // Window completely offscreen at negative coordinates
        let win = CGRect(x: -2000, y: 200, width: 500, height: 500)
        let assigned = ScreenAssignment.assignScreen(for: win, across: [screen1, screen2])
        // Screen 1 is closer than Screen 2
        #expect(assigned == 1)
    }
}
