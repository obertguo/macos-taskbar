// Sources/TaskbarCore/Config/TaskbarConstants.swift

import Foundation
import CoreGraphics

/// Centralized source of truth for engineering constants across layout, geometry, timing, and system integration.
public enum TaskbarConstants {
    
    /// Convenient alias to the centralized strings catalog.
    public typealias Strings = TaskbarStrings
    
    // MARK: - Layout & UI Metrics
    public enum Layout {
        /// Maximum button width in points when few buttons are present.
        public static let defaultMaxButtonWidth: Double = 160.0
        
        /// Minimum button width in points before task buttons stop shrinking and trigger overflow.
        public static let defaultMinButtonWidth: Double = 80.0
        
        /// Spacing in points between adjacent task buttons.
        public static let defaultButtonSpacing: Double = 2.0
        
        /// Minimum button width in points below which window titles are hidden, rendering only icons.
        public static let defaultTitleVisibilityThreshold: Double = 50.0
        
        /// Default height in points of the taskbar along the bottom edge of the screen.
        public static let defaultBarHeight: Double = 30.0
        
        /// Minimum interactive button height in points to guarantee clickable targets on thin bars.
        public static let minimumButtonHeight: CGFloat = 18.0
        
        /// Vertical top and bottom inset padding in points inside the taskbar view.
        public static let taskbarVerticalPadding: CGFloat = 2.0
        
        /// Width in points of the Start button in Retro Classic Windows 95 styling.
        public static let startButtonWidthRetro: CGFloat = 56.0
        
        /// Width in points of the Start button in Modern Hybrid styling.
        public static let startButtonWidthHybrid: CGFloat = 62.0
        
        /// Margin in points between the left edge of the display and the Start button.
        public static let startButtonLeadingMargin: CGFloat = 3.0
        
        /// Margin in points between the Start button and the first task button.
        public static let startButtonTrailingMargin: CGFloat = 4.0
        
        /// Spacing in points between adjacent pinned application buttons.
        public static let pinnedButtonSpacing: CGFloat = 2.0
        
        /// Margin in points between the pinned applications section and running task buttons.
        public static let pinnedSectionTrailingMargin: CGFloat = 6.0
        
        /// Margin in points reserved on the right screen edge when overflow is inactive.
        public static let taskbarTrailingMargin: CGFloat = 4.0
        
        /// Width in points of the overflow chevron button (`»`) shown when buttons overflow.
        public static let overflowButtonWidth: CGFloat = 26.0
        
        /// Margin in points between the overflow button and the right screen edge.
        public static let overflowButtonTrailingMargin: CGFloat = 3.0
        
        /// Vertical offset in points from the taskbar top edge when popping up the overflow menu.
        public static let overflowMenuVerticalOffset: CGFloat = 2.0
        
        /// Width and height in points for rendering application and window icons (fallback/default).
        public static let iconSize: CGFloat = 16.0
        
        /// Default font size in points for button labels and UI typography.
        public static let defaultFontSize: Double = 11.0
        
        /// Default width and height in points for application and window icons.
        public static let defaultIconSize: Double = 16.0
        
        /// Horizontal margin between icon and text in Retro Classic buttons.
        public static let taskButtonIconMarginRetro: CGFloat = 4.0
        
        /// Horizontal margin between icon and text in Modern Hybrid buttons.
        public static let taskButtonIconMarginHybrid: CGFloat = 6.0
        
        /// Opacity multiplier applied to task buttons representing minimized or hidden windows.
        public static let dimmedButtonAlpha: CGFloat = 0.6
        
        /// Corner radius in points for the multi-window counter badge in Modern Hybrid theme.
        public static let groupBadgeCornerRadius: CGFloat = 4.0
        
        /// Minimum width in points for the multi-window counter badge.
        public static let groupBadgeMinWidth: CGFloat = 16.0
        
        /// Height in points for the multi-window counter badge.
        public static let groupBadgeHeight: CGFloat = 14.0
        
