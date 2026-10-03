// Sources/TaskbarApp/UI/TaskButton.swift

import AppKit
import TaskbarCore

public final class TaskButton: NSView {
    public var windowInfo: WindowInfo {
        didSet {
            if oldValue != windowInfo {
                toolTip = windowInfo.displayTitle
                needsDisplay = true
            }
        }
    }
    
    public var isFocusedWindow: Bool {
        didSet {
            if oldValue != isFocusedWindow {
                needsDisplay = true
            }
        }
    }
    
    public var showTitle: Bool {
        didSet {
            if oldValue != showTitle {
                needsDisplay = true
            }
        }
    }
    
    public var theme: ThemeDefinition {
        didSet {
            needsDisplay = true
        }
    }
    
    public var onClick: (() -> Void)?
    public var onClose: (() -> Void)?
    public var onQuit: (() -> Void)?
    
    private var isHovered = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }
    private var isPressed = false {
        didSet { if oldValue != isPressed { needsDisplay = true } }
    }
    private var trackingArea: NSTrackingArea?
    
    public init(
        windowInfo: WindowInfo,
        isFocused: Bool,
        showTitle: Bool,
        theme: ThemeDefinition
    ) {
        self.windowInfo = windowInfo
        self.isFocusedWindow = isFocused
        self.showTitle = showTitle
        self.theme = theme
        super.init(frame: .zero)
        
        self.toolTip = windowInfo.displayTitle
        self.wantsLayer = true
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
            let loc = convert(event.locationInWindow, from: nil)
            if bounds.contains(loc) {
                onClick?()
            }
        }
    }
    
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: windowInfo.appName)
        
        // Restore / Minimize
        let minActionTitle = windowInfo.isMinimized ? "Restore" : "Minimize"
        let minItem = NSMenuItem(title: minActionTitle, action: #selector(handleMenuMinimizeOrRestore), keyEquivalent: "")
        minItem.target = self
        menu.addItem(minItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Close Window
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(handleMenuClose), keyEquivalent: "w")
        closeItem.target = self
        menu.addItem(closeItem)
        
        // Quit App
        let quitItem = NSMenuItem(title: "Quit \(windowInfo.appName)", action: #selector(handleMenuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func handleMenuMinimizeOrRestore() {
        onClick?()
    }
    
    @objc private func handleMenuClose() {
        onClose?()
    }
    
    @objc private func handleMenuQuit() {
        onQuit?()
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
        let isDown = isFocusedWindow || isPressed
        let bg = isDown ? NSColor(rgba: theme.buttonPressedBackground) : NSColor(rgba: theme.buttonNormalBackground)
        bg.setFill()
        bounds.fill()
        
        if isDown {
            BevelDrawing.drawSunkenBevel(in: bounds)
        } else {
            BevelDrawing.drawRaisedBevel(in: bounds)
        }
        
        let iconOffset: CGFloat = isDown ? 1.0 : 0.0
        let iconX = bounds.minX + 4.0 + iconOffset
        let iconY = bounds.midY - 8.0 - iconOffset
        let icon = IconCache.shared.icon(for: windowInfo.bundleID, pid: windowInfo.pid)
        icon.draw(in: NSRect(x: iconX, y: iconY, width: 16, height: 16))
        
        if showTitle {
            let textX = iconX + 16.0 + 4.0
            let maxTextW = max(0, bounds.maxX - textX - 4.0)
            let textY = bounds.midY - 7.0 - iconOffset
            
            let isDimmed = windowInfo.isMinimized || windowInfo.isAppHidden
            let textColor = isDimmed ? NSColor(rgba: RGBAColor.retroShadow) : NSColor.black
            
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: isFocusedWindow ? .bold : .regular),
                .foregroundColor: textColor,
                .paragraphStyle: para
            ]
            let str = NSAttributedString(string: windowInfo.displayTitle, attributes: attrs)
            str.draw(in: NSRect(x: textX, y: textY, width: maxTextW, height: 15))
        }
    }
    
    private func drawHybrid(_ dirtyRect: NSRect) {
        let cornerRadius = CGFloat(theme.buttonCornerRadius)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: cornerRadius, yRadius: cornerRadius)
        
        let isDimmed = windowInfo.isMinimized || windowInfo.isAppHidden
        let alphaMultiplier: CGFloat = isDimmed ? 0.6 : 1.0
        
        let bgColor: NSColor
        if isPressed || isFocusedWindow {
            bgColor = NSColor(rgba: theme.buttonPressedBackground).withAlphaComponent(CGFloat(theme.buttonPressedBackground.alpha) * alphaMultiplier)
        } else if isHovered {
            bgColor = NSColor(rgba: theme.buttonHoverBackground).withAlphaComponent(CGFloat(theme.buttonHoverBackground.alpha) * alphaMultiplier)
        } else {
            bgColor = NSColor(rgba: theme.buttonNormalBackground).withAlphaComponent(CGFloat(theme.buttonNormalBackground.alpha) * alphaMultiplier)
        }
        
        bgColor.setFill()
        path.fill()
        
        let borderColor = (isFocusedWindow || isPressed) ? NSColor(rgba: theme.buttonBorderPressed) : NSColor(rgba: theme.buttonBorderNormal)
        borderColor.setStroke()
        path.lineWidth = 1.0
        path.stroke()
        
        let iconX = bounds.minX + 6.0
        let iconY = bounds.midY - 8.0
        let icon = IconCache.shared.icon(for: windowInfo.bundleID, pid: windowInfo.pid)
        icon.draw(
            in: NSRect(x: iconX, y: iconY, width: 16, height: 16),
            from: .zero,
            operation: .sourceOver,
            fraction: alphaMultiplier
        )
        
        if showTitle {
            let textX = iconX + 16.0 + 5.0
            let maxTextW = max(0, bounds.maxX - textX - 6.0)
            let textY = bounds.midY - 7.0
            
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            
            let textColor = (isFocusedWindow ? NSColor(rgba: theme.textPressedColor) : NSColor(rgba: theme.textColor)).withAlphaComponent(alphaMultiplier)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: isFocusedWindow ? .bold : .medium),
                .foregroundColor: textColor,
                .paragraphStyle: para
            ]
            let str = NSAttributedString(string: windowInfo.displayTitle, attributes: attrs)
            str.draw(in: NSRect(x: textX, y: textY, width: maxTextW, height: 15))
        }
    }
}
