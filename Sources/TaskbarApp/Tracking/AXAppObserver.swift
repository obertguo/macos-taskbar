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
    appObserver.handleNotification(notification as String)
}

public final class AXAppObserver: @unchecked Sendable {
    public let pid: pid_t
    public let appElement: AXUIElement
    private var observer: AXObserver?
    private var runLoopSource: CFRunLoopSource?
    public var onEvent: (() -> Void)?
    
    private let observedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXTitleChangedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
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
        
        // Add notifications to the app element
        for notif in observedNotifications {
            AXObserverAddNotification(observer, appElement, notif, selfPointer)
        }
        
        // Attach source to dedicated AXThread
        let source = AXObserverGetRunLoopSource(observer)
        self.runLoopSource = source
        CFRunLoopAddSource(AXThread.shared.runLoop, source, .commonModes)
    }
    
    fileprivate func handleNotification(_ name: String) {
        onEvent?()
    }
    
    public func invalidate() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(AXThread.shared.runLoop, source, .commonModes)
            runLoopSource = nil
        }
        observer = nil
    }
    
    deinit {
        invalidate()
    }
}
