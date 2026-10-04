// Tests/TaskbarIntegrationTests/Helpers/TestFixtureApp.swift

import Foundation
import AppKit

/// Deterministic, self-cleaning fixture controller for real macOS applications (e.g. TextEdit).
/// Manages window lifecycle via AppleScript and ensures zero dangling processes.
public final class TestFixtureApp: @unchecked Sendable {
    public let appName: String
    public let bundleIdentifier: String
    private var isTerminated = false
    private let lock = NSLock()
    
    public init(appName: String = "TextEdit", bundleIdentifier: String = "com.apple.TextEdit") {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
    }
    
    deinit {
        terminate()
    }
    
    // MARK: - Process Lifecycle
    
    /// Launches the application and creates an empty untitled document window.
    @discardableResult
    public static func launchTextEdit(documentTitle: String = "TaskbarTestDoc") async throws -> TestFixtureApp {
        let fixture = TestFixtureApp(appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
        
        // Ensure any previous dangling instances are cleanly quit
        fixture.terminate()
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Launch TextEdit and create a document
        let script = """
        tell application "TextEdit"
            activate
            make new document with properties {name:"\(documentTitle)"}
        end tell
        """
        _ = try fixture.runAppleScript(script)
        
        // Give macOS WindowServer time to register the window
        try await Task.sleep(nanoseconds: 300_000_000)
        return fixture
    }
    
    /// Terminates the application and cleans up all documents without saving.
    public func terminate() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isTerminated else { return }
        isTerminated = true
        
        let script = """
        if application "\(appName)" is running then
            tell application "\(appName)" to quit saving no
        end if
        """
        _ = try? runAppleScript(script)
    }
    
    // MARK: - Window Manipulations
    
    /// Queries the number of visible windows for the fixture app.
    public func windowCount() throws -> Int {
        let script = """
        tell application "System Events"
            if exists process "\(appName)" then
                return count of (windows of process "\(appName)")
            else
                return 0
            end if
        end tell
        """
        let output = try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output) ?? 0
    }
    
    /// Minimizes window at the given 1-based index.
    public func minimizeWindow(index: Int = 1) throws {
        let script = """
        tell application "System Events"
            tell process "\(appName)"
                if (count of windows) >= \(index) then
                    set value of attribute "AXMinimized" of window \(index) to true
                end if
            end tell
        end tell
        """
        _ = try runAppleScript(script)
    }
    
    /// Restores / deminiaturizes window at the given 1-based index.
    public func restoreWindow(index: Int = 1) throws {
        let script = """
        tell application "System Events"
            tell process "\(appName)"
                if (count of windows) >= \(index) then
                    set value of attribute "AXMinimized" of window \(index) to false
                end if
            end tell
        end tell
        """
        _ = try runAppleScript(script)
    }
    
    /// Checks whether the window at the given index is currently minimized.
    public func isWindowMinimized(index: Int = 1) throws -> Bool {
        let script = """
        tell application "System Events"
            tell process "\(appName)"
                if (count of windows) >= \(index) then
                    return value of attribute "AXMinimized" of window \(index)
                else
                    return false
                end if
            end tell
        end tell
        """
        let output = try runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.lowercased() == "true"
    }
    
    /// Sets the document name / title of window at the given index.
    public func setTitle(_ title: String, index: Int = 1) throws {
        let script = """
        tell application "\(appName)"
            if (count of windows) >= \(index) then
                set name of document \(index) to "\(title)"
            end if
        end tell
        """
        _ = try runAppleScript(script)
    }
    
    /// Closes the window at the given index without saving.
    public func closeWindow(index: Int = 1) throws {
        let script = """
        tell application "\(appName)"
            if (count of windows) >= \(index) then
                close window \(index) saving no
            end if
        end tell
        """
        _ = try runAppleScript(script)
    }
    
    /// Brings the window at the given index to the front and activates it.
    public func activateWindow(index: Int = 1) throws {
        let script = """
        tell application "System Events"
            tell process "\(appName)"
                set frontmost to true
                if (count of windows) >= \(index) then
                    perform action "AXRaise" of window \(index)
                end if
            end tell
        end tell
        """
        _ = try runAppleScript(script)
    }
    
    // MARK: - Subprocess Execution
    
    /// Executes an AppleScript string via `/usr/bin/osascript`.
    @discardableResult
    public func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        
        if process.terminationStatus != 0 {
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown AppleScript error"
            throw NSError(domain: "TestFixtureApp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errMsg])
        }
        
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
