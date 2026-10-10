// Sources/TaskbarKit/UI/Panels/GroupWindowPopup.swift

import AppKit
import TaskbarCore

/// A lightweight popup panel displaying all open windows belonging to a grouped application.
/// Anchored directly above the corresponding taskbar button, supporting mouse selection,
/// keyboard navigation (Up/Down/Return/Escape), individual window closing, and active focus indicators.
@MainActor
public final class GroupWindowPopup: NSPanel {
    public let group: WindowGroup
    public var theme: ThemeDefinition {
        didSet {
            popupContentView.theme = theme
            popupContentView.needsDisplay = true
        }
    }
    
    public var windows: [WindowInfo] {
        get { popupContentView.windows }
        set { popupContentView.windows = newValue }
    }
    
    public var selectedIndex: Int? {
        get { popupContentView.selectedIndex }
        set { popupContentView.selectedIndex = newValue }
    }
    
    public var onSelectWindow: ((WindowInfo) -> Void)?
    public var onCloseWindow: ((WindowKey) -> Void)?
    public var onDismiss: (() -> Void)?
    
    private let popupContentView: GroupWindowContentView
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var isDismissing: Bool = false
    
    public init(
        group: WindowGroup,
        theme: ThemeDefinition,
        focusedKey: WindowKey? = nil,
        frontmostPID: pid_t? = nil
    ) {
        self.group = group
        self.theme = theme
        self.popupContentView = GroupWindowContentView(
            group: group,
            theme: theme,
            focusedKey: focusedKey,
            frontmostPID: frontmostPID
        )
        
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.contentView = popupContentView
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        
        popupContentView.onSelect = { [weak self] win in
            self?.selectWindow(win)
        }
        
        popupContentView.onClose = { [weak self] win in
            self?.handleCloseWindow(win)
        }
    }
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
    
    public override func resignKey() {
        super.resignKey()
        if !isDismissing {
            dismiss()
        }
    }
    
    public func show(
        anchoredTo buttonRect: NSRect,
        in screen: NSScreen,
        focusedKey: WindowKey?,
        frontmostPID: pid_t?
    ) {
        isDismissing = false
        popupContentView.focusedKey = focusedKey
        popupContentView.frontmostPID = frontmostPID
        
        let preferredSize = popupContentView.preferredSize()
        let screenFrame = screen.visibleFrame.isEmpty ? screen.frame : screen.visibleFrame
        
        var originX = buttonRect.minX
        if originX + preferredSize.width > screenFrame.maxX - 4.0 {
            originX = screenFrame.maxX - preferredSize.width - 4.0
        }
        if originX < screenFrame.minX + 4.0 {
            originX = screenFrame.minX + 4.0
        }
        
        let originY = buttonRect.maxY + TaskbarConstants.GroupPopup.verticalOffset
        let panelFrame = NSRect(
            x: originX,
            y: originY,
            width: preferredSize.width,
            height: preferredSize.height
        )
        
        setFrame(panelFrame, display: true)
        orderFrontRegardless()
        makeKey()
        
        installEventMonitor()
    }
    
    public func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        removeEventMonitor()
        orderOut(nil)
        onDismiss?()
    }
    
    public func selectWindow(_ window: WindowInfo) {
        onSelectWindow?(window)
        dismiss()
    }
    
    private func handleCloseWindow(_ window: WindowInfo) {
        onCloseWindow?(window.key)
        popupContentView.removeWindow(forKey: window.key)
        
        if popupContentView.windows.isEmpty {
            dismiss()
        } else {
            // Resize panel smoothly for remaining items
            let preferredSize = popupContentView.preferredSize()
            var newFrame = frame
            let heightDelta = preferredSize.height - newFrame.height
            newFrame.size.height = preferredSize.height
            newFrame.origin.y -= heightDelta
            setFrame(newFrame, display: true, animate: true)
        }
    }
    
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case TaskbarConstants.KeyCodes.escape:
            dismiss()
        case TaskbarConstants.KeyCodes.upArrow:
            popupContentView.moveSelection(up: true)
        case TaskbarConstants.KeyCodes.downArrow:
            popupContentView.moveSelection(up: false)
        case TaskbarConstants.KeyCodes.returnKey:
            if let selected = popupContentView.currentlySelectedWindow() {
                selectWindow(selected)
            }
        default:
            super.keyDown(with: event)
        }
    }
    
    private func installEventMonitor() {
        removeEventMonitor()
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            let clickLoc = NSEvent.mouseLocation
            if !self.frame.contains(clickLoc) {
                self.dismiss()
            }
            return event
        }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.dismiss()
                }
            }
        }
        
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }
    
    private func removeEventMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }
    
    deinit {
        MainActor.assumeIsolated {
            removeEventMonitor()
        }
    }
}

// MARK: - Popup Content View (Container)

@MainActor
private final class GroupWindowContentView: NSView {
    var theme: ThemeDefinition {
        didSet {
            applyTheme(theme)
        }
    }
    
    var windows: [WindowInfo] {
        get { rowsView.windows }
        set { rowsView.windows = newValue }
    }
    
