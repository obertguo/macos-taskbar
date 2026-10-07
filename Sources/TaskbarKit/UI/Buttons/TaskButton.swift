// Sources/TaskbarKit/UI/Buttons/TaskButton.swift

import AppKit
import TaskbarCore

public final class TaskButton: BaseTaskbarButton {
    public var group: WindowGroup {
        didSet {
            if oldValue != group {
                toolTip = group.displayTitle
                needsDisplay = true
            }
        }
    }
    
    public var windowInfo: WindowInfo {
        get {
            group.primaryWindow ?? WindowInfo(
                key: WindowKey(id: 0, pid: 0),
                pid: 0,
                appName: group.appName,
                bundleID: group.bundleID,
                title: group.appName,
                frame: .zero,
                isMinimized: false
            )
        }
        set {
            group = .singleWindow(newValue)
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
    
    public var isPinned: Bool = false
    public var onClose: (() -> Void)?
    public var onCloseAll: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onTogglePin: (() -> Void)?
    public var onGroupClick: (() -> Void)?
    
    public init(
        group: WindowGroup,
        isFocused: Bool,
        showTitle: Bool,
        theme: ThemeDefinition
    ) {
        self.group = group
        self.isFocusedWindow = isFocused
        self.showTitle = showTitle
        self.theme = theme
        super.init(frame: .zero)
        
        self.toolTip = group.displayTitle
    }
    
    public convenience init(
        windowInfo: WindowInfo,
        isFocused: Bool,
        showTitle: Bool,
        theme: ThemeDefinition
    ) {
        self.init(
            group: .singleWindow(windowInfo),
            isFocused: isFocused,
            showTitle: showTitle,
            theme: theme
        )
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: group.appName)
        
        // Restore / Minimize
        let isMin = group.isMinimized
        let minActionTitle = isMin ? TaskbarStrings.ContextMenu.restore : TaskbarStrings.ContextMenu.minimize
        let minItem = NSMenuItem(title: minActionTitle, action: #selector(handleMenuMinimizeOrRestore), keyEquivalent: "")
        minItem.target = self
        menu.addItem(minItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Pin / Unpin from Taskbar
        let pinTitle = isPinned ? TaskbarStrings.ContextMenu.unpinFromTaskbar : TaskbarStrings.ContextMenu.pinToTaskbar
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(handleMenuTogglePin), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        
        menu.addItem(NSMenuItem.separator())
        
        if group.isGrouped {
            // Close All Windows
            let closeAllItem = NSMenuItem(title: TaskbarStrings.WindowGrouping.closeAllWindows, action: #selector(handleMenuCloseAll), keyEquivalent: "")
            closeAllItem.target = self
            menu.addItem(closeAllItem)
        } else {
            // Close Window
            let closeItem = NSMenuItem(title: TaskbarStrings.ContextMenu.closeWindow, action: #selector(handleMenuClose), keyEquivalent: "w")
            closeItem.target = self
            menu.addItem(closeItem)
        }
        
        // Quit App
        let quitItem = NSMenuItem(title: TaskbarStrings.ContextMenu.quitApp(group.appName), action: #selector(handleMenuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func handleMenuTogglePin() {
        onTogglePin?()
    }
    
    @objc private func handleMenuMinimizeOrRestore() {
        onClick?()
    }
    
    @objc private func handleMenuClose() {
        onClose?()
    }
    
    @objc private func handleMenuCloseAll() {
        onCloseAll?()
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
        let isDown = isFocusedWindow || isPressed
        let bg = isDown ? NSColor(rgba: theme.buttonPressedBackground) : NSColor(rgba: theme.buttonNormalBackground)
        bg.setFill()
        bounds.fill()
        
        if isDown {
            BevelDrawing.drawSunkenBevel(in: bounds)
        } else {
            BevelDrawing.drawRaisedBevel(in: bounds)
        }
        
        let iconSize = CGFloat(theme.iconSize)
        let iconOffset: CGFloat = isDown ? 1.0 : 0.0
        let iconX = bounds.minX + TaskbarConstants.Layout.taskButtonIconMarginRetro + iconOffset
        let iconY = bounds.midY - (iconSize / 2.0) - iconOffset
        let icon = IconCache.shared.icon(for: group.bundleID, pid: group.primaryWindow?.pid ?? 0)
        icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        
        if showTitle {
            let textX = iconX + iconSize + TaskbarConstants.Layout.taskButtonIconMarginRetro
            let maxTextW = max(0, bounds.maxX - textX - TaskbarConstants.Layout.taskButtonIconMarginRetro)
            
            let isDimmed = group.isMinimized || group.isAppHidden
            let baseColor = NSColor(rgba: isFocusedWindow ? theme.textPressedColor : theme.textColor)
            let textColor = isDimmed ? (theme.bevelShadow.map { NSColor(rgba: $0) } ?? baseColor.withAlphaComponent(0.5)) : baseColor
            
            let font = NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: isFocusedWindow ? .bold : .regular)
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: para
            ]
            let str = NSAttributedString(string: group.displayTitle, attributes: attrs)
            let lineHeight = ceil(str.size().height)
            let textY = bounds.midY - (lineHeight / 2.0) - iconOffset
            str.draw(in: NSRect(x: textX, y: textY, width: maxTextW, height: lineHeight))
        }
        
        if group.isGrouped {
            // Draw stacked tab bevel ridge on trailing edge
            let ridgeX = bounds.maxX - 5.0 + iconOffset
            let ridgeY1 = bounds.minY + 4.0
            let ridgeY2 = bounds.maxY - 4.0
            if let shadow = theme.bevelShadow {
                NSColor(rgba: shadow).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: ridgeX, y: ridgeY1))
                path.line(to: NSPoint(x: ridgeX, y: ridgeY2))
                path.lineWidth = 1.0
                path.stroke()
            }
        }
    }
    
    private func drawHybrid(_ dirtyRect: NSRect) {
        let cornerRadius = CGFloat(theme.buttonCornerRadius)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.0, dy: 1.0), xRadius: cornerRadius, yRadius: cornerRadius)
        
        let isDimmed = group.isMinimized || group.isAppHidden
        let alphaMultiplier: CGFloat = isDimmed ? TaskbarConstants.Layout.dimmedButtonAlpha : 1.0
        
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
        
        let iconSize = CGFloat(theme.iconSize)
        let iconX = bounds.minX + TaskbarConstants.Layout.taskButtonIconMarginHybrid
        let iconY = bounds.midY - (iconSize / 2.0)
        let icon = IconCache.shared.icon(for: group.bundleID, pid: group.primaryWindow?.pid ?? 0)
        icon.draw(
            in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize),
            from: .zero,
            operation: .sourceOver,
            fraction: alphaMultiplier
        )
        
