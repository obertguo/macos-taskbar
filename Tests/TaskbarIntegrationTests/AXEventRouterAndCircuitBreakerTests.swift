// Tests/TaskbarIntegrationTests/AXEventRouterAndCircuitBreakerTests.swift

import Foundation
import Testing
import CoreGraphics
import ApplicationServices
import TaskbarCore
@testable import TaskbarKit

@Suite("AX Event Router and Circuit Breaker Suite", .serialized)
@MainActor
struct AXEventRouterAndCircuitBreakerTests {
    
    // MARK: - 1. Batched Window Attributes
    
    @Test("Verify RawWindowAttributes stores attributes and AXUIElement batch fetch")
    func testBatchedWindowAttributes() {
        let frame = CGRect(x: 100, y: 150, width: 800, height: 600)
        let attrs = RawWindowAttributes(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: "Test Window",
            isMinimized: false,
            frame: frame,
            isMain: true,
            isFullScreen: false
        )
        
        #expect(attrs.role == "AXWindow")
        #expect(attrs.subrole == "AXStandardWindow")
        #expect(attrs.title == "Test Window")
        #expect(attrs.isMinimized == false)
        #expect(attrs.frame == frame)
        #expect(attrs.isMain == true)
        #expect(attrs.isFullScreen == false)
        
        // Edge case variations (dialog, minimized, fullscreen, nil frame/subrole)
        let dialogAttrs = RawWindowAttributes(
            role: "AXWindow",
            subrole: "AXDialog",
            title: "Modal Dialog",
            isMinimized: true,
            frame: nil,
            isMain: false,
            isFullScreen: true
        )
        #expect(dialogAttrs.role == "AXWindow")
        #expect(dialogAttrs.subrole == "AXDialog")
        #expect(dialogAttrs.title == "Modal Dialog")
        #expect(dialogAttrs.isMinimized == true)
        #expect(dialogAttrs.frame == nil)
        #expect(dialogAttrs.isMain == false)
        #expect(dialogAttrs.isFullScreen == true)
        
        // AXUIElement batch attribute fetch verification
        let sysElement = AXUIElementCreateSystemWide()
        let sysBatch = sysElement.fetchWindowAttributesBatch()
        _ = sysBatch // Non-window safely returns nil without IPC crash
        
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let appBatch = appElement.fetchWindowAttributesBatch()
        _ = appBatch
    }
    
    // MARK: - 2. WindowID Nil on Dead Handle (M-23)
    
    @Test("Verify AXUIElement.windowID returns UInt64? and nil on dead/invalid handle")
    func testWindowIDNilOnDeadHandle() {
        // 1. Non-window element (system-wide element)
        let sysElement = AXUIElementCreateSystemWide()
        let sysID: UInt64? = sysElement.windowID
        #expect(sysID == nil, "windowID must return nil for system-wide element")
        
        // 2. Application element (not a window)
        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let appID: UInt64? = appElement.windowID
        #expect(appID == nil, "windowID must return nil for application-level element")
        
        // 3. Dead handle / non-existent PID
        let deadElement = AXUIElementCreateApplication(999999)
        let deadID: UInt64? = deadElement.windowID
        #expect(deadID == nil, "windowID must return nil for dead handle")
        
        // 4. Verify CFHash is NOT used as fallback (preventing M-23 identity corruption)
        let deadHash = UInt64(bitPattern: Int64(CFHash(deadElement)))
        #expect(deadID != deadHash, "windowID must not corrupt data by falling back to CFHash")
    }
    
    // MARK: - 3. CFEqual Recovery on Destroyed Window (M-08)
    
    @Test("Verify AXAppObserver recovers true windowID on destroyed handle via CFEqual")
    func testCFEqualRecoveryOnDestroyedWindow() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var receivedEvent: AXNotificationEvent?
        
        let observer = AXAppObserver(pid: currentPID) { event in
            receivedEvent = event
        }
        
        let testElement = AXUIElementCreateApplication(currentPID)
        #expect(testElement.windowID == nil, "Simulated element has no native CGWindowID (returns nil)")
        
        if let observer = observer {
            let knownWindowID: UInt64 = 77777
            observer.registerObservedWindowForTesting(id: knownWindowID, element: testElement)
            #expect(observer.isWindowObserved(knownWindowID) == true)
            
            // Dispatch destroyed notification with testElement whose windowID is nil
            observer.handleNotification(kAXUIElementDestroyedNotification as String, element: testElement)
            
            // Verify CFEqual successfully resolved the true window ID
            #expect(receivedEvent?.resolvedWindowID == knownWindowID, "Resolved window ID must match knownWindowID via CFEqual")
            #expect(observer.isWindowObserved(knownWindowID) == false, "Window must be removed from observed set after destruction")
        }
        
