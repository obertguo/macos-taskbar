// Sources/TaskbarCore/Logic/AutoHideStateMachine.swift

import Foundation

/// Lifecycle states of the taskbar under proximity auto-hide management.
public enum AutoHideState: String, Sendable, Equatable, CaseIterable {
    case visible
    case hiding
    case hidden
    case revealing
}

/// Represents an explicit state transition produced by the auto-hide state machine.
public struct AutoHideTransition: Sendable, Equatable {
    public let fromState: AutoHideState
    public let toState: AutoHideState
    public let animated: Bool
    public let animationDuration: Double
    
    public init(
        fromState: AutoHideState,
        toState: AutoHideState,
        animated: Bool = true,
        animationDuration: Double = 0.2
    ) {
        self.fromState = fromState
        self.toState = toState
        self.animated = animated
        self.animationDuration = animationDuration
    }
}

/// Pure Swift state machine governing taskbar auto-hide visibility, mouse hover dwell,
/// and interactive locks (popup menus, dragging sessions).
public struct AutoHideStateMachine: Sendable, Equatable {
    public private(set) var state: AutoHideState
    public private(set) var isAutoHideEnabled: Bool
    public private(set) var isMouseInside: Bool
    public private(set) var isPopupActive: Bool
    public private(set) var isDragActive: Bool
    public private(set) var isWindowActive: Bool
    
    public var hideDelay: Double
    public var revealAnimationDuration: Double
    public var hideAnimationDuration: Double
    
    /// Returns `true` if interaction or configuration locks demand that the bar remains visible.
    public var shouldStayVisible: Bool {
        !isAutoHideEnabled || isMouseInside || isPopupActive || isDragActive
    }
    
    public init(
        initialState: AutoHideState = .visible,
        isAutoHideEnabled: Bool = false,
        hideDelay: Double = 0.3,
        revealAnimationDuration: Double = 0.15,
        hideAnimationDuration: Double = 0.2
    ) {
        self.state = initialState
        self.isAutoHideEnabled = isAutoHideEnabled
        self.isMouseInside = false
        self.isPopupActive = false
        self.isDragActive = false
        self.isWindowActive = false
        self.hideDelay = hideDelay
        self.revealAnimationDuration = revealAnimationDuration
        self.hideAnimationDuration = hideAnimationDuration
    }
    
    /// Updates auto-hide enable setting and triggers transitions if needed.
    @discardableResult
    public mutating func setAutoHideEnabled(_ enabled: Bool) -> AutoHideTransition? {
        isAutoHideEnabled = enabled
        if !enabled {
            if state != .visible {
                let previous = state
                state = .visible
                return AutoHideTransition(fromState: previous, toState: .visible, animated: false, animationDuration: 0)
            }
        } else {
            if !shouldStayVisible && (state == .visible || state == .revealing) {
                let previous = state
                state = .hiding
                return AutoHideTransition(fromState: previous, toState: .hiding, animated: true, animationDuration: hideAnimationDuration)
            }
        }
        return nil
    }
    
    /// Called when the mouse pointer enters the taskbar or proximity hot zone.
    @discardableResult
    public mutating func onMouseEntered() -> AutoHideTransition? {
        isMouseInside = true
        if state == .hidden || state == .hiding {
            let previous = state
            state = .revealing
            return AutoHideTransition(fromState: previous, toState: .revealing, animated: true, animationDuration: revealAnimationDuration)
        }
        return nil
    }
    
    /// Called when the mouse pointer exits the taskbar.
    @discardableResult
    public mutating func onMouseExited() -> AutoHideTransition? {
        isMouseInside = false
        if isAutoHideEnabled && !isPopupActive && !isDragActive {
            if state == .visible || state == .revealing {
                let previous = state
                state = .hiding
                return AutoHideTransition(fromState: previous, toState: .hiding, animated: true, animationDuration: hideAnimationDuration)
            }
        }
        return nil
    }
    
    /// Called when a popup (group window list, context menu) is displayed, locking visibility.
    @discardableResult
    public mutating func onPopupPresented() -> AutoHideTransition? {
        isPopupActive = true
        if state == .hidden || state == .hiding {
            let previous = state
            state = .revealing
            return AutoHideTransition(fromState: previous, toState: .revealing, animated: true, animationDuration: revealAnimationDuration)
        }
        return nil
    }
    
    /// Called when a popup is dismissed, releasing the visibility lock.
    @discardableResult
    public mutating func onPopupDismissed() -> AutoHideTransition? {
        isPopupActive = false
        if isAutoHideEnabled && !isMouseInside && !isDragActive {
            if state == .visible || state == .revealing {
                let previous = state
                state = .hiding
                return AutoHideTransition(fromState: previous, toState: .hiding, animated: true, animationDuration: hideAnimationDuration)
            }
        }
        return nil
    }
    
    /// Called when button dragging begins, locking visibility.
    @discardableResult
    public mutating func onDragStarted() -> AutoHideTransition? {
        isDragActive = true
        if state == .hidden || state == .hiding {
            let previous = state
            state = .revealing
            return AutoHideTransition(fromState: previous, toState: .revealing, animated: true, animationDuration: revealAnimationDuration)
        }
        return nil
    }
    
    /// Called when button dragging finishes or is cancelled, releasing the visibility lock.
    @discardableResult
    public mutating func onDragEnded() -> AutoHideTransition? {
        isDragActive = false
        if isAutoHideEnabled && !isMouseInside && !isPopupActive {
            if state == .visible || state == .revealing {
                let previous = state
                state = .hiding
                return AutoHideTransition(fromState: previous, toState: .hiding, animated: true, animationDuration: hideAnimationDuration)
            }
        }
        return nil
    }
    
    /// Marks the owning window active/foreground.
    @discardableResult
    public mutating func onWindowActive() -> AutoHideTransition? {
        isWindowActive = true
        return nil
    }
    
    /// Called when the running transition animation completes its duration.
    @discardableResult
    public mutating func onAnimationCompleted() -> AutoHideTransition? {
        switch state {
        case .revealing:
            state = .visible
            return AutoHideTransition(fromState: .revealing, toState: .visible, animated: false, animationDuration: 0)
        case .hiding:
            state = .hidden
            return AutoHideTransition(fromState: .hiding, toState: .hidden, animated: false, animationDuration: 0)
        case .visible, .hidden:
            return nil
        }
    }
    
    /// Manually resets or forces the state machine into an explicit state.
    public mutating func forceState(_ newState: AutoHideState) {
        state = newState
    }
}
