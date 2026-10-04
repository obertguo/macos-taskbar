// Sources/TaskbarCore/Config/TaskbarConstants.swift

import Foundation
import CoreGraphics

public enum TaskbarConstants {
    
    // MARK: - Layout & UI Metrics
    public enum Layout {
        public static let defaultMaxButtonWidth: Double = 160.0
        public static let defaultMinButtonWidth: Double = 80.0
        public static let defaultButtonSpacing: Double = 2.0
        public static let defaultTitleVisibilityThreshold: Double = 50.0
        
        public static let defaultBarHeight: Double = 30.0
        public static let minimumButtonHeight: CGFloat = 18.0
        public static let taskbarVerticalPadding: CGFloat = 2.0
        
        public static let startButtonWidthRetro: CGFloat = 56.0
        public static let startButtonWidthHybrid: CGFloat = 62.0
        public static let startButtonLeadingMargin: CGFloat = 3.0
        public static let startButtonTrailingMargin: CGFloat = 4.0
        public static let taskbarTrailingMargin: CGFloat = 4.0
        
        public static let overflowButtonWidth: CGFloat = 26.0
        public static let overflowButtonTrailingMargin: CGFloat = 3.0
        public static let overflowMenuVerticalOffset: CGFloat = 2.0
        
        public static let iconSize: CGFloat = 16.0
        public static let taskButtonIconMarginRetro: CGFloat = 4.0
        public static let taskButtonIconMarginHybrid: CGFloat = 6.0
        
        public static let dimmedButtonAlpha: CGFloat = 0.6
    }
    
    // MARK: - Work Area & Geometry
    public enum WorkArea {
        public static let minimumWindowHeight: CGFloat = 100.0
        public static let overlapTolerance: CGFloat = 2.0
        public static let screenHeightMaximizedRatio: CGFloat = 0.45
        public static let screenTopToleranceBase: CGFloat = 120.0
        public static let screenTopToleranceRatio: CGFloat = 0.20
        public static let clampingRecursionGuardDelta: CGFloat = 1.0
        public static let fullScreenDisplayTolerance: CGFloat = 2.0
        public static let minimumWindowDimension: CGFloat = 50.0
    }
    
    // MARK: - Event Timing & Debounce (Seconds)
    public enum Timing {
        public static let frameRenderDebounce: TimeInterval = 0.016
        public static let appLifecycleDebounce: TimeInterval = 0.05
        public static let spaceChangeInitialDebounce: TimeInterval = 0.05
        public static let spaceChangeSettleDelay: TimeInterval = 0.15
        public static let windowDragSettleDebounce: TimeInterval = 0.15
        public static let windowZoomAnimationSettleDelay: TimeInterval = 0.25
        public static let nudgeRecursionWindow: TimeInterval = 0.6
        public static let maxNudgeAttempts: Int = 2
        public static let axTimeout: Float = 0.3
    }
    
    // MARK: - System Dock Integration
    public enum Dock {
        public static let autohideDelaySeconds: Double = 1000.0
        public static let defaultsBinaryPath = "/usr/bin/defaults"
        public static let killallBinaryPath = "/usr/bin/killall"
        public static let processName = "Dock"
        public static let domain = "com.apple.dock"
        public static let autohideKey = "autohide"
        public static let autohideDelayKey = "autohide-delay"
        public static let originalStateUserDefaultsKey = "com.taskbar.original_dock_state"
    }
    
    // MARK: - Accessibility & Window Filter Sets
    public enum Accessibility {
        public static let windowRole = "AXWindow"
        
        public static let rejectedSubroles: Set<String> = [
            "AXDialog",
            "AXSystemDialog",
            "AXFloatingWindow",
            "AXSheet",
            "AXDrawer",
            "AXMenu",
            "AXPopover"
        ]
        
        public static let ignoredSystemBundleIDs: Set<String> = [
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.WindowManager",
            "com.apple.Spotlight",
            "com.apple.SystemUIServer"
        ]
    }
}