    var focusedKey: WindowKey? {
        get { rowsView.focusedKey }
        set { rowsView.focusedKey = newValue }
    }
    
    var frontmostPID: pid_t? {
        get { rowsView.frontmostPID }
        set { rowsView.frontmostPID = newValue }
    }
    
    var selectedIndex: Int? {
        get { rowsView.selectedIndex }
        set { rowsView.selectedIndex = newValue }
    }
    
    var onSelect: ((WindowInfo) -> Void)? {
        get { rowsView.onSelect }
        set { rowsView.onSelect = newValue }
    }
    
    var onClose: ((WindowInfo) -> Void)? {
        get { rowsView.onClose }
        set { rowsView.onClose = newValue }
    }
    
    private let visualEffectView = NSVisualEffectView()
    private let rowsView: GroupWindowRowsView
    
    init(
        group: WindowGroup,
        theme: ThemeDefinition,
        focusedKey: WindowKey?,
        frontmostPID: pid_t?
    ) {
        self.theme = theme
        self.rowsView = GroupWindowRowsView(
            group: group,
            theme: theme,
            focusedKey: focusedKey,
            frontmostPID: frontmostPID
        )
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        layer?.masksToBounds = true
        
        // 1. Background visual effect view (frosted glass)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.isHidden = !theme.useTranslucency || theme.is3DBeveled
        visualEffectView.material = VisualEffectMapping.resolveMaterial(theme.material)
        visualEffectView.blendingMode = VisualEffectMapping.resolveBlendingMode(theme.blendingMode)
        addSubview(visualEffectView)
        
        // 2. Foreground rows view (rendered above visualEffectView)
        rowsView.autoresizingMask = [.width, .height]
        rowsView.wantsLayer = true
        addSubview(rowsView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override func layout() {
        super.layout()
        visualEffectView.frame = bounds
        rowsView.frame = bounds
    }
    
    private func applyTheme(_ theme: ThemeDefinition) {
        layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        visualEffectView.layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        visualEffectView.isHidden = !theme.useTranslucency || theme.is3DBeveled
        visualEffectView.material = VisualEffectMapping.resolveMaterial(theme.material)
        visualEffectView.blendingMode = VisualEffectMapping.resolveBlendingMode(theme.blendingMode)
        rowsView.theme = theme
    }
    
    func removeWindow(forKey key: WindowKey) {
        rowsView.removeWindow(forKey: key)
    }
    
    func currentlySelectedWindow() -> WindowInfo? {
        rowsView.currentlySelectedWindow()
    }
    
    func moveSelection(up: Bool) {
        rowsView.moveSelection(up: up)
    }
    
    func preferredSize() -> NSSize {
        rowsView.preferredSize()
    }
}

// MARK: - Foreground Rows View

@MainActor
private final class GroupWindowRowsView: NSView {
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
        
        let font = NSFont.systemFont(ofSize: CGFloat(theme.fontSize))
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
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
        let bg = NSColor(rgba: theme.backgroundColor)
        bg.setFill()
        bounds.fill()
        BevelDrawing.drawRaisedBevel(in: bounds)
    }
    
    private func drawHybridBackground() {
        let cornerRadius = TaskbarConstants.GroupPopup.cornerRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
        
        if !theme.useTranslucency || theme.backgroundColor.alpha > 0.0 {
            NSColor(rgba: theme.backgroundColor).setFill()
            path.fill()
        }
        
        NSColor(rgba: theme.buttonBorderNormal).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }
    
    private func drawRows() {
        for (index, win) in windows.enumerated() {
            let row = rowRect(forRow: index)
            let isSelected = (index == selectedIndex)
            let isHovered = (index == hoveredIndex)
            
            // 1. Row highlight
            if isSelected || isHovered {
                let highlightColor: NSColor
                if theme.is3DBeveled {
                    highlightColor = NSColor(rgba: theme.buttonPressedBackground)
                } else {
                    highlightColor = NSColor(rgba: theme.buttonHoverBackground)
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
                let dotColor = NSColor(rgba: theme.buttonBorderPressed)
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
            let icon = IconCache.shared.icon(for: win.bundleID, pid: win.pid)
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
            let closeColor = isCloseHovered ? NSColor.red : (isSelected ? NSColor(rgba: theme.textPressedColor) : NSColor(rgba: theme.textColor)).withAlphaComponent(0.6)
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
            let font = NSFont.systemFont(ofSize: CGFloat(theme.fontSize), weight: isSelected ? .bold : .regular)
            let textColor = (isSelected ? NSColor(rgba: theme.textPressedColor) : NSColor(rgba: theme.textColor)).withAlphaComponent(alpha)
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: para
            ]
            let titleStr = NSAttributedString(string: win.displayTitle, attributes: titleAttrs)
            let textH = ceil(titleStr.size().height)
            let textY = row.midY - (textH / 2.0)
            titleStr.draw(in: NSRect(x: titleX, y: textY, width: titleW, height: textH))
        }
    }
}
