// Sources/TaskbarApp/UI/StartButton.swift

import AppKit
import TaskbarCore

public final class StartButton: NSView {
    public var theme: ThemeDefinition {
        didSet {
            needsDisplay = true
        }
    }
    
    public var onClick: (() -> Void)?
    
    private var isHovered: Bool = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }
    
    private var isPressed: Bool = false {
        didSet { if oldValue != isPressed { needsDisplay = true } }
    }
    
    private var trackingArea: NSTrackingArea?
    
    public init(theme: ThemeDefinition) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: 26))
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateTrackingAreas() {
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
    
    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }
    
    public override func mouseDown(with event: NSEvent) {
        isPressed = true
    }
    
    public override func mouseUp(with event: NSEvent) {
        if isPressed {
            isPressed = false
            let location = convert(event.locationInWindow, from: nil)
            if bounds.contains(location) {
                onClick?()
            }
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        switch theme.style {
        case .retroClassic:
            drawRetro(dirtyRect)
        case .modernHybrid:
            drawHybrid(dirtyRect)
        }
    }
    
    private func drawRetro(_ dirtyRect: NSRect) {
        let bg = isPressed ? NSColor(rgba: theme.buttonPressedBackground) : NSColor(rgba: theme.buttonNormalBackground)
        bg.setFill()
        bounds.fill()
        
        if isPressed {
            BevelDrawing.drawSunkenBevel(in: bounds)
        } else {
            BevelDrawing.drawRaisedBevel(in: bounds)
        }
        
        // Draw retro 4-color flag icon (2x2 grid)
        let iconX = bounds.minX + (isPressed ? 7.0 : 6.0)
        let iconY = bounds.midY - 6.0 + (isPressed ? -1.0 : 0.0)
        let boxSize: CGFloat = 5.0
        let spacing: CGFloat = 1.0
        
        // Top-left: Red
        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0).setFill()
        NSRect(x: iconX, y: iconY + boxSize + spacing, width: boxSize, height: boxSize).fill()
        
        // Top-right: Green
        NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0).setFill()
        NSRect(x: iconX + boxSize + spacing, y: iconY + boxSize + spacing, width: boxSize, height: boxSize).fill()
        
        // Bottom-left: Blue
        NSColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1.0).setFill()
        NSRect(x: iconX, y: iconY, width: boxSize, height: boxSize).fill()
        
        // Bottom-right: Yellow
        NSColor(red: 0.95, green: 0.85, blue: 0.1, alpha: 1.0).setFill()
        NSRect(x: iconX + boxSize + spacing, y: iconY, width: boxSize, height: boxSize).fill()
        
        // Draw "Start" label
        let textX = iconX + (boxSize * 2) + spacing + 5.0
        let textY = bounds.midY - 7.0 + (isPressed ? -1.0 : 0.0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: .bold),
            .foregroundColor: NSColor(rgba: theme.textColor)
        ]
        let str = NSAttributedString(string: TaskbarStrings.StartButton.title, attributes: attrs)
        str.draw(at: NSPoint(x: textX, y: textY))
    }
    
    private func drawHybrid(_ dirtyRect: NSRect) {
        let cornerRadius = CGFloat(theme.buttonCornerRadius)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: cornerRadius, yRadius: cornerRadius)
        
        let bgColor: NSColor
        if isPressed {
            bgColor = NSColor(rgba: theme.buttonPressedBackground)
        } else if isHovered {
            bgColor = NSColor(rgba: theme.buttonHoverBackground)
        } else {
            bgColor = NSColor(rgba: theme.buttonNormalBackground)
        }
        
        bgColor.setFill()
        path.fill()
        
        let borderColor = isPressed ? NSColor(rgba: theme.buttonBorderPressed) : NSColor(rgba: theme.buttonBorderNormal)
        borderColor.setStroke()
        path.lineWidth = 1.0
        path.stroke()
        
        // Modern icon: 4 neat rounded squares
        let iconX = bounds.minX + 8.0
        let iconY = bounds.midY - 5.0
        let dotSize: CGFloat = 4.0
        let dotSpacing: CGFloat = 2.0
        
        let iconColor = NSColor(white: 1.0, alpha: isPressed ? 1.0 : 0.85)
        iconColor.setFill()
        
        NSBezierPath(roundedRect: NSRect(x: iconX, y: iconY + dotSize + dotSpacing, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: iconX + dotSize + dotSpacing, y: iconY + dotSize + dotSpacing, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: iconX, y: iconY, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: iconX + dotSize + dotSpacing, y: iconY, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        
        // Text
        let textX = iconX + (dotSize * 2) + dotSpacing + 6.0
        let textY = bounds.midY - 7.0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: .medium),
            .foregroundColor: NSColor(rgba: theme.textColor)
        ]
        let str = NSAttributedString(string: TaskbarStrings.StartButton.title, attributes: attrs)
        str.draw(at: NSPoint(x: textX, y: textY))
    }
}
