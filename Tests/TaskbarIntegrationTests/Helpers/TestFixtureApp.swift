// Tests/TaskbarIntegrationTests/Helpers/TestFixtureApp.swift

import Foundation
import AppKit
import ApplicationServices
import TaskbarKit

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
    
    public var runningApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }
    
    public func windowElement(index: Int = 1) -> AXUIElement? {
        guard let pid = runningApp?.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        let wins = appElement.windows
        guard wins.count >= index else { return nil }
        return wins[index - 1]
    }
    
    /// Static teardown for any running instances of an application.
    public static func terminateApp(appName: String = "TextEdit", bundleIdentifier: String = "com.apple.TextEdit") {
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleIdentifier {
            app.terminate()
            if !app.isTerminated {
                app.forceTerminate()
            }
        }
        let script = """
        if application "\(appName)" is running then
            try
                tell application "\(appName)" to quit saving no
            end try
        end if
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Polls until the window element at index is available via Accessibility API.
    public func waitForWindowElement(index: Int = 1, timeoutSeconds: Double = 3.0) async -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let win = windowElement(index: index) {
                return win
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return windowElement(index: index)
    }

    private actor TestFixtureQueue {
        static let shared = TestFixtureQueue()
        private var isBusy = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        
        func acquire() async {
            if !isBusy {
                isBusy = true
                return
            }
            await withCheckedContinuation { cont in
                waiters.append(cont)
            }
        }
        
        func release() {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                isBusy = false
            }
        }
    }
    
    /// Launches the application and creates an empty untitled document window.
    @discardableResult
    public static func launchTextEdit(documentTitle: String = "TaskbarTestDoc") async throws -> TestFixtureApp {
        await TestFixtureQueue.shared.acquire()
        do {
            // Ensure any previous dangling instances are cleanly quit before creating our fixture
            terminateApp(appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
            try await Task.sleep(nanoseconds: 200_000_000)
            
            let fixture = TestFixtureApp(appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
            
            // Launch TextEdit and create a document
            let script = """
            tell application "TextEdit"
                activate
                try
                    close every document saving no
                end try
                make new document with properties {name:"\(documentTitle)"}
            end tell
            """
            _ = try fixture.runAppleScript(script)
            
            // Give macOS WindowServer and AX time to register the window
            _ = await fixture.waitForWindowElement(index: 1, timeoutSeconds: 3.0)
            return fixture
        } catch {
            Task { await TestFixtureQueue.shared.release() }
            throw error
        }
    }
    
    /// Terminates the application and cleans up all documents without saving.
    public func terminate() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isTerminated else { return }
        isTerminated = true
        
        Self.terminateApp(appName: appName, bundleIdentifier: bundleIdentifier)
        Task { await TestFixtureQueue.shared.release() }
    }
    
    /// Creates an additional document window for the fixture app.
    public func createDocument(documentTitle: String) throws {
        let script = """
        tell application "\(appName)"
            make new document with properties {name:"\(documentTitle)"}
        end tell
        """
        _ = try runAppleScript(script)
    }
    
    // MARK: - Window Manipulations
    
    /// Queries the number of visible windows for the fixture app.
    public func windowCount() throws -> Int {
        if let pid = runningApp?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            let wins = appElement.windows
            if !wins.isEmpty {
                return wins.count
            }
        }
        let script = """
        tell application "\(appName)"
            return count of windows
        end tell
        """
        let output = (try? runAppleScript(script))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Int(output) ?? 0
    }
    
    /// Minimizes window at the given 1-based index.
    public func minimizeWindow(index: Int = 1) throws {
        if let win = windowElement(index: index) {
            let res = AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            if res != .success || !win.isMinimized {
                if let minButton = win.minimizeButton {
                    AXUIElementPerformAction(minButton, kAXPressAction as CFString)
                }
            }
        }
        
        let script = """
        tell application "\(appName)"
            if (count of windows) >= \(index) then
                set miniaturized of window \(index) to true
            end if
        end tell
        """
        _ = try? runAppleScript(script)
    }
    
    /// Restores / deminiaturizes window at the given 1-based index.
    public func restoreWindow(index: Int = 1) throws {
        if let win = windowElement(index: index) {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
        
        let script = """
        tell application "\(appName)"
            activate
            if (count of windows) >= \(index) then
                set miniaturized of window \(index) to false
            end if
        end tell
        """
        _ = try? runAppleScript(script)
    }
    
    /// Checks whether the window at the given index is currently minimized.
    public func isWindowMinimized(index: Int = 1) throws -> Bool {
        if let win = windowElement(index: index) {
            return win.isMinimized
        }
        let script = """
        tell application "\(appName)"
            if (count of windows) >= \(index) then
                return miniaturized of window \(index)
            else
                return false
            end if
        end tell
        """
        let output = (try? runAppleScript(script))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.lowercased() == "true"
    }
    
    /// Sets the document name / title of window at the given index.
    public func setTitle(_ title: String, index: Int = 1) throws {
        let script = """
        tell application "\(appName)"
            if (count of documents) >= \(index) then
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
