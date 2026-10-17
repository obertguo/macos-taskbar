// Sources/TaskbarKit/System/AppEnvironment.swift

@preconcurrency import Dispatch
import Foundation
import AppKit
import ApplicationServices
import TaskbarCore

// MARK: - Clock

public protocol Clock: Sendable {
    func now() -> TimeInterval
}

public struct SystemUptimeClock: Clock {
    public init() {}
    
    public func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

public final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentTime: TimeInterval
    
    public init(initialTime: TimeInterval = 0) {
        self.currentTime = initialTime
    }
    
    public func now() -> TimeInterval {
        lock.withLock { currentTime }
    }
    
    public func advance(by delta: TimeInterval) {
        lock.withLock {
            currentTime += delta
        }
    }
    
    public func advance(_ delta: TimeInterval) {
        advance(by: delta)
    }
    
    public func setTime(_ time: TimeInterval) {
        lock.withLock {
            currentTime = time
        }
    }
    
    public func setTime(time: TimeInterval) {
        setTime(time)
    }
}

// MARK: - Cancellable

public protocol Cancellable: Sendable {
    func cancel()
}

public final class AnyCancellable: Cancellable, @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (@Sendable () -> Void)?
    
    public init(_ onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }
    
    public func cancel() {
        let block: (@Sendable () -> Void)? = lock.withLock {
            let action = onCancel
            onCancel = nil
            return action
        }
        block?()
    }
}

private final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    
    func cancel() {
        lock.withLock { isCancelled = true }
    }
    
    var isCancelledStatus: Bool {
        lock.withLock { isCancelled }
    }
}

// MARK: - Scheduler

public protocol Scheduler: Sendable {
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any Cancellable
}

public extension Scheduler {
    @discardableResult
    func schedule(_ action: @escaping @Sendable () -> Void) -> any Cancellable {
        schedule(after: 0, action)
    }
}

public struct MainScheduler: Scheduler {
    public init() {}
    
    @discardableResult
    public func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any Cancellable {
        let state = CancellationState()
        let cancellable = AnyCancellable {
            state.cancel()
        }
        
        let block: @Sendable () -> Void = {
            guard !state.isCancelledStatus else { return }
            action()
        }
        
        if delay <= 0 {
            DispatchQueue.main.async(execute: block)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
        }
        return cancellable
    }
}

public struct AXThreadScheduler: Scheduler {
    public init() {}
    
    @discardableResult
    public func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any Cancellable {
        let state = CancellationState()
        let cancellable = AnyCancellable {
            state.cancel()
        }
        
        let runOnAX: @Sendable () -> Void = {
            guard !state.isCancelledStatus else { return }
            AXThread.shared.async {
                guard !state.isCancelledStatus else { return }
                action()
            }
        }
        
        if delay <= 0 {
            AXThread.shared.async {
                guard !state.isCancelledStatus else { return }
                action()
            }
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                runOnAX()
            }
        }
        
        return cancellable
    }
}

public final class TestScheduler: Scheduler, @unchecked Sendable {
    private struct ScheduledItem {
        let id: UUID
        let time: TimeInterval
        let sequence: UInt64
        let action: @Sendable () -> Void
    }
    
    private let lock = NSLock()
    private var currentTime: TimeInterval
    private var sequenceCounter: UInt64 = 0
    private var scheduledItems: [UUID: ScheduledItem] = [:]
    
    public init(initialTime: TimeInterval = 0) {
        self.currentTime = initialTime
    }
    
    public var now: TimeInterval {
        lock.withLock { currentTime }
    }
    
    public var pendingCount: Int {
        lock.withLock { scheduledItems.count }
    }
    
