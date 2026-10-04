// Sources/TaskbarKit/UI/PinnedButton.swift

import AppKit
import TaskbarCore

/// A compact square button representing a pinned application shortcut on the taskbar.
public final class PinnedButton: NSView {
    public var pinnedApp: PinnedApp {
        didSet {
            if oldValue != pinnedApp {
                toolTip = pinnedApp.displayName
                setAccessibilityLabel(pinnedApp.displayName)
                needsDisplay = true
            }
        }
    }
    
    public var isRunning: Bool {
        didSet {
            if oldValue != isRunning {
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
    public var onUnpin: (() -> Void)?
    public var onQuit: (() -> Void)?
    
    public private(set) var isHovered: Bool = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }
    
    public private(set) var isPressed: Bool = false {
        didSet { if oldValue != isPressed { needsDisplay = true } }
    }
    
    private var trackingArea: NSTrackingArea?
    
    public init(
        pinnedApp: PinnedApp,
        isRunning: Bool,
        theme: ThemeDefinition
    ) {
        self.pinnedApp = pinnedApp
        self.isRunning = isRunning
        self.theme = theme
        super.init(frame: .zero)
        
        self.toolTip = pinnedApp.displayName
        self.wantsLayer = true
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.button)
        self.setAccessibilityLabel(pinnedApp.displayName)
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
        let menu = NSMenu(title: pinnedApp.displayName)
        
        // 1. Open <AppName>
        let openItem = NSMenuItem(
            title: TaskbarStrings.ContextMenu.openApp(pinnedApp.displayName),
            action: #selector(handleMenuOpen),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        
        // 2. Unpin from Taskbar
        let unpinItem = NSMenuItem(
            title: TaskbarStrings.ContextMenu.unpinFromTaskbar,
            action: #selector(handleMenuUnpin),
            keyEquivalent: ""
        )
        unpinItem.target = self
        menu.addItem(unpinItem)
        
        // 3. If running, Quit <AppName>
        if isRunning {
            menu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(
                title: TaskbarStrings.ContextMenu.quitApp(pinnedApp.displayName),
                action: #selector(handleMenuQuit),
                keyEquivalent: "q"
            )
            quitItem.target = self
            menu.addItem(quitItem)
        }
        
        return menu
    }
    
    @objc private func handleMenuOpen() {
        onClick?()
    }
    
    @objc private func handleMenuUnpin() {
        onUnpin?()
    }
    
    @objc private func handleMenuQuit() {
        onQuit?()
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
        let isDown = isPressed
        if isDown {
            let bg = NSColor(rgba: theme.buttonPressedBackground)
            bg.setFill()
            bounds.fill()
            BevelDrawing.drawSunkenBevel(in: bounds)
        } else if isHovered {
            let bg = NSColor(rgba: theme.buttonNormalBackground)
            bg.setFill()
            bounds.fill()
            BevelDrawing.drawRaisedBevel(in: bounds)
        }
        
        let iconSize = CGFloat(theme.iconSize)
        let iconOffset: CGFloat = isDown ? 1.0 : 0.0
        let runningYOffset: CGFloat = isRunning ? 1.0 : 0.0
        let iconX = round(bounds.midX - (iconSize / 2.0)) + iconOffset
        let iconY = round(bounds.midY - (iconSize / 2.0)) - iconOffset + runningYOffset
        
        let icon = IconCache.shared.icon(
            for: pinnedApp.bundleIdentifier,
            customPath: pinnedApp.customPath,
            size: NSSize(width: iconSize, height: iconSize)
        )
        icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        
        if isRunning {
            let dotSize: CGFloat = 3.0
            let dotX = round(bounds.midX - (dotSize / 2.0)) + iconOffset
            let dotY = bounds.minY + 2.0 - iconOffset
            let dotColor = NSColor(rgba: theme.textColor)
            dotColor.setFill()
            NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize).fill()
        }
    }
    
    private func drawHybrid(_ dirtyRect: NSRect) {
        let cornerRadius = CGFloat(theme.buttonCornerRadius)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: cornerRadius, yRadius: cornerRadius)
        
        if isPressed {
            let bgColor = NSColor(rgba: theme.buttonPressedBackground)
            bgColor.setFill()
            path.fill()
            let borderColor = NSColor(rgba: theme.buttonBorderPressed)
            borderColor.setStroke()
            path.lineWidth = 1.0
            path.stroke()
        } else if isHovered {
            let bgColor = NSColor(rgba: theme.buttonHoverBackground)
            bgColor.setFill()
            path.fill()
            let borderColor = NSColor(rgba: theme.buttonBorderNormal)
            borderColor.setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
        
        let iconSize = CGFloat(theme.iconSize)
        let runningYOffset: CGFloat = isRunning ? 1.0 : 0.0
        let iconX = round(bounds.midX - (iconSize / 2.0))
        let iconY = round(bounds.midY - (iconSize / 2.0)) + runningYOffset
        
        let icon = IconCache.shared.icon(
            for: pinnedApp.bundleIdentifier,
            customPath: pinnedApp.customPath,
            size: NSSize(width: iconSize, height: iconSize)
        )
        icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        
        if isRunning {
            let dotDiameter: CGFloat = 3.5
            let dotX = round(bounds.midX - (dotDiameter / 2.0))
            let dotY = bounds.minY + 2.0
            let dotRect = NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            let dotColor = NSColor(rgba: theme.buttonBorderPressed).withAlphaComponent(1.0)
            dotColor.setFill()
            dotPath.fill()
        }
    }
}
