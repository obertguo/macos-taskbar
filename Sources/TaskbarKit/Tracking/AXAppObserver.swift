// Sources/TaskbarApp/Tracking/AXAppObserver.swift

import ApplicationServices
import Foundation

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let appObserver = Unmanaged<AXAppObserver>.fromOpaque(refcon).takeUnretainedValue()
    appObserver.handleNotification(notification as String, element: element)
}

public final class AXAppObserver: @unchecked Sendable {
    public let pid: pid_t
    public let appElement: AXUIElement
    private var observer: AXObserver?
    private var runLoopSource: CFRunLoopSource?
    public var onEvent: (() -> Void)?
    
    private var observedWindows: Set<UInt64> = []
    private var observedWindowElements: [UInt64: AXUIElement] = [:]
    
    // Application-level notifications (supported on appElement)
    private let appNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString
    ]
    
    // Window-level notifications (must be attached to AXWindow elements)
    private let windowNotifications: [CFString] = [
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
        kAXTitleChangedNotification as CFString,
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString
    ]
    
    public init?(pid: pid_t, onEvent: @escaping () -> Void) {
        self.pid = pid
        self.onEvent = onEvent
        self.appElement = AXUIElementCreateApplication(pid)
        self.appElement.setTimeout(0.3)
        
        var obs: AXObserver?
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let createResult = AXObserverCreate(pid, axObserverCallback, &obs)
        
        guard createResult == .success, let observer = obs else {
            return nil
        }
        self.observer = observer
        
        // Add application-level notifications to appElement
        for notif in appNotifications {
            AXObserverAddNotification(observer, appElement, notif, selfPointer)
        }
        
        // Attach source to dedicated AXThread runloop
        let source = AXObserverGetRunLoopSource(observer)
        self.runLoopSource = source
        CFRunLoopAddSource(AXThread.shared.runLoop, source, .commonModes)
    }
    
    /// Attaches window-level notifications to an individual window element.
    public func observeWindow(_ winElement: AXUIElement) {
        guard let observer = observer else { return }
        let winID = winElement.windowID
        guard !observedWindows.contains(winID) else { return }
        observedWindows.insert(winID)
        observedWindowElements[winID] = winElement
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for notif in windowNotifications {
            AXObserverAddNotification(observer, winElement, notif, selfPointer)
        }
    }
    
    fileprivate func handleNotification(_ name: String, element: AXUIElement) {
        if name == (kAXWindowResizedNotification as String) {
            WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: element, pid: pid, isResize: true)
        } else if name == (kAXWindowMovedNotification as String) {
            WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: element, pid: pid, isResize: false)
        } else if name == (kAXUIElementDestroyedNotification as String) {
            let winID = element.windowID
            observedWindows.remove(winID)
            observedWindowElements.removeValue(forKey: winID)
            WorkAreaEnforcer.shared.removeWindow(winID: winID)
        }
        onEvent?()
    }
    
    public func invalidate() {
        if let observer = observer {
            // Unregister application-level notifications
            for notif in appNotifications {
                _ = AXObserverRemoveNotification(observer, appElement, notif)
            }
            // Unregister window-level notifications
            for winElement in observedWindowElements.values {
                for notif in windowNotifications {
                    _ = AXObserverRemoveNotification(observer, winElement, notif)
                }
            }
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(AXThread.shared.runLoop, source, .commonModes)
            CFRunLoopWakeUp(AXThread.shared.runLoop)
            runLoopSource = nil
        }
        observedWindows.removeAll()
        observedWindowElements.removeAll()
        observer = nil
        onEvent = nil
    }
    
    deinit {
        invalidate()
    }
}
