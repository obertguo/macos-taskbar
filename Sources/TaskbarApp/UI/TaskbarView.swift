// Sources/TaskbarApp/UI/TaskbarView.swift

import AppKit
import TaskbarCore

public final class TaskbarView: NSView {
    public var theme: ThemeDefinition {
        didSet {
            applyTheme()
        }
    }
    
    public var launcherAction: LauncherAction
    
    private let visualEffectView = NSVisualEffectView()
    public let startButton: StartButton
    public let overflowButton: OverflowButton
    private var taskButtons: [TaskButton] = []
    
    private var currentWindows: [WindowInfo] = []
    private var focusedKey: WindowKey?
    private var frontmostPID: pid_t?
    
    public var minButtonWidth: Double = 80.0 {
        didSet {
            if oldValue != minButtonWidth { layoutComponents() }
        }
    }
    public var maxButtonWidth: Double = 160.0 {
        didSet {
            if oldValue != maxButtonWidth { layoutComponents() }
        }
    }
    
    public init(
        theme: ThemeDefinition,
        launcherAction: LauncherAction,
        minButtonWidth: Double = 80.0,
        maxButtonWidth: Double = 160.0
    ) {
        self.theme = theme
        self.launcherAction = launcherAction
        self.minButtonWidth = minButtonWidth
        self.maxButtonWidth = maxButtonWidth
        self.startButton = StartButton(theme: theme)
        self.overflowButton = OverflowButton(theme: theme)
        super.init(frame: .zero)
        
        setupViews()
        applyTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        wantsLayer = true
        
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .underWindowBackground
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.frame = bounds
        addSubview(visualEffectView)
        
        startButton.onClick = { [weak self] in
            guard let self = self else { return }
            Launcher.launch(self.launcherAction)
        }
        addSubview(startButton)
        
        overflowButton.isHidden = true
        overflowButton.onClick = { [weak self] in
            self?.showOverflowMenu()
        }
        addSubview(overflowButton)
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutComponents()
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutComponents()
    }
    
    public func updateWindows(windows: [WindowInfo], focusedKey: WindowKey?, frontmostPID: pid_t?) {
        self.currentWindows = windows
        self.focusedKey = focusedKey
        self.frontmostPID = frontmostPID
        
        var existingMap: [WindowKey: TaskButton] = [:]
        for btn in taskButtons {
            existingMap[btn.windowInfo.key] = btn
        }
        
        var newButtons: [TaskButton] = []
        let currentKeys = Set(windows.map { $0.key })
        
        // Remove buttons for closed windows
        for (key, btn) in existingMap {
            if !currentKeys.contains(key) {
                btn.removeFromSuperview()
            }
        }
        
        for win in windows {
            // A minimized or hidden window can never be drawn as focused
            let isFocused = !win.isMinimized && !win.isAppHidden && (win.key == focusedKey && win.pid == frontmostPID)
            
            if let existing = existingMap[win.key] {
                existing.windowInfo = win
                existing.isFocusedWindow = isFocused
                newButtons.append(existing)
            } else {
                let btn = TaskButton(
                    windowInfo: win,
                    isFocused: isFocused,
                    showTitle: true,
                    theme: theme
                )
                
                btn.onClick = { [weak self, weak btn] in
                    guard let self = self, let btn = btn else { return }
                    let action = ClickPolicy.leftClickAction(
                        for: btn.windowInfo,
                        focusedKey: self.focusedKey,
                        isFrontmostApp: (self.frontmostPID == btn.windowInfo.pid)
                    )
                    WindowActions.performAction(action, for: btn.windowInfo.key)
                    
                    // Optimistic visual update
                    switch action {
                    case .minimize:
                        btn.windowInfo.isMinimized = true
                        btn.isFocusedWindow = false
                    case .restoreAndFocus:
                        btn.windowInfo.isMinimized = false
                        btn.isFocusedWindow = true
                    case .focus:
                        btn.isFocusedWindow = true
                    }
                }
                btn.onClose = { [weak btn] in
                    guard let btn = btn else { return }
                    WindowActions.closeWindow(btn.windowInfo.key)
                }
                btn.onQuit = { [weak btn] in
                    guard let btn = btn else { return }
                    WindowActions.quitApplication(pid: btn.windowInfo.pid)
                }
                
                addSubview(btn)
                newButtons.append(btn)
            }
        }
        
        self.taskButtons = newButtons
        layoutComponents()
    }
    