        /// Preset configurations for button width and overflow sensitivity in settings menu.
        public static let buttonWidthPresets: [(title: String, width: Double)] = [
            (TaskbarStrings.Presets.buttonWidthBalanced, 80.0),
            (TaskbarStrings.Presets.buttonWidthRoomy, 100.0),
            (TaskbarStrings.Presets.buttonWidthSpacious, 120.0),
            (TaskbarStrings.Presets.buttonWidthCompact, 60.0),
            (TaskbarStrings.Presets.buttonWidthIconOnly, 28.0)
        ]
        
        /// Preset configurations for taskbar bar height in settings menu.
        public static let barHeightPresets: [(title: String, height: Double)] = [
            (TaskbarStrings.Presets.barHeightSlim, 26.0),
            (TaskbarStrings.Presets.barHeightClassic, 30.0),
            (TaskbarStrings.Presets.barHeightMedium, 34.0),
            (TaskbarStrings.Presets.barHeightLarge, 38.0),
            (TaskbarStrings.Presets.barHeightSpacious, 44.0)
        ]
        
        /// Preset configurations for UI font size in settings menu.
        public static let fontSizePresets: [(title: String, size: Double)] = [
            (TaskbarStrings.Presets.fontSizeSmall, 10.0),
            (TaskbarStrings.Presets.fontSizeStandard, 11.0),
            (TaskbarStrings.Presets.fontSizeMedium, 12.0),
            (TaskbarStrings.Presets.fontSizeLarge, 13.0),
            (TaskbarStrings.Presets.fontSizeExtraLarge, 14.0)
        ]
        
        /// Preset configurations for window icon size in settings menu.
        public static let iconSizePresets: [(title: String, size: Double)] = [
            (TaskbarStrings.Presets.iconSizeCompact, 14.0),
            (TaskbarStrings.Presets.iconSizeStandard, 16.0),
            (TaskbarStrings.Presets.iconSizeMedium, 18.0),
            (TaskbarStrings.Presets.iconSizeLarge, 20.0),
            (TaskbarStrings.Presets.iconSizeExtraLarge, 24.0)
        ]
    }
    
    // MARK: - Work Area & Window Geometry
    public enum WorkArea {
        /// Minimum allowable window height in points to prevent the nudger from collapsing windows into slices.
        public static let minimumWindowHeight: CGFloat = 100.0
        
        /// Sub-pixel tolerance in points when determining if a window bottom overlaps the taskbar frame.
        public static let overlapTolerance: CGFloat = 2.0
        
        /// Fractional screen height (45%) a window must occupy to qualify as vertically maximized/tiled.
        public static let screenHeightMaximizedRatio: CGFloat = 0.45
        
        /// Absolute top tolerance in points from the screen origin where maximized windows start.
        public static let screenTopToleranceBase: CGFloat = 120.0
        
        /// Fractional top tolerance (20% of screen height) allowing for menu bar, notch, and title bars.
        public static let screenTopToleranceRatio: CGFloat = 0.20
        
        /// Threshold in points below which minor size adjustments are ignored to prevent feedback loops.
        public static let clampingRecursionGuardDelta: CGFloat = 1.0
        
        /// Coordinate variance tolerance in points when matching full-screen app bounds against display bounds.
        public static let fullScreenDisplayTolerance: CGFloat = 2.0
        
        /// Minimum width and height in points for a window candidate to avoid invisible tracking elements.
        public static let minimumWindowDimension: CGFloat = 50.0
    }
    
    // MARK: - Clamping & Boundary Tolerances
    public enum Clamping {
        /// Sub-pixel overlap threshold in points to ignore minor rounding differences when clamping windows.
        public static let subpixelOverlapThreshold: Double = 2.0
    }
    
    // MARK: - Event Timing & Debounce (Seconds)
    public enum Timing {
        /// Target 60fps frame debounce interval (approx 16ms) for UI redraw coalescing.
        public static let frameRenderDebounce: TimeInterval = 0.016
        
        /// Debounce interval in seconds following NSWorkspace launch/terminate notifications.
        public static let appLifecycleDebounce: TimeInterval = 0.05
        
        /// Immediate debounce in seconds triggered upon receiving macOS active space change notifications.
        public static let spaceChangeInitialDebounce: TimeInterval = 0.05
        
