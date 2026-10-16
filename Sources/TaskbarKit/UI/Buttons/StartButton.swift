// Sources/TaskbarKit/UI/Buttons/StartButton.swift

import AppKit
import TaskbarCore

public final class StartButton: BaseTaskbarButton {
    public var theme: ThemeDefinition {
        didSet {
            guard oldValue != theme else { return }
            needsDisplay = true
        }
    }
    
    public init(theme: ThemeDefinition) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: 26))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Computes minimum width required to render the Start icon and text cleanly without clipping.
    public func preferredWidth() -> CGFloat {
        ResolvedTheme.resolve(theme).startButtonPreferredWidth
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if theme.is3DBeveled {
            drawRetro(dirtyRect)
        } else {
            drawHybrid(dirtyRect)
        }
    }
    
    private func drawRetro(_ dirtyRect: NSRect) {
        let resolved = ResolvedTheme.resolve(theme)
        let bg = isPressed ? resolved.buttonPressedBackground : resolved.buttonNormalBackground
        bg.setFill()
        bounds.fill()
        
        if isPressed {
            BevelDrawing.drawSunkenBevel(in: bounds, palette: theme.palette)
        } else {
            BevelDrawing.drawRaisedBevel(in: bounds, palette: theme.palette)
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
        let attrs = resolved.boldTextAttributes
        let str = NSAttributedString(string: TaskbarStrings.StartButton.title, attributes: attrs)
        let lineHeight = ceil(str.size().height)
        let textY = bounds.midY - (lineHeight / 2.0) + (isPressed ? -1.0 : 0.0)
        str.draw(at: NSPoint(x: textX, y: textY))
    }
    
    private func drawHybrid(_ dirtyRect: NSRect) {
        let resolved = ResolvedTheme.resolve(theme)
        let cornerRadius = CGFloat(theme.buttonCornerRadius)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: cornerRadius, yRadius: cornerRadius)
        
        let bgColor: NSColor
        if isPressed {
            bgColor = resolved.startButtonPressed
        } else if isHovered {
            bgColor = resolved.startButtonHover
        } else {
            bgColor = resolved.startButtonNormal
        }
        
        bgColor.setFill()
        path.fill()
        
        let borderColor = isPressed ? resolved.buttonBorderPressed : resolved.buttonBorderNormal
        borderColor.setStroke()
        path.lineWidth = 1.0
        path.stroke()
        
        // Modern icon: 4 neat rounded squares
        let iconX = bounds.minX + 8.0
        let iconY = bounds.midY - 5.0
        let dotSize: CGFloat = 4.0
        let dotSpacing: CGFloat = 2.0
        
        let iconColor = resolved.startButtonText.withAlphaComponent(isPressed ? 1.0 : 0.85)
        iconColor.setFill()
        
        NSBezierPath(roundedRect: NSRect(x: iconX, y: iconY + dotSize + dotSpacing, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: iconX + dotSize + dotSpacing, y: iconY + dotSize + dotSpacing, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: iconX, y: iconY, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: iconX + dotSize + dotSpacing, y: iconY, width: dotSize, height: dotSize), xRadius: 1, yRadius: 1).fill()
        
        // Text
        let textX = iconX + (dotSize * 2) + dotSpacing + 6.0
        let attrs = resolved.startButtonTextAttributes
        let str = NSAttributedString(string: TaskbarStrings.StartButton.title, attributes: attrs)
        let lineHeight = ceil(str.size().height)
        let textY = bounds.midY - (lineHeight / 2.0)
        str.draw(at: NSPoint(x: textX, y: textY))
    }
    
    // MARK: - NSAccessibility
    public override func accessibilityLabel() -> String? {
        "Start"
    }
}
