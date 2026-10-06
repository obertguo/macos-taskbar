// Sources/TaskbarKit/UI/Buttons/OverflowButton.swift

import AppKit
import TaskbarCore

public final class OverflowButton: BaseTaskbarButton {
    public var theme: ThemeDefinition {
        didSet {
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
        let bg = isPressed ? NSColor(rgba: theme.buttonPressedBackground) : NSColor(rgba: theme.buttonNormalBackground)
        bg.setFill()
        bounds.fill()
        
        if isPressed {
            BevelDrawing.drawSunkenBevel(in: bounds)
        } else {
            BevelDrawing.drawRaisedBevel(in: bounds)
        }
        
        // Draw double chevron "»"
        let font = NSFont.boldSystemFont(ofSize: CGFloat(theme.fontSize))
        let textColor = isPressed ? NSColor(rgba: theme.textPressedColor) : NSColor(rgba: theme.textColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
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
        let cornerRadius: CGFloat = 4.0
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: cornerRadius, yRadius: cornerRadius)
        
        if isPressed {
            NSColor(rgba: theme.buttonPressedBackground).setFill()
            path.fill()
        } else if isHovered {
            NSColor(rgba: theme.buttonHoverBackground).setFill()
            path.fill()
        }
        
        NSColor(rgba: theme.buttonBorderNormal).setStroke()
        path.lineWidth = 1.0
        path.stroke()
        
        let font = NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: .semibold)
        let textColor = isPressed ? NSColor(rgba: theme.textPressedColor) : NSColor(rgba: theme.textColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
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
}
