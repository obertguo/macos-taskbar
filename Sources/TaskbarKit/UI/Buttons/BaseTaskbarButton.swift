// Sources/TaskbarKit/UI/Buttons/BaseTaskbarButton.swift

import AppKit
import TaskbarCore

/// Base class for interactive taskbar buttons providing centralized mouse tracking,
/// hover state, pressed state, and configurable click dispatch lifecycle.
@MainActor
open class BaseTaskbarButton: NSView {
    public var onClick: (() -> Void)?
    
    // MARK: - Drag-and-Drop Callbacks & State
    public var onDragStarted: (() -> Void)?
    public var onDragged: ((_ currentWindowLocation: NSPoint) -> Void)?
    public var onDragEnded: ((_ cancelled: Bool) -> Void)?
    
    public private(set) var isDragging: Bool = false
    private var mouseDownLocation: NSPoint?
    
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
        if !isDragging {
            isPressed = false
        }
    }
    
    open override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
        isPressed = true
        if triggerClickOnMouseDown {
            onClick?()
        }
    }
    
    open override func mouseDragged(with event: NSEvent) {
        guard let startLocation = mouseDownLocation else {
            super.mouseDragged(with: event)
            return
        }
        
        let currentLocation = event.locationInWindow
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        
        if !isDragging {
            if hypot(dx, dy) >= TaskbarConstants.Drag.activationThreshold {
                isDragging = true
                onDragStarted?()
            }
        }
        
        if isDragging {
            // Check vertical departure bounds outside taskbar vertically
            let localPoint = convert(currentLocation, from: nil)
            let escape = TaskbarConstants.Drag.verticalEscapeThreshold
            if localPoint.y < -escape || localPoint.y > (bounds.height + escape) {
                cancelDrag()
            } else {
                onDragged?(currentLocation)
            }
        }
    }
    
    open override func mouseUp(with event: NSEvent) {
        let wasDragging = isDragging
        mouseDownLocation = nil
        
        if wasDragging {
            isDragging = false
            isPressed = false
            onDragEnded?(false)
        } else if isPressed {
            isPressed = false
            if !triggerClickOnMouseDown {
                let location = convert(event.locationInWindow, from: nil)
                if bounds.contains(location) {
                    onClick?()
                }
            }
        }
    }
    
    /// Cancels an active drag session cleanly without triggering clicks or committing moves.
    public func cancelDrag() {
        guard isDragging else { return }
        isDragging = false
        isPressed = false
        mouseDownLocation = nil
        onDragEnded?(true)
    }
    
    open override func keyDown(with event: NSEvent) {
        // Escape key cancels active drag session
        if event.keyCode == TaskbarConstants.KeyCodes.escape && isDragging {
            cancelDrag()
            return
        }
        super.keyDown(with: event)
    }
    
    /// Optional subclass hook invoked whenever `isHovered` or `isPressed` mutates.
    open func didUpdateHoverOrPressState() {}
}
