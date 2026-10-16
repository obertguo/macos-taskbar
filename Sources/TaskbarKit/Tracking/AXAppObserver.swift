// Sources/TaskbarKit/Tracking/AXAppObserver.swift

@preconcurrency import ApplicationServices
import Foundation
import TaskbarCore

public struct AXNotificationEvent: Sendable {
    public let pid: pid_t
    public let notification: String
    public let element: AXUIElement
    public let resolvedWindowID: UInt64?
    
    public init(pid: pid_t, notification: String, element: AXUIElement, resolvedWindowID: UInt64?) {
        self.pid = pid
        self.notification = notification
        self.element = element
        self.resolvedWindowID = resolvedWindowID
    }
}

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
    public var onNotification: ((AXNotificationEvent) -> Void)?
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
    
    public init?(pid: pid_t, onNotification: @escaping (AXNotificationEvent) -> Void) {
        self.pid = pid
        self.onNotification = onNotification
        self.onEvent = nil
        self.appElement = AXUIElementCreateApplication(pid)
        self.appElement.setTimeout(TaskbarConstants.Timing.axTimeout)
        
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
    
    public convenience init?(pid: pid_t, onEvent: @escaping () -> Void) {
        self.init(pid: pid, onNotification: { _ in onEvent() })
        self.onEvent = onEvent
    }
    
    /// Attaches window-level notifications to an individual window element.
    public func observeWindow(_ winElement: AXUIElement) {
        stateLock.lock()
        guard let observer = observer, let ptr = contextPointer, !isInvalidated else {
            stateLock.unlock()
            return
        }
        guard let winID = winElement.windowID else {
            stateLock.unlock()
            return
        }
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
    
    internal func isWindowObserved(_ id: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return observedWindows.contains(id)
    }
    
    internal func registerObservedWindowForTesting(id: UInt64, element: AXUIElement) {
        stateLock.lock()
        observedWindows.insert(id)
        observedWindowElements[id] = element
        stateLock.unlock()
    }
    
    internal func handleNotification(_ name: String, element: AXUIElement) {
        var resolvedWindowID: UInt64? = element.windowID
        if resolvedWindowID == nil {
            stateLock.lock()
            for (wid, storedElement) in observedWindowElements {
                if CFEqual(storedElement, element) {
                    resolvedWindowID = wid
                    break
                }
            }
            stateLock.unlock()
        }
        
        if name == (kAXWindowCreatedNotification as String) {
            observeWindow(element)
        } else if name == (kAXWindowResizedNotification as String) {
            observeWindow(element)
            WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: element, pid: pid, isResize: true)
        } else if name == (kAXWindowMovedNotification as String) {
            observeWindow(element)
            WorkAreaEnforcer.shared.handleWindowMovedOrResized(element: element, pid: pid, isResize: false)
        } else if name == (kAXUIElementDestroyedNotification as String) {
            if let wid = resolvedWindowID {
                stateLock.lock()
                observedWindows.remove(wid)
                observedWindowElements.removeValue(forKey: wid)
                stateLock.unlock()
                WorkAreaEnforcer.shared.removeWindow(winID: wid)
            }
        }
        
        let event = AXNotificationEvent(
            pid: pid,
            notification: name,
            element: element,
            resolvedWindowID: resolvedWindowID
        )
        onNotification?(event)
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
        let removedWindows = observedWindows
        let winElements = Array(observedWindowElements.values)
        observedWindows.removeAll()
        observedWindowElements.removeAll()
        observer = nil
        runLoopSource = nil
        onEvent = nil
        onNotification = nil
        stateLock.unlock()
        
        for wid in removedWindows {
            WorkAreaEnforcer.shared.removeWindow(winID: wid)
        }
        
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