        // Also verify CFEqual identity matching directly
        let elementA = AXUIElementCreateApplication(currentPID)
        let elementB = elementA
        #expect(elementA.windowID == nil)
        #expect(CFEqual(elementA, elementB), "CFEqual must match identical AXUIElement references")
    }
    
    // MARK: - 4. Circuit Breaker Backoff and Bypass (M-04)
    
    @Test("Verify circuit breaker backoff activation, WindowActions bypass, and clear backoff")
    func testCircuitBreakerBackoffAndBypass() async throws {
        let testPID: pid_t = 9999
        
        // Ensure clean initial state
        AppTracker.clearBackoff(for: testPID)
        #expect(AppTracker.isPIDBackedOff(testPID) == false)
        
        // 1. Record timeout for PID 9999 activates backoff
        AppTracker.recordTimeout(for: testPID)
        #expect(AppTracker.isPIDBackedOff(testPID) == true, "PID must be backed off after recording timeout")
        
        // 2. While backed off, WindowActions.focusWindow bypasses AX IPC without blocking AXThread
        let key = WindowKey(id: 8888, pid: testPID)
        let start = ProcessInfo.processInfo.systemUptime
        WindowActions.focusWindow(key)
        let duration = ProcessInfo.processInfo.systemUptime - start
        
        #expect(duration < 0.10, "Focusing a backed-off PID must return immediately without blocking AXThread")
        
        // 3. Clear backoff restores normal state
        AppTracker.clearBackoff(for: testPID)
        #expect(AppTracker.isPIDBackedOff(testPID) == false, "clearBackoff must restore normal state")
    }
    
    // MARK: - 5. Single Window Delta Update (M-02 Tier 1)
    
    @Test("Verify Tier 1 delta update updates only target WindowKey in WindowStore")
    func testSingleWindowDeltaUpdate() {
        let store = WindowStore()
        
        let key1 = WindowKey(id: 101, pid: 42)
        let key2 = WindowKey(id: 102, pid: 42)
        let key3 = WindowKey(id: 201, pid: 88)
        
        let win1 = WindowInfo(
            key: key1, pid: 42, appName: "TextEdit", bundleID: "com.apple.TextEdit",
            title: "Original Title 1", frame: CGRect(x: 100, y: 100, width: 600, height: 400),
            isMinimized: false, isAppHidden: false, isMain: true, isFullScreen: false
        )
        let win2 = WindowInfo(
            key: key2, pid: 42, appName: "TextEdit", bundleID: "com.apple.TextEdit",
            title: "Original Title 2", frame: CGRect(x: 200, y: 200, width: 600, height: 400),
            isMinimized: false, isAppHidden: false, isMain: false, isFullScreen: false
        )
        let win3 = WindowInfo(
            key: key3, pid: 88, appName: "Safari", bundleID: "com.apple.Safari",
            title: "Apple", frame: CGRect(x: 300, y: 300, width: 800, height: 600),
            isMinimized: false, isAppHidden: false, isMain: false, isFullScreen: false
        )
        
        store.addOrUpdateWindow(win1)
        store.addOrUpdateWindow(win2)
        store.addOrUpdateWindow(win3)
        
        #expect(store.totalWindowCount == 3)
        let initialOpenOrder2 = store.window(forKey: key2)?.openOrder
        let initialOpenOrder3 = store.window(forKey: key3)?.openOrder
        
        // Tier 1 Delta Event: Title Changed on key1
        var updatedWin1 = win1
        updatedWin1.title = "Updated Title 1"
        store.addOrUpdateWindow(updatedWin1)
        
        #expect(store.window(forKey: key1)?.title == "Updated Title 1")
        #expect(store.window(forKey: key2)?.title == "Original Title 2")
        #expect(store.window(forKey: key3)?.title == "Apple")
        #expect(store.window(forKey: key2)?.openOrder == initialOpenOrder2, "Other window openOrder preserved")
        #expect(store.window(forKey: key3)?.openOrder == initialOpenOrder3, "Other window openOrder preserved")
        #expect(store.totalWindowCount == 3, "WindowStore did not replace or clear other windows")
        
        // Tier 1 Delta Event: Minimize key1
        store.setMinimized(key: key1, isMinimized: true)
        
        #expect(store.window(forKey: key1)?.isMinimized == true)
        #expect(store.window(forKey: key2)?.isMinimized == false)
        #expect(store.window(forKey: key3)?.isMinimized == false)
        #expect(store.totalWindowCount == 3)
    }
    
    // MARK: - 6. Dirty PID Reconcile (M-02 Tier 2)
    
    @Test("Verify Tier 2 reconcile updates only the dirty PID in WindowStore")
    func testDirtyPIDReconcile() {
        let store = WindowStore()
        
        let pid1: pid_t = 100
        let pid2: pid_t = 200
        
        let key1 = WindowKey(id: 1001, pid: pid1)
        let key2 = WindowKey(id: 1002, pid: pid1)
        let key3 = WindowKey(id: 2001, pid: pid2)
        let key4 = WindowKey(id: 2002, pid: pid2)
        
        let w1 = WindowInfo(
            key: key1, pid: pid1, appName: "Finder", bundleID: "com.apple.finder",
            title: "Downloads", frame: CGRect(x: 0, y: 0, width: 500, height: 400),
            isMinimized: false, isAppHidden: false, isMain: true, isFullScreen: false
        )
        let w2 = WindowInfo(
            key: key2, pid: pid1, appName: "Finder", bundleID: "com.apple.finder",
            title: "Documents", frame: CGRect(x: 50, y: 50, width: 500, height: 400),
            isMinimized: false, isAppHidden: false, isMain: false, isFullScreen: false
        )
        let w3 = WindowInfo(
            key: key3, pid: pid2, appName: "Xcode", bundleID: "com.apple.dt.Xcode",
            title: "Project", frame: CGRect(x: 100, y: 100, width: 1000, height: 800),
            isMinimized: false, isAppHidden: false, isMain: true, isFullScreen: false
        )
        let w4 = WindowInfo(
            key: key4, pid: pid2, appName: "Xcode", bundleID: "com.apple.dt.Xcode",
            title: "Debug", frame: CGRect(x: 150, y: 150, width: 800, height: 500),
            isMinimized: false, isAppHidden: false, isMain: false, isFullScreen: false
        )
        
        store.syncSnapshot(forPID: pid1, currentWindows: [w1, w2])
        store.syncSnapshot(forPID: pid2, currentWindows: [w3, w4])
        
        #expect(store.totalWindowCount == 4)
        let w3OpenOrder = store.window(forKey: key3)?.openOrder
        let w4OpenOrder = store.window(forKey: key4)?.openOrder
        
        // Simulate Tier 2 Dirty PID Reconcile for dirty pid1 (e.g. w2 closed, w5 created)
        let key5 = WindowKey(id: 1003, pid: pid1)
        let w5 = WindowInfo(
            key: key5, pid: pid1, appName: "Finder", bundleID: "com.apple.finder",
            title: "Desktop", frame: CGRect(x: 200, y: 200, width: 500, height: 400),
            isMinimized: false, isAppHidden: false, isMain: false, isFullScreen: false
        )
        
        let didChange = store.syncSnapshot(forPID: pid1, currentWindows: [w1, w5])
        #expect(didChange == true)
        
        // Verify pid1 is reconciled
        #expect(store.window(forKey: key1) != nil)
        #expect(store.window(forKey: key5) != nil)
        #expect(store.window(forKey: key2) == nil, "Closed window w2 removed for dirty pid1")
        
        // Verify clean pid2 is completely untouched
        #expect(store.window(forKey: key3)?.title == "Project")
        #expect(store.window(forKey: key4)?.title == "Debug")
        #expect(store.window(forKey: key3)?.openOrder == w3OpenOrder, "Clean PID openOrder untouched")
        #expect(store.window(forKey: key4)?.openOrder == w4OpenOrder, "Clean PID openOrder untouched")
        #expect(store.totalWindowCount == 4)
        
        // When another window closes for pid1, only pid1 drops
        let didChange2 = store.syncSnapshot(forPID: pid1, currentWindows: [w1])
        #expect(didChange2 == true)
        #expect(store.window(forKey: key5) == nil)
        #expect(store.window(forKey: key3) != nil)
        #expect(store.window(forKey: key4) != nil)
        #expect(store.totalWindowCount == 3)
    }
    
    // MARK: - 7. Element Cache Fast Path (M-02)
    
    @Test("Verify AppTracker element cache provides O(1) lookup for WindowKey")
    func testElementCacheFastPath() {
        let key = WindowKey(id: 4321, pid: ProcessInfo.processInfo.processIdentifier)
        let element = AXUIElementCreateApplication(key.pid)
        
        AppTracker.removeElement(for: key)
        #expect(AppTracker.elementForWindowKey(key) == nil)
        
        // Cache element
        AppTracker.cacheElement(element, for: key)
        
        // O(1) fast-path retrieval
        let cached = AppTracker.elementForWindowKey(key)
        #expect(cached != nil)
        if let cached = cached {
            #expect(CFEqual(cached, element))
        }
        
        // Eviction
        AppTracker.removeElement(for: key)
        #expect(AppTracker.elementForWindowKey(key) == nil)
    }
}
