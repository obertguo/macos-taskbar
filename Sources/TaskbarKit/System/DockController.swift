// Sources/TaskbarKit/System/DockController.swift

import Foundation
import TaskbarCore

public final class DockController: @unchecked Sendable {
    public static let shared = DockController()
    
    public static let originalStateKey = TaskbarConstants.Dock.originalStateUserDefaultsKey
    public static let sentinelKey = "com.taskbar.dockCurrentlyOverriddenByTaskbar"
    
    /// Target domain for macOS Dock preferences. Defaults to "com.apple.dock".
    public nonisolated(unsafe) static var preferencesDomain: String = TaskbarConstants.Dock.domain
    
    /// Optional closure overriding the Dock restart command (`killall Dock`).
    /// Exposed for testing to prevent killing the system Dock daemon during automated runs.
    public nonisolated(unsafe) static var dockRestartHandler: (@Sendable () -> Void)? = nil
    
    private let lock = NSLock()
    private var _isDockHidden: Bool = false
    private var _currentAppliedDelay: Double?
    
    /// Dedicated private serial queue for asynchronous Dock preference writes and restart execution.
    private let dockQueue = DispatchQueue(label: "com.taskbar.dock-controller", qos: .utility)
    private static let queueSpecificKey = DispatchSpecificKey<Void>()
    
    public var isDockHidden: Bool {
        lock.withLock { _isDockHidden }
    }
    
    public var currentAppliedDelay: Double? {
        lock.withLock { _currentAppliedDelay }
    }
    
    public struct SavedDockState: Codable, Equatable, Sendable {
        public let autohide: Bool
        public let autohideDelay: Double?
        
        public init(autohide: Bool, autohideDelay: Double?) {
            self.autohide = autohide
            self.autohideDelay = autohideDelay
        }
    }
    
    private init() {
        dockQueue.setSpecific(key: Self.queueSpecificKey, value: ())
        let wasOverridden = UserDefaults.standard.bool(forKey: Self.sentinelKey)
        if wasOverridden {
            _isDockHidden = true
        } else {
            captureOriginalStateIfFirstRun()
        }
    }
    
    /// Reconciles Dock state on application launch, providing crash recovery for unclean terminations.
    public func reconcileOnLaunch(shouldHideDock: Bool, delay: Double = TaskbarConstants.Dock.defaultAutohideDelaySeconds) {
        let wasOverridden = UserDefaults.standard.bool(forKey: Self.sentinelKey)
        
        if wasOverridden {
            TaskbarLogger.dock.warning("Detected dirty session from prior run (sentinel active). Reconciling Dock state...")
            if !shouldHideDock {
                // User does not want dock hidden. Restore the dock to the saved baseline! Clear the sentinel.
                restoreDock()
            } else {
                // User wants dock hidden. PRESERVE the existing baseline snapshot (DO NOT overwrite it with current system state where autohide-delay=1000).
                // Re-apply hide settings to ensure consistency, and keep sentinel true.
                hideDock(delay: delay, force: true)
            }
        } else {
            // Clean exit or fresh launch:
            captureOriginalStateIfFirstRun()
            if shouldHideDock {
                hideDock(delay: delay)
            } else if isDockHidden {
                restoreDock()
            }
        }
    }
    
