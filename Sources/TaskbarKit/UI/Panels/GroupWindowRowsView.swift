// Sources/TaskbarKit/UI/Panels/GroupWindowRowsView.swift

import AppKit
import TaskbarCore

/// A dedicated rows view that renders window item titles, icons, focus indicators,
/// and close buttons for a window group popup panel.
@MainActor
internal final class GroupWindowRowsView: NSView {
    var theme: ThemeDefinition {
        didSet {
            needsDisplay = true
        }
    }
    
    var windows: [WindowInfo] {
        didSet {
            updateTrackingAreas()
            needsDisplay = true
        }
    }
    
    var focusedKey: WindowKey? {
        didSet {
            if oldValue != focusedKey {
                needsDisplay = true
            }
        }
    }
    
    var frontmostPID: pid_t? {
        didSet {
            if oldValue != frontmostPID {
                needsDisplay = true
            }
        }
    }
    
    var selectedIndex: Int? = 0 {
        didSet {
            needsDisplay = true
        }
    }
    
    private var hoveredIndex: Int? {
        didSet {
            if oldValue != hoveredIndex {
                needsDisplay = true
            }
        }
    }
    
    private var hoveredCloseIndex: Int? {
        didSet {
            if oldValue != hoveredCloseIndex {
                needsDisplay = true
            }
        }
    }
    
    var onSelect: ((WindowInfo) -> Void)?
    var onClose: ((WindowInfo) -> Void)?
    
    private var trackingAreaRef: NSTrackingArea?
    
    init(
        group: WindowGroup,
        theme: ThemeDefinition,
        focusedKey: WindowKey?,
        frontmostPID: pid_t?
    ) {
        self.theme = theme
        self.windows = group.windows
        self.focusedKey = focusedKey
        self.frontmostPID = frontmostPID
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    func removeWindow(forKey key: WindowKey) {
        windows.removeAll { $0.key == key }
        if let sel = selectedIndex, sel >= windows.count {
            selectedIndex = max(0, windows.count - 1)
        }
        updateTrackingAreas()
        needsDisplay = true
    }
    
    func currentlySelectedWindow() -> WindowInfo? {
        guard let idx = selectedIndex, idx >= 0, idx < windows.count else { return nil }
        return windows[idx]
    }
    
    func moveSelection(up: Bool) {
        guard !windows.isEmpty else { return }
        let current = selectedIndex ?? (up ? windows.count : -1)
        let next = up ? max(0, current - 1) : min(windows.count - 1, current + 1)
        selectedIndex = next
    }
    
    func preferredSize() -> NSSize {
        let count = max(1, windows.count)
        let height = CGFloat(count) * TaskbarConstants.GroupPopup.rowHeight + TaskbarConstants.GroupPopup.contentVerticalPadding * 2.0
        
        let resolved = ResolvedTheme.resolve(theme)
        let attrs = resolved.normalTextAttributes
        var maxTitleW: CGFloat = 0.0
        for win in windows {
            let title = win.displayTitle as NSString
            let w = title.size(withAttributes: attrs).width
            if w > maxTitleW { maxTitleW = w }
        }
        
        let chromeWidth = TaskbarConstants.GroupPopup.contentHorizontalPadding * 2.0 +
            TaskbarConstants.GroupPopup.activeDotSize +
            TaskbarConstants.GroupPopup.itemSpacing +
            CGFloat(theme.iconSize) +
            TaskbarConstants.GroupPopup.itemSpacing +
            TaskbarConstants.GroupPopup.closeButtonSize +
            TaskbarConstants.GroupPopup.itemSpacing * 2.0
        
        let width = min(
            TaskbarConstants.GroupPopup.maxWidth,
            max(TaskbarConstants.GroupPopup.minWidth, maxTitleW + chromeWidth)
        )
        return NSSize(width: width, height: height)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingAreaRef {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingAreaRef = area
    }
    
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        updateHoverStates(for: loc)
    }
    
    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        hoveredCloseIndex = nil
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard let rowIdx = rowIndex(at: loc) else { return }
        
        let closeHit = closeHitRect(forRow: rowIdx)
        if closeHit.contains(loc) {
            onClose?(windows[rowIdx])
        } else {
            selectedIndex = rowIdx
            onSelect?(windows[rowIdx])
        }
    }
    
    private func updateHoverStates(for location: NSPoint) {
        guard let rowIdx = rowIndex(at: location) else {
            hoveredIndex = nil
            hoveredCloseIndex = nil
            return
        }
        hoveredIndex = rowIdx
        selectedIndex = rowIdx
        
        let closeHit = closeHitRect(forRow: rowIdx)
        hoveredCloseIndex = closeHit.contains(location) ? rowIdx : nil
    }
    
    private func rowIndex(at location: NSPoint) -> Int? {
        guard !windows.isEmpty else { return nil }
        let padding = TaskbarConstants.GroupPopup.contentVerticalPadding
        let rowH = TaskbarConstants.GroupPopup.rowHeight
        guard location.y >= padding && location.y <= bounds.height - padding else { return nil }
        
        let invertedY = bounds.height - padding - location.y
        let idx = Int(invertedY / rowH)
        guard idx >= 0 && idx < windows.count else { return nil }
        return idx
    }
    
    private func rowRect(forRow index: Int) -> NSRect {
        let paddingH = TaskbarConstants.GroupPopup.contentHorizontalPadding
        let paddingV = TaskbarConstants.GroupPopup.contentVerticalPadding
        let rowH = TaskbarConstants.GroupPopup.rowHeight
        let y = bounds.height - paddingV - CGFloat(index + 1) * rowH
        return NSRect(x: paddingH, y: y, width: bounds.width - paddingH * 2.0, height: rowH)
    }
    