        /// Settling delay in seconds to allow Mission Control and full-screen space transitions to complete.
        public static let spaceChangeSettleDelay: TimeInterval = 0.15
        
        /// Settle interval in seconds after user finishes dragging or resizing a window before checking clamp.
        public static let windowDragSettleDebounce: TimeInterval = 0.15
        
        /// Delay in seconds following a window zoom or maximize animation before nudging coordinates.
        public static let windowZoomAnimationSettleDelay: TimeInterval = 0.25
        
        /// Sliding window in seconds during which repetitive nudges on the same window trigger loop detection.
        public static let nudgeRecursionWindow: TimeInterval = 0.6
        
        /// Maximum permitted nudge attempts within the recursion window before backing off.
        public static let maxNudgeAttempts: Int = 4
        
        /// Global timeout in seconds for Accessibility API IPC queries to prevent UI hangs.
        public static let axTimeout: Float = 0.15
    }
    
    // MARK: - System Dock Integration
    public enum Dock {
        /// Default autohide delay in seconds (1000s) written to macOS preferences to keep native Dock permanently hidden.
        public static let defaultAutohideDelaySeconds: Double = 1000.0
        
        /// Alias for default autohide delay in seconds.
        public static let autohideDelaySeconds: Double = defaultAutohideDelaySeconds
        
        /// Preset configurations for Dock autohide delay in settings menu.
        public static let dockDelayPresets: [(title: String, delay: Double)] = [
            (TaskbarStrings.Presets.dockDelayPermanentlyHidden, 1000.0),
            (TaskbarStrings.Presets.dockDelay15s, 1.5),
            (TaskbarStrings.Presets.dockDelay10s, 1.0),
            (TaskbarStrings.Presets.dockDelay05s, 0.5),
            (TaskbarStrings.Presets.dockDelayInstant, 0.0)
        ]
        
        /// File system path to the macOS `/usr/bin/defaults` command-line utility.
        public static let defaultsBinaryPath = "/usr/bin/defaults"
        
        /// File system path to the macOS `/usr/bin/killall` executable used to reload the Dock process.
        public static let killallBinaryPath = "/usr/bin/killall"
        
        /// Process name of the macOS native Dock daemon.
        public static let processName = "Dock"
        
        /// Domain string used for reading and writing macOS Dock preferences.
        public static let domain = "com.apple.dock"
        
        /// Preferences key controlling native Dock auto-hiding state.
        public static let autohideKey = "autohide"
        
        /// Preferences key controlling native Dock hover reveal delay.
        public static let autohideDelayKey = "autohide-delay"
        
        /// UserDefaults key used to persist user's original Dock settings for clean restoration on quit.
        public static let originalStateUserDefaultsKey = "com.taskbar.original_dock_state"
    }
    
    // MARK: - Accessibility & Window Filter Sets
    public enum Accessibility {
        /// Expected standard accessibility role for app windows.
        public static let windowRole = "AXWindow"
        
        /// Set of accessibility subroles (sheets, dialogs, drawers, popovers) rejected from the taskbar.
        public static let rejectedSubroles: Set<String> = [
            "AXDialog",
            "AXSystemDialog",
            "AXFloatingWindow",
            "AXSheet",
            "AXDrawer",
            "AXMenu",
            "AXPopover"
        ]
        
        /// Bundle identifiers of macOS system services and overlays ignored by the taskbar window list.
        public static let ignoredSystemBundleIDs: Set<String> = [
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.WindowManager",
            "com.apple.Spotlight",
            "com.apple.SystemUIServer"
        ]
        
        /// Option key used with AXIsProcessTrustedWithOptions to prompt the user for permission.
        public static let promptOptionKey = "AXTrustedCheckOptionPrompt"
        
        /// System URL scheme to navigate directly to Accessibility preferences in macOS System Settings.
        public static let systemSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }
    
    // MARK: - App Launchers
    public enum Launcher {
        /// Custom URL scheme used to open Raycast.
        public static let raycastScheme = "raycast://"
        
        /// Standard application bundle path for Raycast on macOS.
        public static let raycastAppPath = "/Applications/Raycast.app"
    }
    