    /// Snapshots the user's original Dock configuration on the very first launch.
    /// Never overwrites an existing snapshot.
    public func captureOriginalStateIfFirstRun() {
        guard UserDefaults.standard.data(forKey: Self.originalStateKey) == nil else {
            return
        }
        
        // If the dock is currently marked as overridden, do not capture the overridden state as original!
        if UserDefaults.standard.bool(forKey: Self.sentinelKey) {
            return
        }
        
        let autohide = Self.querySystemAutohide()
        let delay = Self.querySystemAutohideDelay()
        
        // If delay is already ~1000s (e.g. from an unmanaged prior session), treat as unconfigured (nil)
        let cleanDelay = (delay != nil && delay! >= TaskbarConstants.Dock.defaultAutohideDelaySeconds - 1.0) ? nil : delay
        
        let state = SavedDockState(autohide: autohide, autohideDelay: cleanDelay)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.originalStateKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Reads the system Dock autohide preference in-process using `CFPreferencesCopyAppValue` without spawning subprocesses.
    public static func querySystemAutohide() -> Bool {
        guard let value = CFPreferencesCopyAppValue(
            TaskbarConstants.Dock.autohideKey as CFString,
            preferencesDomain as CFString
        ) else {
            return false
        }
        if let boolVal = value as? Bool {
            return boolVal
        }
        if let num = value as? NSNumber {
            return num.boolValue
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return false
    }
    
    /// Reads the system Dock autohide delay preference in-process using `CFPreferencesCopyAppValue` without spawning subprocesses.
    public static func querySystemAutohideDelay() -> Double? {
        guard let value = CFPreferencesCopyAppValue(
            TaskbarConstants.Dock.autohideDelayKey as CFString,
            preferencesDomain as CFString
        ) else {
            return nil
        }
        if let num = value as? NSNumber {
            return num.doubleValue
        }
        if let dbl = value as? Double {
            return dbl
        }
        if CFGetTypeID(value) == CFNumberGetTypeID() {
            var d: Double = 0
            if CFNumberGetValue((value as! CFNumber), .doubleType, &d) {
                return d
            }
        }
        if let str = value as? String, let d = Double(str) {
            return d
        }
        return nil
    }
    
    /// Hides the system Dock by applying the specified autohide hover delay and enabling autohide.
    /// Preference writes and Dock reload are executed asynchronously on a utility serial queue.
    public func hideDock(delay: Double = TaskbarConstants.Dock.defaultAutohideDelaySeconds, force: Bool = false) {
        lock.lock()
        // If already hidden with the exact same delay and not forced, no-op
        if !force && _isDockHidden, let current = _currentAppliedDelay, abs(current - delay) < 0.01 {
            lock.unlock()
            return
        }
        _isDockHidden = true
        _currentAppliedDelay = delay
        lock.unlock()
        
        // Ensure baseline snapshot is saved before applying override
        captureOriginalStateIfFirstRun()
        
        // Set dirty-session sentinel
        UserDefaults.standard.set(true, forKey: Self.sentinelKey)
        UserDefaults.standard.synchronize()
        
        dockQueue.async {
            Self.performHideInternal(delay: delay)
        }
    }
    
    /// Restores the user's original Dock preferences and restarts the Dock process.
    /// Preference writes and Dock reload are executed asynchronously on a utility serial queue.
    public func restoreDock() {
        lock.lock()
        _isDockHidden = false
        _currentAppliedDelay = nil
        lock.unlock()
        
        // Clear dirty-session sentinel
        UserDefaults.standard.set(false, forKey: Self.sentinelKey)
        UserDefaults.standard.synchronize()
        
        dockQueue.async {
            Self.performRestoreInternal()
        }
    }
    
    /// Static synchronous restore callable from POSIX signal handlers, atexit, or termination.
    public static func restoreDockSync() {
        let shouldRestore = shared.lock.withLock {
            let hidden = shared._isDockHidden
            shared._isDockHidden = false
            shared._currentAppliedDelay = nil
            return hidden
        } || UserDefaults.standard.bool(forKey: sentinelKey)
        
        UserDefaults.standard.set(false, forKey: sentinelKey)
        UserDefaults.standard.synchronize()
        
        guard shouldRestore else { return }
        
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            performRestoreInternal()
        } else {
            shared.dockQueue.sync {
                performRestoreInternal()
            }
        }
    }
    
    /// Synchronously waits for all pending operations on the DockController serial utility queue to finish.
    public func waitForQueue() {
        if DispatchQueue.getSpecific(key: Self.queueSpecificKey) != nil {
            return
        }
        dockQueue.sync {}
    }
    
    /// Resets in-memory state of the controller. For test use only.
    public func resetStateForTesting(isDockHidden: Bool = false, currentAppliedDelay: Double? = nil) {
        lock.withLock {
            _isDockHidden = isDockHidden
            _currentAppliedDelay = currentAppliedDelay
        }
    }
    
    private static func performHideInternal(delay: Double) {
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideKey as CFString,
            kCFBooleanTrue,
            preferencesDomain as CFString
        )
        let delayNumber = NSNumber(value: delay) as CFNumber
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideDelayKey as CFString,
            delayNumber,
            preferencesDomain as CFString
        )
        CFPreferencesAppSynchronize(preferencesDomain as CFString)
        restartDock()
        TaskbarLogger.dock.info("System Dock hidden (autohide-delay: \(delay)s).")
    }
    
    private static func performRestoreInternal() {
        var originalAutohide = false
        var originalDelay: Double? = nil
        
        if let data = UserDefaults.standard.data(forKey: originalStateKey),
           let saved = try? JSONDecoder().decode(SavedDockState.self, from: data) {
            originalAutohide = saved.autohide
            originalDelay = saved.autohideDelay
        }
        
        // Restore autohide delay
        if let delay = originalDelay {
            let delayNumber = NSNumber(value: delay) as CFNumber
            CFPreferencesSetAppValue(
                TaskbarConstants.Dock.autohideDelayKey as CFString,
                delayNumber,
                preferencesDomain as CFString
            )
        } else {
            CFPreferencesSetAppValue(
                TaskbarConstants.Dock.autohideDelayKey as CFString,
                nil,
                preferencesDomain as CFString
            )
        }
        
        // Restore autohide flag
        let autohideBool: CFBoolean = originalAutohide ? kCFBooleanTrue : kCFBooleanFalse
        CFPreferencesSetAppValue(
            TaskbarConstants.Dock.autohideKey as CFString,
            autohideBool,
            preferencesDomain as CFString
        )
        
        CFPreferencesAppSynchronize(preferencesDomain as CFString)
        restartDock()
        TaskbarLogger.dock.info("System Dock restored to original settings.")
    }
    
    private static func restartDock() {
        if let customHandler = dockRestartHandler {
            customHandler()
        } else {
            executeCommand(TaskbarConstants.Dock.killallBinaryPath, arguments: [TaskbarConstants.Dock.processName])
        }
    }
    
    @discardableResult
    private static func executeCommand(_ executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
