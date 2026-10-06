// Sources/TaskbarKit/Tracking/AXAppObserver.swift

import ApplicationServices
import Foundation

private final class AXObserverContext: @unchecked Sendable {
    private let lock = NSLock()
    private weak var target: AXAppObserver?
    private var isInvalidated = false
    
    init() {}
    
    func setTarget(_ target: AXAppObserver) {
        lock.lock()
        self.target = target
        lock.unlock()
    }
    
    func invalidate() {
        lock.lock()
        isInvalidated = true
        target = nil
        lock.unlock()
    }
    
    func perform(notification: String, element: AXUIElement) {
        lock.lock()
        guard !isInvalidated, let target = target else {
            lock.unlock()
            return
        }
        lock.unlock()
        target.handleNotification(notification, element: element)
    }
}

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let context = Unmanaged<AXObserverContext>.fromOpaque(refcon).takeUnretainedValue()
    context.perform(notification: notification as String, element: element)
}

public final class AXAppObserver: @unchecked Sendable {
    public let pid: pid_t
    public let appElement: AXUIElement
    private var observer: AXObserver?
    private var runLoopSource: CFRunLoopSource?
    public var onEvent: (() -> Void)?
    
    private var observedWindows: Set<UInt64> = []
    private var observedWindowElements: [UInt64: AXUIElement] = [:]
    
    private let context = AXObserverContext()
    private var contextPointer: UnsafeMutableRawPointer?
    private var isInvalidated = false
    private let stateLock = NSLock()
    
    // Application-level notifications (supported on appElement)
    private let appNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXWindowResizedNotification as CFString,
        kAXWindowMovedNotification as CFString
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
        
        self.context.setTarget(self)
        let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
        self.contextPointer = ptr
        
        var obs: AXObserver?
        let createResult = AXObserverCreate(pid, axObserverCallback, &obs)
        guard createResult == .success, let observer = obs else {
            self.context.invalidate()
            self.contextPointer = nil
            let address = UInt(bitPattern: ptr)
            AXThread.shared.async {
                if let raw = UnsafeMutableRawPointer(bitPattern: address) {
                    Unmanaged<AXObserverContext>.fromOpaque(raw).release()
                }
            }
            return nil
        }
        self.observer = observer
        
        // Add application-level notifications to appElement
        for notif in appNotifications {
            AXObserverAddNotification(observer, appElement, notif, ptr)
        }
        
        // Attach source to dedicated AXThread runloop
        let source = AXObserverGetRunLoopSource(observer)
        self.runLoopSource = source
        CFRunLoopAddSource(AXThread.shared.runLoop, source, .commonModes)
        
        // Observe all existing windows for this application immediately
        for win in appElement.windows {
            observeWindow(win)
        }
    }
    
    /// Attaches window-level notifications to an individual window element.
    public func observeWindow(_ winElement: AXUIElement) {
        stateLock.lock()
        guard let observer = observer, let ptr = contextPointer, !isInvalidated else {
            stateLock.unlock()
            return
        }
        let winID = winElement.windowID
        guard !observedWindows.contains(winID) else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        
        var attachedAny = false
        for notif in windowNotifications {
            let err = AXObserverAddNotification(observer, winElement, notif, ptr)
            if err == .success || err == .notificationAlreadyRegistered {
                attachedAny = true
            }
        }
        
        if attachedAny {
            stateLock.lock()
            if !isInvalidated {
                observedWindows.insert(winID)
                observedWindowElements[winID] = winElement
            }
            stateLock.unlock()
        }
    }
    
    fileprivate func handleNotification(_ name: String, element: AXUIElement) {
        if name == (kAXWindowCreatedNotification as String) {
            observeWindow(element)
        } else if name == (kAXWindowResizedNotification as String) {
            observeWindow(element)
            WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: element, pid: pid, isResize: true)
        } else if name == (kAXWindowMovedNotification as String) {
            observeWindow(element)
            WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: element, pid: pid, isResize: false)
        } else if name == (kAXUIElementDestroyedNotification as String) {
            let winID = element.windowID
            stateLock.lock()
            observedWindows.remove(winID)
            observedWindowElements.removeValue(forKey: winID)
            stateLock.unlock()
            WorkAreaEnforcer.shared.removeWindow(winID: winID)
        }
        onEvent?()
    }
    
    public func invalidate() {
        stateLock.lock()
        guard !isInvalidated else {
            stateLock.unlock()
            return
        }
        isInvalidated = true
        
        // Invalidate context first so any concurrent callback will not retain target
        context.invalidate()
        
        let ptr = contextPointer
        contextPointer = nil
        
        let obs = observer
        let src = runLoopSource
        let winElements = Array(observedWindowElements.values)
        
        observedWindows.removeAll()
        observedWindowElements.removeAll()
        observer = nil
        runLoopSource = nil
        onEvent = nil
        stateLock.unlock()
        
        if let obs = obs {
            // Unregister application-level notifications
            for notif in appNotifications {
                _ = AXObserverRemoveNotification(obs, appElement, notif)
            }
            // Unregister window-level notifications
            for winElement in winElements {
                for notif in windowNotifications {
                    _ = AXObserverRemoveNotification(obs, winElement, notif)
                }
            }
        }
        
        if let src = src {
            CFRunLoopRemoveSource(AXThread.shared.runLoop, src, .commonModes)
            CFRunLoopWakeUp(AXThread.shared.runLoop)
        }
        
        if let ptr = ptr {
            let address = UInt(bitPattern: ptr)
            AXThread.shared.async {
                if let raw = UnsafeMutableRawPointer(bitPattern: address) {
                    Unmanaged<AXObserverContext>.fromOpaque(raw).release()
                }
            }
        }
    }
    
    deinit {
        invalidate()
    }
}
