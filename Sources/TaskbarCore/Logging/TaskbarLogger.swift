// Sources/TaskbarCore/Logging/TaskbarLogger.swift

import Foundation
import os

/// Unified logging facade for Taskbar using Apple's os.Logger framework.
/// Enables structured, low-overhead diagnostic logging viewable in Console.app.
public enum TaskbarLogger: Sendable {
    /// Subsystem identifier derived from BuildConfiguration.
    public static let subsystem: String = BuildConfiguration.bundleID
    
    /// Logger for application lifecycle events (launch, screen changes, termination).
    public static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    
    /// Logger for window discovery, state changes, AX observations, and debouncing.
    public static let tracking = Logger(subsystem: subsystem, category: "Tracking")
    
    /// Logger for work area enforcer and window clamping calculations.
    public static let workArea = Logger(subsystem: subsystem, category: "WorkArea")
    
    /// Logger for macOS Dock autohide toggling and restoration.
    public static let dock = Logger(subsystem: subsystem, category: "Dock")
    
    /// Logger for taskbar UI panel rendering, button recycling, and user interactions.
    public static let ui = Logger(subsystem: subsystem, category: "UI")
}
