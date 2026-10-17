// Sources/TaskbarKit/UI/Buttons/OverflowButton.swift

import AppKit
import TaskbarCore

public final class OverflowButton: BaseTaskbarButton {
    public var theme: ThemeDefinition {
        didSet {
            guard oldValue != theme else { return }
            needsDisplay = true
        }
    }
    
    public override var triggerClickOnMouseDown: Bool { true }
    
    public init(theme: ThemeDefinition) {
        self.theme = theme
        let btnW = TaskbarConstants.Layout.overflowButtonWidth
        super.init(frame: NSRect(x: 0, y: 0, width: btnW, height: btnW))
        toolTip = TaskbarStrings.Overflow.toolTip
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
            BevelDrawing.drawSunkenBevel(in: bounds, theme: resolved)
        } else {
            BevelDrawing.drawRaisedBevel(in: bounds, theme: resolved)
        }
        
        // Draw double chevron "»"
        let attrs = isPressed ? resolved.boldPressedTextAttributes : resolved.boldTextAttributes
        
        let text = TaskbarStrings.Overflow.buttonGlyph as NSString
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: bounds.midX - (textSize.width / 2.0) + (isPressed ? 1.0 : 0.0),
            y: bounds.midY - (textSize.height / 2.0) + (isPressed ? -1.0 : 0.0),
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }
    
    private func drawHybrid(_ dirtyRect: NSRect) {
        let resolved = ResolvedTheme.resolve(theme)
        let cornerRadius = CGFloat(theme.buttonCornerRadius)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: cornerRadius, yRadius: cornerRadius)
        
        if isPressed {
            resolved.buttonPressedBackground.setFill()
            path.fill()
        } else if isHovered {
            resolved.buttonHoverBackground.setFill()
            path.fill()
        }
        
        let borderColor = isPressed ? resolved.buttonBorderPressed : resolved.buttonBorderNormal
        borderColor.setStroke()
        path.lineWidth = 1.0
        path.stroke()
        
        let attrs = isPressed ? resolved.semiboldPressedTextAttributes : resolved.semiboldTextAttributes
        
        let text = TaskbarStrings.Overflow.buttonGlyph as NSString
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: bounds.midX - (textSize.width / 2.0),
            y: bounds.midY - (textSize.height / 2.0),
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }
    
    // MARK: - NSAccessibility
    public override func accessibilityLabel() -> String? {
        "Overflow Items"
    }
}