    private func layoutComponents() {
        visualEffectView.frame = bounds
        
        let padY: CGFloat = 2.0
        let btnH = max(18.0, bounds.height - (padY * 2))
        let startBtnW: CGFloat = (theme.style == .retroClassic) ? 56.0 : 62.0
        startButton.frame = NSRect(x: 3.0, y: padY, width: startBtnW, height: btnH)
        
        let startX = startButton.frame.maxX + 4.0
        let totalAvailableW = max(0.0, bounds.width - startX - 4.0)
        
        // Initial layout calculation
        var layout = ButtonLayout.computeLayout(
            availableWidth: Double(totalAvailableW),
            itemCount: taskButtons.count,
            maxButtonWidth: maxButtonWidth,
            minButtonWidth: minButtonWidth,
            spacing: 2.0
        )
        
        let overflowBtnW: CGFloat = 26.0
        if layout.hasOverflow {
            // Reserve space for the overflow chevron button on the right edge
            let netAvailableW = max(0.0, totalAvailableW - overflowBtnW - 2.0)
            layout = ButtonLayout.computeLayout(
                availableWidth: Double(netAvailableW),
                itemCount: taskButtons.count,
                maxButtonWidth: maxButtonWidth,
                minButtonWidth: minButtonWidth,
                spacing: 2.0
            )
            
            overflowButton.isHidden = false
            overflowButton.frame = NSRect(
                x: bounds.width - overflowBtnW - 3.0,
                y: padY,
                width: overflowBtnW,
                height: btnH
            )
        } else {
            overflowButton.isHidden = true
        }
        
        var currentX = startX
        for (index, btn) in taskButtons.enumerated() {
            if index < layout.visibleCount {
                btn.isHidden = false
                btn.frame = NSRect(
                    x: currentX,
                    y: padY,
                    width: CGFloat(layout.buttonWidth),
                    height: btnH
                )
                btn.showTitle = layout.showTitle
                currentX += CGFloat(layout.buttonWidth) + 2.0
            } else {
                btn.isHidden = true
            }
        }
    }
    
    private func showOverflowMenu() {
        let menu = NSMenu(title: "Overflow Windows")
        menu.autoenablesItems = false
        
        let overflowingButtons = taskButtons.filter { $0.isHidden }
        guard !overflowingButtons.isEmpty else { return }
        
        for btn in overflowingButtons {
            let win = btn.windowInfo
            let item = NSMenuItem(
                title: win.displayTitle,
                action: #selector(handleOverflowItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = btn
            item.image = IconCache.shared.icon(for: win.bundleID, pid: win.pid)
            
            let isActive = !win.isMinimized && !win.isAppHidden && (win.key == focusedKey && win.pid == frontmostPID)
            item.state = isActive ? .on : .off
            
            menu.addItem(item)
        }
        
        let menuOrigin = NSPoint(x: 0, y: bounds.height + 2.0)
        menu.popUp(positioning: nil, at: menuOrigin, in: overflowButton)
    }
    
    @objc private func handleOverflowItemClicked(_ sender: NSMenuItem) {
        guard let btn = sender.representedObject as? TaskButton else { return }
        btn.onClick?()
    }
    
    private func applyTheme() {
        startButton.theme = theme
        overflowButton.theme = theme
        visualEffectView.isHidden = !theme.useTranslucency
        
        for btn in taskButtons {
            btn.theme = theme
        }
        
        layoutComponents()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        switch theme.style {
        case .retroClassic:
            NSColor(rgba: theme.backgroundColor).setFill()
            bounds.fill()
            
            if let topBorder = theme.topBorderColor {
                NSColor(rgba: topBorder).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
                path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
                path.lineWidth = 1.0
                path.stroke()
            }
            
        case .modernHybrid:
            if let topBorder = theme.topBorderColor {
                NSColor(rgba: topBorder).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
                path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
                path.lineWidth = 1.0
                path.stroke()
            }
        }
    }
}