    @discardableResult
    public func schedule(after delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any Cancellable {
        let id = UUID()
        lock.withLock {
            sequenceCounter += 1
            let targetTime = currentTime + max(0, delay)
            scheduledItems[id] = ScheduledItem(
                id: id,
                time: targetTime,
                sequence: sequenceCounter,
                action: action
            )
        }
        return AnyCancellable { [weak self] in
            self?.remove(id: id)
        }
    }
    
    private func remove(id: UUID) {
        lock.withLock {
            _ = scheduledItems.removeValue(forKey: id)
        }
    }
    
    public func advance(by interval: TimeInterval = 0) {
        lock.lock()
        currentTime += max(0, interval)
        lock.unlock()
        
        drainReady()
    }
    
    public func advance(_ interval: TimeInterval) {
        advance(by: interval)
    }
    
    public func runAllPending() {
        while true {
            let nextAction: (@Sendable () -> Void)? = lock.withLock {
                guard let next = scheduledItems.values.min(by: {
                    if $0.time != $1.time {
                        return $0.time < $1.time
                    }
                    return $0.sequence < $1.sequence
                }) else {
                    return nil
                }
                scheduledItems.removeValue(forKey: next.id)
                if next.time > currentTime {
                    currentTime = next.time
                }
                return next.action
            }
            
            guard let action = nextAction else { break }
            action()
        }
    }
    
    private func drainReady() {
        while true {
            let nextAction: (@Sendable () -> Void)? = lock.withLock {
                guard let next = scheduledItems.values
                    .filter({ $0.time <= currentTime })
                    .min(by: {
                        if $0.time != $1.time {
                            return $0.time < $1.time
                        }
                        return $0.sequence < $1.sequence
                    }) else {
                    return nil
                }
                scheduledItems.removeValue(forKey: next.id)
                return next.action
            }
            
            guard let action = nextAction else { break }
            action()
        }
    }
}

// MARK: - WindowActionPerforming

public protocol WindowActionPerforming: Sendable {
    func performAction(_ action: ClickAction, for key: WindowKey)
    func focusWindow(_ key: WindowKey)
    func minimizeWindow(_ key: WindowKey)
    func restoreAndFocusWindow(_ key: WindowKey)
    func closeWindow(_ key: WindowKey)
    func quitApplication(pid: pid_t)
    func quitApplication(bundleIdentifier: String)
    @MainActor func launchOrActivateApp(bundleIdentifier: String, customPath: String?, store: WindowStore?)
}

public extension WindowActionPerforming {
    @MainActor
    func launchOrActivateApp(bundleIdentifier: String, customPath: String? = nil, store: WindowStore? = nil) {
        launchOrActivateApp(bundleIdentifier: bundleIdentifier, customPath: customPath, store: store)
    }
}

public struct LiveWindowActions: WindowActionPerforming {
    public init() {}
    
    public func performAction(_ action: ClickAction, for key: WindowKey) {
        WindowActions.performAction(action, for: key)
    }
    
    public func focusWindow(_ key: WindowKey) {
        WindowActions.focusWindow(key)
    }
    
    public func minimizeWindow(_ key: WindowKey) {
        WindowActions.minimizeWindow(key)
    }
    
    public func restoreAndFocusWindow(_ key: WindowKey) {
        WindowActions.restoreAndFocusWindow(key)
    }
    
    public func closeWindow(_ key: WindowKey) {
        WindowActions.closeWindow(key)
    }
    
    public func quitApplication(pid: pid_t) {
        WindowActions.quitApplication(pid: pid)
    }
    
    public func quitApplication(bundleIdentifier: String) {
        WindowActions.quitApplication(bundleIdentifier: bundleIdentifier)
    }
    
    @MainActor
    public func launchOrActivateApp(bundleIdentifier: String, customPath: String?, store: WindowStore?) {
        WindowActions.launchOrActivateApp(bundleIdentifier: bundleIdentifier, customPath: customPath, store: store)
    }
}

public final class SpyWindowActions: WindowActionPerforming, @unchecked Sendable {
    public enum Invocation: Equatable, Sendable {
        case performAction(action: ClickAction, key: WindowKey)
        case focusWindow(key: WindowKey)
        case minimizeWindow(key: WindowKey)
        case restoreAndFocusWindow(key: WindowKey)
        case closeWindow(key: WindowKey)
        case quitApplicationPID(pid: pid_t)
        case quitApplicationBundleID(bundleIdentifier: String)
        case launchOrActivateApp(bundleIdentifier: String, customPath: String?, store: WindowStore?)
        
