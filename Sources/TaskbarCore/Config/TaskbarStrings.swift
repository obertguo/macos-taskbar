// Sources/TaskbarCore/Config/TaskbarStrings.swift

import Foundation

/// Centralized repository of user-facing UI strings and labels.
/// Structured hierarchically to serve as the single source of truth for UI copy and future localization (i18n).
public enum TaskbarStrings {
    
    // MARK: - Start Button
    public enum StartButton {
        /// Text label displayed on the Start button.
        public static let title = "Start"
    }
    
    // MARK: - Overflow UI
    public enum Overflow {
        /// Chevron glyph displayed on the overflow button when running windows exceed bar capacity.
        public static let buttonGlyph = "»"
        
        /// Hover tooltip displayed on the overflow chevron button.
        public static let toolTip = "More windows"
        
        /// Title for the overflow popup menu displaying hidden windows.
        public static let menuTitle = "Overflow Windows"
    }
    
    // MARK: - Task Button Context Menu
    public enum ContextMenu {
        /// Menu item to restore a minimized window to the desktop.
        public static let restore = "Restore"
        
        /// Menu item to minimize an active window into the taskbar.
        public static let minimize = "Minimize"
        
        /// Menu item to close the selected window.
        public static let closeWindow = "Close Window"
        
        /// Menu item to pin an application to the taskbar quick launch area.
        public static let pinToTaskbar = "Pin to Taskbar"
        
        /// Menu item to unpin an application from the taskbar quick launch area.
        public static let unpinFromTaskbar = "Unpin from Taskbar"
        
        /// Menu item to terminate the application owning the window.
        public static func quitApp(_ appName: String) -> String {
            "Quit \(appName)"
        }
    }
    
    // MARK: - Menu Bar Status Item & Menu
    public enum StatusMenu {
        /// System SF Symbol identifier for the menu bar icon.
        public static let statusBarSymbol = "menubar.dock.rectangle"
        
        /// Fallback text glyph for the menu bar item if the SF Symbol fails to render.
        public static let statusBarFallbackGlyph = "⊞"
        
        /// Formatted application name and version string for the disabled header menu item.
        public static func appHeader(name: String, version: String) -> String {
            "\(name) v\(version)"
        }
        
        /// Title for the Theme submenu.
        public static let themeMenu = "Theme"
        
        /// Title for the Button Width / Overflow threshold submenu.
        public static let buttonWidthMenu = "Button Width"
        
        /// Title for the Taskbar Height submenu.
        public static let barHeightMenu = "Taskbar Height"
        
        /// Title for the Font Size submenu.
        public static let fontSizeMenu = "Font Size"
        
        /// Title for the Icon Size submenu.
        public static let iconSizeMenu = "Icon Size"
        
        /// Menu item to launch the configured start launcher (Spotlight, Raycast, etc.).
        public static let openStartLauncher = "Open Start Launcher"
        
        /// Menu item toggle for automatically nudging maximized windows above the taskbar.
        public static let nudgeMaximizedWindows = "Nudge Maximized Windows"
        
        /// Menu item toggle to keep the native macOS Dock permanently hidden.
        public static let hideSystemDock = "Hide macOS System Dock"
        
        /// Title for the Dock Autohide Delay submenu.
        public static let dockDelayMenu = "Dock Autohide Delay"
        
        /// Menu item to immediately restore native macOS Dock autohide settings.
        public static let restoreSystemDock = "Restore System Dock Now"
        
        /// Menu item to terminate the Taskbar process cleanly.
        public static func quitApp(name: String) -> String {
            "Quit \(name)"
        }
    }
    
    // MARK: - Presets Copy
    public enum Presets {
        // Button Width Presets
        public static let buttonWidthBalanced = "80 pt (Default - Balanced)"
        public static let buttonWidthRoomy = "100 pt (Roomy - Early overflow)"
        public static let buttonWidthSpacious = "120 pt (Spacious)"
        public static let buttonWidthCompact = "60 pt (Compact)"
        public static let buttonWidthIconOnly = "28 pt (Ultra-compact - Icon only)"
        
        // Bar Height Presets
        public static let barHeightSlim = "26 pt (Slim)"
        public static let barHeightClassic = "30 pt (Default - Classic)"
        public static let barHeightMedium = "34 pt (Medium)"
        public static let barHeightLarge = "38 pt (Large)"
        public static let barHeightSpacious = "44 pt (Spacious)"
        
        // Font Size Presets
        public static let fontSizeSmall = "10 pt (Small)"
        public static let fontSizeStandard = "11 pt (Default - Standard)"
        public static let fontSizeMedium = "12 pt (Medium)"
        public static let fontSizeLarge = "13 pt (Large)"
        public static let fontSizeExtraLarge = "14 pt (Extra Large)"
        
        // Icon Size Presets
        public static let iconSizeCompact = "14 pt (Compact)"
        public static let iconSizeStandard = "16 pt (Default - Standard)"
        public static let iconSizeMedium = "18 pt (Medium)"
        public static let iconSizeLarge = "20 pt (Large)"
        public static let iconSizeExtraLarge = "24 pt (Extra Large)"
        
        // Dock Autohide Delay Presets
        public static let dockDelayPermanentlyHidden = "Permanently Hidden (1000s)"
        public static let dockDelay15s = "1.5s (Deliberate Hover)"
        public static let dockDelay10s = "1.0s (Slow Hover)"
        public static let dockDelay05s = "0.5s (Normal Autohide)"
        public static let dockDelayInstant = "0.0s (Instant Reveal)"
    }
    
    // MARK: - Theme Display Names
    public enum Themes {
        /// User-facing display name for the Modern Hybrid theme.
        public static let modernHybrid = "Modern Hybrid"
        
        /// User-facing display name for the Retro Classic Windows 95 theme.
        public static let retroClassic = "Retro Classic"
        
        /// User-facing display name for the Windows XP Luna theme.
        public static let windowsXPLuna = "Windows XP Luna"
        
        /// User-facing display name for the Dark Minimal theme.
        public static let darkMinimal = "Dark Minimal"
        
        /// Label for the custom themes section or empty state.
        public static let customThemesHeader = "Custom Themes"
        public static let noCustomThemesFound = "No Custom Themes"
        
        /// Actions in the Theme menu.
        public static let reloadThemes = "Reload Themes from Disk"
        public static let openThemesFolder = "Open Themes Folder in Finder..."
        public static let exportCurrentTheme = "Export Current Theme as JSON..."
    }
}