        if showTitle {
            let textX = iconX + iconSize + TaskbarConstants.Layout.taskButtonIconMarginHybrid
            let maxTextW = max(0, bounds.maxX - textX - TaskbarConstants.Layout.taskButtonIconMarginHybrid)
            
            let font = NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: isFocusedWindow ? .bold : .medium)
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            
            let textColor = (isFocusedWindow ? NSColor(rgba: theme.textPressedColor) : NSColor(rgba: theme.textColor)).withAlphaComponent(alphaMultiplier)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: para
            ]
            let str = NSAttributedString(string: group.displayTitle, attributes: attrs)
            let lineHeight = ceil(str.size().height)
            let textY = bounds.midY - (lineHeight / 2.0)
            str.draw(in: NSRect(x: textX, y: textY, width: maxTextW, height: lineHeight))
        } else if group.isGrouped {
            // Draw compact pill badge in top-right corner when title is hidden
            let badgeText = "\(group.count)" as NSString
            let badgeFont = NSFont.boldSystemFont(ofSize: 9.0)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor.white
            ]
            let badgeTextSize = badgeText.size(withAttributes: badgeAttrs)
            let badgeW = max(TaskbarConstants.Layout.groupBadgeMinWidth, badgeTextSize.width + 6.0)
            let badgeH = TaskbarConstants.Layout.groupBadgeHeight
            let badgeRect = NSRect(
                x: bounds.maxX - badgeW - 3.0,
                y: bounds.maxY - badgeH - 3.0,
                width: badgeW,
                height: badgeH
            )
            let badgePath = NSBezierPath(
                roundedRect: badgeRect,
                xRadius: TaskbarConstants.Layout.groupBadgeCornerRadius,
                yRadius: TaskbarConstants.Layout.groupBadgeCornerRadius
            )
            NSColor(rgba: theme.buttonBorderPressed).setFill()
            badgePath.fill()
            let textPoint = NSPoint(
                x: badgeRect.midX - (badgeTextSize.width / 2.0),
                y: badgeRect.midY - (badgeTextSize.height / 2.0)
            )
            badgeText.draw(at: textPoint, withAttributes: badgeAttrs)
        }
    }
}