        public static func == (lhs: Invocation, rhs: Invocation) -> Bool {
            switch (lhs, rhs) {
            case (.performAction(let a1, let k1), .performAction(let a2, let k2)):
                return a1 == a2 && k1 == k2
            case (.focusWindow(let k1), .focusWindow(let k2)):
                return k1 == k2
            case (.minimizeWindow(let k1), .minimizeWindow(let k2)):
                return k1 == k2
            case (.restoreAndFocusWindow(let k1), .restoreAndFocusWindow(let k2)):
                return k1 == k2
            case (.closeWindow(let k1), .closeWindow(let k2)):
                return k1 == k2
            case (.quitApplicationPID(let p1), .quitApplicationPID(let p2)):
                return p1 == p2
            case (.quitApplicationBundleID(let b1), .quitApplicationBundleID(let b2)):
                return b1 == b2
            case (.launchOrActivateApp(let b1, let p1, let s1), .launchOrActivateApp(let b2, let p2, let s2)):
                return b1 == b2 && p1 == p2 && s1 === s2
            default:
                return false
            }
        }
    }
    
    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    
    public init(invocations: [Invocation] = []) {
        self._invocations = invocations
    }
    
    public var invocations: [Invocation] {
        lock.withLock { _invocations }
    }
    
    public func clear() {
        lock.withLock {
            _invocations.removeAll()
        }
    }
    
    public func performAction(_ action: ClickAction, for key: WindowKey) {
        lock.withLock {
            _invocations.append(.performAction(action: action, key: key))
        }
    }
    
    public func focusWindow(_ key: WindowKey) {
        lock.withLock {
            _invocations.append(.focusWindow(key: key))
        }
    }
    
    public func minimizeWindow(_ key: WindowKey) {
        lock.withLock {
            _invocations.append(.minimizeWindow(key: key))
        }
    }
    
    public func restoreAndFocusWindow(_ key: WindowKey) {
        lock.withLock {
            _invocations.append(.restoreAndFocusWindow(key: key))
        }
    }
    
    public func closeWindow(_ key: WindowKey) {
        lock.withLock {
            _invocations.append(.closeWindow(key: key))
        }
    }
    
    public func quitApplication(pid: pid_t) {
        lock.withLock {
            _invocations.append(.quitApplicationPID(pid: pid))
        }
    }
    
    public func quitApplication(bundleIdentifier: String) {
        lock.withLock {
            _invocations.append(.quitApplicationBundleID(bundleIdentifier: bundleIdentifier))
        }
    }
    
    @MainActor
    public func launchOrActivateApp(bundleIdentifier: String, customPath: String?, store: WindowStore?) {
        lock.withLock {
            _invocations.append(.launchOrActivateApp(bundleIdentifier: bundleIdentifier, customPath: customPath, store: store))
        }
    }
}

public extension SpyWindowActions.Invocation {
    static func quitApplication(pid: pid_t) -> SpyWindowActions.Invocation {
        .quitApplicationPID(pid: pid)
    }
    
    static func quitApplication(bundleIdentifier: String) -> SpyWindowActions.Invocation {
        .quitApplicationBundleID(bundleIdentifier: bundleIdentifier)
    }
    
    static func performAction(_ action: ClickAction, _ key: WindowKey) -> SpyWindowActions.Invocation {
        .performAction(action: action, key: key)
    }
    
    static func focusWindow(_ key: WindowKey) -> SpyWindowActions.Invocation {
        .focusWindow(key: key)
    }
    
    static func minimizeWindow(_ key: WindowKey) -> SpyWindowActions.Invocation {
        .minimizeWindow(key: key)
    }
    
    static func restoreAndFocusWindow(_ key: WindowKey) -> SpyWindowActions.Invocation {
        .restoreAndFocusWindow(key: key)
    }
    