    private func closeButtonRect(forRow index: Int) -> NSRect {
        let row = rowRect(forRow: index)
        let size = TaskbarConstants.GroupPopup.closeButtonSize
        return NSRect(
            x: row.maxX - size - TaskbarConstants.GroupPopup.itemSpacing,
            y: row.midY - (size / 2.0),
            width: size,
            height: size
        )
    }
    
    private func closeHitRect(forRow index: Int) -> NSRect {
        closeButtonRect(forRow: index).insetBy(dx: -4.0, dy: -4.0)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if theme.is3DBeveled {
            drawRetroBackground()
        } else {
            drawHybridBackground()
        }
        
        drawRows()
    }
    
    private func drawRetroBackground() {
        let resolved = ResolvedTheme.resolve(theme)
        let bg = resolved.backgroundColor
        bg.setFill()
        bounds.fill()
        BevelDrawing.drawRaisedBevel(in: bounds, palette: theme.palette)
    }
    
    private func drawHybridBackground() {
        let resolved = ResolvedTheme.resolve(theme)
        let cornerRadius = TaskbarConstants.GroupPopup.cornerRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        
        if !theme.useTranslucency || theme.backgroundColor.alpha > 0.0 {
            resolved.backgroundColor.setFill()
            path.fill()
        }
        
        resolved.buttonBorderNormal.setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }
    
    private func drawRows() {
        let resolved = ResolvedTheme.resolve(theme)
        for (index, win) in windows.enumerated() {
            let row = rowRect(forRow: index)
            let isSelected = (index == selectedIndex)
            let isHovered = (index == hoveredIndex)
            
            // 1. Row highlight
            if isSelected || isHovered {
                let highlightColor: NSColor
                if theme.is3DBeveled {
                    highlightColor = resolved.buttonPressedBackground
                } else {
                    highlightColor = resolved.buttonHoverBackground
                }
                highlightColor.setFill()
                let rowPath = NSBezierPath(
                    roundedRect: row,
                    xRadius: theme.is3DBeveled ? 0 : 4.0,
                    yRadius: theme.is3DBeveled ? 0 : 4.0
                )
                rowPath.fill()
            }
            
            // 2. Active focused indicator dot
            let isActive = !win.isMinimized && !win.isAppHidden && (win.key == focusedKey && win.pid == frontmostPID)
            let dotSize = TaskbarConstants.GroupPopup.activeDotSize
            let dotRect = NSRect(
                x: row.minX + 4.0,
                y: row.midY - (dotSize / 2.0),
                width: dotSize,
                height: dotSize
            )
            if isActive {
                let dotColor = resolved.buttonBorderPressed
                dotColor.setFill()
                let dotPath = NSBezierPath(ovalIn: dotRect)
                dotPath.fill()
            }
            
            // 3. Application / Window Icon
            let iconSize = CGFloat(theme.iconSize)
            let iconX = dotRect.maxX + TaskbarConstants.GroupPopup.itemSpacing
            let iconRect = NSRect(
                x: iconX,
                y: row.midY - (iconSize / 2.0),
                width: iconSize,
                height: iconSize
            )
            let icon = IconCache.shared.icon(
                for: win.bundleID,
                pid: win.pid,
                size: NSSize(width: theme.iconSize, height: theme.iconSize)
            )
            let isDimmed = win.isMinimized || win.isAppHidden
            let alpha: CGFloat = isDimmed ? TaskbarConstants.Layout.dimmedButtonAlpha : 1.0
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: alpha)
            
            // 4. Close Button (✕)
            let closeRect = closeButtonRect(forRow: index)
            let isCloseHovered = (index == hoveredCloseIndex)
            if isCloseHovered {
                let hoverBg = NSColor.red.withAlphaComponent(0.2)
                hoverBg.setFill()
                let bgPath = NSBezierPath(roundedRect: closeRect, xRadius: 3.0, yRadius: 3.0)
                bgPath.fill()
            }
            let closeFont = NSFont.systemFont(ofSize: 11.0, weight: isCloseHovered ? .bold : .regular)
            let closeColor = isCloseHovered ? NSColor.red : (isSelected ? resolved.textPressedColor : resolved.textColor).withAlphaComponent(0.6)
            let closeAttrs: [NSAttributedString.Key: Any] = [
                .font: closeFont,
                .foregroundColor: closeColor
            ]
            let glyph = TaskbarStrings.WindowGrouping.closeWindowGlyph as NSString
            let glyphSize = glyph.size(withAttributes: closeAttrs)
            let glyphPoint = NSPoint(
                x: closeRect.midX - (glyphSize.width / 2.0),
                y: closeRect.midY - (glyphSize.height / 2.0)
            )
            glyph.draw(at: glyphPoint, withAttributes: closeAttrs)
            
            // 5. Window Title
            let titleX = iconRect.maxX + TaskbarConstants.GroupPopup.itemSpacing
            let titleW = max(0, closeRect.minX - titleX - TaskbarConstants.GroupPopup.itemSpacing)
            
            let baseAttrs = isSelected ? resolved.boldPressedTextAttributes : resolved.normalTextAttributes
            let titleAttrs: [NSAttributedString.Key: Any]
            if isDimmed {
                let textColor = (isSelected ? resolved.textPressedColor : resolved.textColor).withAlphaComponent(alpha)
                var dimmedAttrs = baseAttrs
                dimmedAttrs[.foregroundColor] = textColor
                titleAttrs = dimmedAttrs
            } else {
                titleAttrs = baseAttrs
            }
            
            let titleStr = NSAttributedString(string: win.displayTitle, attributes: titleAttrs)
            let textH = ceil(titleStr.size().height)
            let textY = row.midY - (textH / 2.0)
            titleStr.draw(in: NSRect(x: titleX, y: textY, width: titleW, height: textH))
        }
    }
}
