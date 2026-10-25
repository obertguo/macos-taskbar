// Tests/TaskbarIntegrationTests/Helpers/FakeWindowSource.swift

import Foundation
import CoreGraphics
import TaskbarCore
import TaskbarKit

@MainActor
public final class FakeWindowSource: WindowSource {
    public let store: WindowStore
    public var onWindowsChanged: (() -> Void)?
    public private(set) var isTracking: Bool = false
    
    public init(store: WindowStore = WindowStore()) {
        self.store = store
    }
    
    public func startTracking() {
        isTracking = true
    }
    
    public func stopTracking() {
        isTracking = false
    }
    
    @discardableResult
    public func addWindow(
        id: UInt64 = UInt64.random(in: 1000...999999),
        pid: pid_t = 100,
        appName: String = "TestApp",
        bundleID: String = "com.test.app",
        title: String = "Test Window",
        frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
        isMinimized: Bool = false,
        isAppHidden: Bool = false,
        isMain: Bool = false,
        isFullScreen: Bool = false
    ) -> WindowInfo {
        let key = WindowKey(id: id, pid: pid)
        let info = WindowInfo(
            key: key,
            pid: pid,
            appName: appName,
            bundleID: bundleID,
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            isAppHidden: isAppHidden,
            isMain: isMain,
            isFullScreen: isFullScreen
        )
        return addWindow(info)
    }
    
    @discardableResult
    public func addWindow(_ info: WindowInfo) -> WindowInfo {
        let pid = info.pid
        var current = store.allWindows.filter { $0.pid == pid && $0.key != info.key }
        current.append(info)
        store.syncSnapshot(forPID: pid, currentWindows: current)
        if info.isMain && (store.frontmostPID == nil || store.frontmostPID == pid) {
            store.setFocusedWindow(key: info.key)
        }
        onWindowsChanged?()
        return info
    }
    
    public func setFrontmostPID(_ pid: pid_t?) {
        store.setFrontmostPID(pid)
    }
    
    public func removeWindow(key: WindowKey) {
        let pid = key.pid
        let remaining = store.allWindows.filter { $0.pid == pid && $0.key != key }
        store.syncSnapshot(forPID: pid, currentWindows: remaining)
        if store.focusedWindowKey == key {
            store.setFocusedWindow(key: nil)
        }
        onWindowsChanged?()
    }
    
    public func removeAllWindows(forPID pid: pid_t) {
        store.removeWindows(forPID: pid)
        onWindowsChanged?()
    }
    
    public func updateTitle(key: WindowKey, newTitle: String) {
        guard var win = store.window(forKey: key) else { return }
        win.title = newTitle
        let pid = key.pid
        var current = store.allWindows.filter { $0.pid == pid && $0.key != key }
        current.append(win)
        store.syncSnapshot(forPID: pid, currentWindows: current)
        onWindowsChanged?()
    }
    
    public func setMinimized(key: WindowKey, isMinimized: Bool) {
        guard var win = store.window(forKey: key) else { return }
        win.isMinimized = isMinimized
        let pid = key.pid
        var current = store.allWindows.filter { $0.pid == pid && $0.key != key }
        current.append(win)
        store.syncSnapshot(forPID: pid, currentWindows: current)
        if isMinimized && store.focusedWindowKey == key {
            store.setFocusedWindow(key: nil)
        }
        onWindowsChanged?()
    }
    
    public func setFocused(key: WindowKey?) {
        store.setFocusedWindow(key: key)
        onWindowsChanged?()
    }
    
    public func setAppHidden(pid: pid_t, isHidden: Bool) {
        store.setAppHidden(pid: pid, isHidden: isHidden)
        onWindowsChanged?()
    }
}
