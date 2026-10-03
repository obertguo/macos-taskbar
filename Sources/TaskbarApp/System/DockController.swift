// Sources/TaskbarApp/System/DockController.swift

import Foundation

public final class DockController: @unchecked Sendable {
    public static let shared = DockController()
    
    private static let originalStateKey = "com.taskbar.original_dock_state"
    private let lock = NSLock()
    private var _isDockHidden: Bool = false
    
    public var isDockHidden: Bool {
        lock.withLock { _isDockHidden }
    }
    
    private struct SavedDockState: Codable {
        let autohide: Bool
        let autohideDelay: Double?
    }
    
    private init() {
        captureOriginalStateIfFirstRun()
    }
    
    /// Snapshots the user's original Dock configuration on the very first launch.
    private func captureOriginalStateIfFirstRun() {
        guard UserDefaults.standard.data(forKey: Self.originalStateKey) == nil else {
            return
        }
        
        let autohide = querySystemAutohide()
        let delay = querySystemAutohideDelay()
        
        // If delay is already ~1000s (e.g. from a prior test session), treat as unconfigured (nil)
        let cleanDelay = (delay != nil && delay! >= 999.0) ? nil : delay
        
        let state = SavedDockState(autohide: autohide, autohideDelay: cleanDelay)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.originalStateKey)
        }
    }
    
    private func querySystemAutohide() -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "autohide"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try? process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return false }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "1" || trimmed.lowercased() == "true"
    }
    
    private func querySystemAutohideDelay() -> Double? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.dock", "autohide-delay"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try? process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }
    
    /// Hides the system Dock by applying a 1000-second hover delay and enabling autohide.
    public func hideDock() {
        lock.lock()
        defer { lock.unlock() }
        
        captureOriginalStateIfFirstRun()
        
        guard !_isDockHidden else { return }
        
        Self.executeCommand("/usr/bin/defaults", arguments: ["write", "com.apple.dock", "autohide", "-bool", "true"])
        Self.executeCommand("/usr/bin/defaults", arguments: ["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        Self.executeCommand("/usr/bin/killall", arguments: ["Dock"])
        
        _isDockHidden = true
        print("[DockController] System Dock hidden (autohide-delay: 1000s).")
    }
    
    /// Restores the user's original Dock preferences and restarts the Dock process.
    public func restoreDock() {
        lock.lock()
        defer { lock.unlock() }
        
        guard _isDockHidden else { return }
        Self.restoreDockInternal()
        _isDockHidden = false
    }
    
    /// Static synchronous restore callable from POSIX signal handlers, atexit, or termination.
    public static func restoreDockSync() {
        if shared.isDockHidden {
            shared.restoreDock()
        }
    }
    
    private static func restoreDockInternal() {
        var originalAutohide = false
        var originalDelay: Double? = nil
        
        if let data = UserDefaults.standard.data(forKey: originalStateKey),
           let saved = try? JSONDecoder().decode(SavedDockState.self, from: data) {
            originalAutohide = saved.autohide
            originalDelay = saved.autohideDelay
        }
        
        // Restore autohide delay
        if let delay = originalDelay {
            executeCommand("/usr/bin/defaults", arguments: ["write", "com.apple.dock", "autohide-delay", "-float", "\(delay)"])
        } else {
            executeCommand("/usr/bin/defaults", arguments: ["delete", "com.apple.dock", "autohide-delay"])
        }
        
        // Restore autohide flag
        executeCommand("/usr/bin/defaults", arguments: ["write", "com.apple.dock", "autohide", "-bool", originalAutohide ? "true" : "false"])
        
        // Restart Dock
        executeCommand("/usr/bin/killall", arguments: ["Dock"])
        
        print("[DockController] System Dock restored to original settings.")
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
