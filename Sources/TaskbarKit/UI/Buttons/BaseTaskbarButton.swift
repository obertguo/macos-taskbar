// Sources/TaskbarKit/UI/Buttons/BaseTaskbarButton.swift

import AppKit
import TaskbarCore

/// Base class for interactive taskbar buttons providing centralized mouse tracking,
/// hover state, pressed state, and configurable click dispatch lifecycle.
@MainActor
open class BaseTaskbarButton: NSView {
    public var onClick: (() -> Void)?
    
    public private(set) var isHovered: Bool = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
                didUpdateHoverOrPressState()
            }
        }
    }
    
    public private(set) var isPressed: Bool = false {
        didSet {
            if oldValue != isPressed {
                needsDisplay = true
                didUpdateHoverOrPressState()
            }
        }
    }
    
    /// Whether the button action triggers on mouse-down (e.g. for menu/popover anchors)
    /// instead of the default mouse-up within bounds.
    open var triggerClickOnMouseDown: Bool { false }
    
    private var trackingArea: NSTrackingArea?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    open override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    open override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }
    
    open override func mouseDown(with event: NSEvent) {
        isPressed = true
        if triggerClickOnMouseDown {
            onClick?()
        }
    }
    
    open override func mouseUp(with event: NSEvent) {
        if isPressed {
            isPressed = false
            if !triggerClickOnMouseDown {
                let location = convert(event.locationInWindow, from: nil)
                if bounds.contains(location) {
                    onClick?()
                }
            }
        }
    }
    
    /// Optional subclass hook invoked whenever `isHovered` or `isPressed` mutates.
    open func didUpdateHoverOrPressState() {}
}
