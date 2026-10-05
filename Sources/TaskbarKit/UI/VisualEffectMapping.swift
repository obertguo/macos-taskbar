// Sources/TaskbarKit/UI/VisualEffectMapping.swift

import AppKit

public enum VisualEffectMapping {
    /// Resolves a string identifier into an AppKit `NSVisualEffectView.Material`.
    /// Defaults to `.underWindowBackground` if unspecified or unrecognized.
    public static func resolveMaterial(_ name: String?) -> NSVisualEffectView.Material {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .underWindowBackground
        }
        
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "hudwindow", "hud":
            return .hudWindow
        case "windowbackground", "window":
            return .windowBackground
        case "underwindowbackground", "underwindow":
            return .underWindowBackground
        case "menu":
            return .menu
        case "popover":
            return .popover
        case "sidebar":
            return .sidebar
        case "headerview", "header":
            return .headerView
        case "sheet":
            return .sheet
        case "selection":
            return .selection
        case "titlebar":
            return .titlebar
        case "tooltip":
            return .toolTip
        case "contentbackground", "content":
            return .contentBackground
        case "underpagebackground", "underpage":
            return .underPageBackground
        case "fullscreenui", "fullscreen":
            return .fullScreenUI
        default:
            return .underWindowBackground
        }
    }
    
    /// Resolves a string identifier into an AppKit `NSVisualEffectView.BlendingMode`.
    /// Defaults to `.behindWindow` if unspecified or unrecognized.
    public static func resolveBlendingMode(_ name: String?) -> NSVisualEffectView.BlendingMode {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .behindWindow
        }
        
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "withinwindow", "within":
            return .withinWindow
        case "behindwindow", "behind":
            return .behindWindow
        default:
            return .behindWindow
        }
    }
}