    // MARK: - Drag-and-Drop Reordering
    public enum Drag {
        /// Minimum drag movement distance in points before activating a drag session.
        public static let activationThreshold: CGFloat = 4.0
        
        /// Vertical escape distance in points outside taskbar bounds that cancels an active drag session.
        public static let verticalEscapeThreshold: CGFloat = 30.0
        
        /// Width of the vertical insertion indicator line in points.
        public static let insertionIndicatorWidth: CGFloat = 2.0
        
        /// Corner radius in points for the vertical insertion indicator line.
        public static let insertionIndicatorCornerRadius: CGFloat = 1.0
        
        /// Vertical padding in points deducted from top/bottom for the insertion indicator line.
        public static let insertionIndicatorVerticalInset: CGFloat = 8.0
        
        /// Minimum height in points for the insertion indicator line.
        public static let insertionIndicatorMinHeight: CGFloat = 16.0
        
        /// Opacity multiplier applied to the dragged button during an active drag session.
        public static let draggedButtonAlpha: CGFloat = 0.85
        
        /// Layer z-position for elevating the dragged button above siblings.
        public static let draggedButtonZPosition: CGFloat = 100.0
        
        /// Layer z-position for rendering the drop insertion indicator bar above all buttons.
        public static let insertionIndicatorZPosition: CGFloat = 200.0
    }
    
    // MARK: - Stable Component Identifiers
    public enum Identifiers {
        /// Prefix used for single-window taskbar button and custom order IDs.
        public static let windowPrefix = "win_"
        
        /// Prefix used for multi-window group taskbar button and custom order IDs.
        public static let groupPrefix = "group_"
        
        /// Generates a stable unique identifier for an ungrouped window button or custom order slot.
        public static func windowID(pid: pid_t, id: UInt64) -> String {
            "\(windowPrefix)\(pid)_\(id)"
        }
        
        /// Generates a stable unique identifier for an application group button or custom order slot.
        public static func groupID(bundleID: String) -> String {
            "\(groupPrefix)\(bundleID)"
        }
        
        /// Generates a PID prefix matching all windows belonging to the given process ID.
        public static func windowPIDPrefix(pid: pid_t) -> String {
            "\(windowPrefix)\(pid)_"
        }
    }
    
    // MARK: - Keyboard Codes
    public enum KeyCodes {
        /// macOS virtual key code for the Escape key (kVK_Escape).
        public static let escape: UInt16 = 53
        
        /// macOS virtual key code for Return / Enter (kVK_Return).
        public static let returnKey: UInt16 = 36
        
        /// macOS virtual key code for Up Arrow (kVK_UpArrow).
        public static let upArrow: UInt16 = 126
        
        /// macOS virtual key code for Down Arrow (kVK_DownArrow).
        public static let downArrow: UInt16 = 125
    }
    
    // MARK: - Group Window Popup Metrics
    public enum GroupPopup {
        /// Fixed height for each window row in the popup list.
        public static let rowHeight: CGFloat = 28.0
        
        /// Minimum horizontal width for the popup panel.
        public static let minWidth: CGFloat = 220.0
        
        /// Maximum horizontal width for the popup panel.
        public static let maxWidth: CGFloat = 360.0
        
        /// Vertical offset in points from the taskbar button top edge.
        public static let verticalOffset: CGFloat = 4.0
        
        /// Outer corner radius in points for the popup panel in Modern Hybrid theme.
        public static let cornerRadius: CGFloat = 6.0
        
        /// Horizontal padding inside the popup panel.
        public static let contentHorizontalPadding: CGFloat = 6.0
        
        /// Vertical padding inside the popup panel.
        public static let contentVerticalPadding: CGFloat = 6.0
        
        /// Size in points of the active window indicator dot.
        public static let activeDotSize: CGFloat = 6.0
        
        /// Size in points of the window close button (✕).
        public static let closeButtonSize: CGFloat = 16.0
        
        /// Horizontal spacing between icon, title, and accessories.
        public static let itemSpacing: CGFloat = 6.0
    }
}

extension Notification.Name {
    /// Broadcast when pinned applications are added, removed, or reordered.
    public static let taskbarPinnedAppsDidChange = Notification.Name("com.taskbar.pinnedAppsDidChange")
}