    static func closeWindow(_ key: WindowKey) -> SpyWindowActions.Invocation {
        .closeWindow(key: key)
    }
}

// MARK: - DockServicing

public protocol DockServicing: Sendable {
    var isDockHidden: Bool { get }
    var currentAppliedDelay: Double? { get }
    func hideDock(delay: Double)
    func restoreDock()
}

public extension DockServicing {
    func hideDock() {
        hideDock(delay: TaskbarConstants.Dock.defaultAutohideDelaySeconds)
    }
}

public final class LiveDockService: DockServicing, @unchecked Sendable {
    public init() {}
    
    public var isDockHidden: Bool {
        DockController.shared.isDockHidden
    }
    
    public var currentAppliedDelay: Double? {
        DockController.shared.currentAppliedDelay
    }
    
    public func hideDock(delay: Double) {
        DockController.shared.hideDock(delay: delay)
    }
    
    public func restoreDock() {
        DockController.shared.restoreDock()
    }
}

public final class MockDockService: DockServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var _isDockHidden: Bool
    private var _currentAppliedDelay: Double?
    private var _hideDockCallCount: Int = 0
    private var _restoreDockCallCount: Int = 0
    
    public init(isDockHidden: Bool = false, currentAppliedDelay: Double? = nil) {
        self._isDockHidden = isDockHidden
        self._currentAppliedDelay = currentAppliedDelay
    }
    
    public var isDockHidden: Bool {
        get { lock.withLock { _isDockHidden } }
        set { lock.withLock { _isDockHidden = newValue } }
    }
    
    public var currentAppliedDelay: Double? {
        get { lock.withLock { _currentAppliedDelay } }
        set { lock.withLock { _currentAppliedDelay = newValue } }
    }
    
    public var hideDockCallCount: Int {
        get { lock.withLock { _hideDockCallCount } }
        set { lock.withLock { _hideDockCallCount = newValue } }
    }
    
    public var restoreDockCallCount: Int {
        get { lock.withLock { _restoreDockCallCount } }
        set { lock.withLock { _restoreDockCallCount = newValue } }
    }
    
    public func hideDock(delay: Double) {
        lock.withLock {
            _hideDockCallCount += 1
            _isDockHidden = true
            _currentAppliedDelay = delay
        }
    }
    
    public func restoreDock() {
        lock.withLock {
            _restoreDockCallCount += 1
            _isDockHidden = false
            _currentAppliedDelay = nil
        }
    }
    
    public func reset() {
        lock.withLock {
            _isDockHidden = false
            _currentAppliedDelay = nil
            _hideDockCallCount = 0
            _restoreDockCallCount = 0
        }
    }
}

// MARK: - WindowSource

@MainActor
public protocol WindowSource: AnyObject {
    var store: WindowStore { get }
    var onWindowsChanged: (() -> Void)? { get set }
    func startTracking()
    func stopTracking()
}

// MARK: - AppEnvironment

public struct AppEnvironment: Sendable {
    public var clock: any Clock
    public var scheduler: any Scheduler
    public var windowActions: any WindowActionPerforming
    public var dockService: any DockServicing
    
    public init(
        clock: any Clock = SystemUptimeClock(),
        scheduler: any Scheduler = MainScheduler(),
        windowActions: any WindowActionPerforming = LiveWindowActions(),
        dockService: any DockServicing = LiveDockService()
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.windowActions = windowActions
        self.dockService = dockService
    }
    
    public static let live: AppEnvironment = AppEnvironment(
        clock: SystemUptimeClock(),
        scheduler: AXThreadScheduler(),
        windowActions: LiveWindowActions(),
        dockService: LiveDockService()
    )
    
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: AppEnvironment = .live
    
    public static var current: AppEnvironment {
        get {
            lock.withLock { _current }
        }
        set {
            lock.withLock { _current = newValue }
        }
    }
    
    public static func reset() {
        lock.withLock {
            _current = .live
        }
    }
}
