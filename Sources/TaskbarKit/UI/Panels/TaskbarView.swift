// Sources/TaskbarKit/UI/Panels/TaskbarView.swift

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
    private var buttonMap: [WindowKey: TaskButton] = [:]
    
    private var pinnedButtons: [PinnedButton] = []
    private var pinnedButtonMap: [String: PinnedButton] = [:]
    public private(set) var currentPinnedApps: [PinnedApp] = []
    
    public var onPinRequested: ((_ bundleID: String, _ appName: String) -> Void)?
    public var onUnpinRequested: ((_ bundleID: String) -> Void)?
    public weak var store: WindowStore?
    
    private var currentWindows: [WindowInfo] = []
    private var focusedKey: WindowKey?
    private var frontmostPID: pid_t?
    
    public var minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth {
        didSet {
            if oldValue != minButtonWidth { layoutComponents() }
        }
    }
    public var maxButtonWidth: Double = TaskbarConstants.Layout.defaultMaxButtonWidth {
        didSet {
            if oldValue != maxButtonWidth { layoutComponents() }
        }
    }
    public var buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing {
        didSet {
            if oldValue != buttonSpacing { layoutComponents() }
        }
    }
    public var titleVisibilityThreshold: Double = TaskbarConstants.Layout.defaultTitleVisibilityThreshold {
        didSet {
            if oldValue != titleVisibilityThreshold { layoutComponents() }
        }
    }
    
    public init(
        theme: ThemeDefinition,
        launcherAction: LauncherAction,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        maxButtonWidth: Double = TaskbarConstants.Layout.defaultMaxButtonWidth,
        buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing,
        titleVisibilityThreshold: Double = TaskbarConstants.Layout.defaultTitleVisibilityThreshold,
        pinnedApps: [PinnedApp] = [],
        store: WindowStore? = nil
    ) {
        self.theme = theme
        self.launcherAction = launcherAction
        self.minButtonWidth = minButtonWidth
        self.maxButtonWidth = maxButtonWidth
        self.buttonSpacing = buttonSpacing
        self.titleVisibilityThreshold = titleVisibilityThreshold
        self.store = store
        self.startButton = StartButton(theme: theme)
        self.overflowButton = OverflowButton(theme: theme)
        super.init(frame: .zero)
        
        setupViews()
        applyTheme()
        if !pinnedApps.isEmpty {
            updatePinnedApps(pinnedApps)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        wantsLayer = true
        
        visualEffectView.blendingMode = VisualEffectMapping.resolveBlendingMode(theme.blendingMode)
        visualEffectView.material = VisualEffectMapping.resolveMaterial(theme.material)
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
        
        let runningIDs = Set(windows.map { $0.bundleID })
        let pinnedIDs = Set(currentPinnedApps.map { $0.bundleIdentifier })
        
        // Update isRunning for pinned buttons
        for btn in pinnedButtons {
            btn.isRunning = isAppRunning(bundleIdentifier: btn.pinnedApp.bundleIdentifier, runningBundleIDs: runningIDs)
        }
        
        let currentKeys = Set(windows.map { $0.key })
        
        // 1. Remove buttons for closed windows
        for (key, btn) in buttonMap {
            if !currentKeys.contains(key) {
                btn.removeFromSuperview()
                buttonMap.removeValue(forKey: key)
            }
        }
        
        // 2. Re-use existing buttons or instantiate new ones
        var orderedButtons: [TaskButton] = []
        for win in windows {
            let isFocused = !win.isMinimized && !win.isAppHidden && (win.key == focusedKey && win.pid == frontmostPID)
            let isPinned = pinnedIDs.contains(win.bundleID)
            
            if let existing = buttonMap[win.key] {
                existing.windowInfo = win
                existing.isFocusedWindow = isFocused
                existing.isPinned = isPinned
                existing.theme = theme
                orderedButtons.append(existing)
            } else {
                let btn = TaskButton(
                    windowInfo: win,
                    isFocused: isFocused,
                    showTitle: true,
                    theme: theme
                )
                btn.isPinned = isPinned
                btn.onTogglePin = { [weak self, weak btn] in
                    guard let self = self, let btn = btn else { return }
                    if btn.isPinned {
                        self.onUnpinRequested?(btn.windowInfo.bundleID)
                    } else {
                        self.onPinRequested?(btn.windowInfo.bundleID, btn.windowInfo.appName)
                    }
                }
                
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
                buttonMap[win.key] = btn
                orderedButtons.append(btn)
            }
        }
        
        self.taskButtons = orderedButtons
        layoutComponents()
    }
    
    public func updatePinnedApps(_ apps: [PinnedApp], runningBundleIDs: Set<String>? = nil) {
        self.currentPinnedApps = apps
        let runningIDs = runningBundleIDs ?? Set(currentWindows.map { $0.bundleID })
        let newIDs = Set(apps.map { $0.bundleIdentifier })
        
        // 1. Remove buttons for unpinned apps
        for (bundleID, btn) in pinnedButtonMap {
            if !newIDs.contains(bundleID) {
                btn.removeFromSuperview()
                pinnedButtonMap.removeValue(forKey: bundleID)
            }
        }
        
        // 2. Recycle existing or instantiate new pinned buttons
        var orderedButtons: [PinnedButton] = []
        for app in apps {
            let running = isAppRunning(bundleIdentifier: app.bundleIdentifier, runningBundleIDs: runningIDs)
            if let existing = pinnedButtonMap[app.bundleIdentifier] {
                existing.pinnedApp = app
                existing.isRunning = running
                existing.theme = theme
                orderedButtons.append(existing)
            } else {
                let btn = PinnedButton(
                    pinnedApp: app,
                    isRunning: running,
                    theme: theme
                )
                btn.onClick = { [weak self, weak btn] in
                    guard let self = self, let btn = btn else { return }
                    WindowActions.launchOrActivateApp(
                        bundleIdentifier: btn.pinnedApp.bundleIdentifier,
                        customPath: btn.pinnedApp.customPath,
                        store: self.store
                    )
                }
                btn.onUnpin = { [weak self, weak btn] in
                    guard let self = self, let btn = btn else { return }
                    self.onUnpinRequested?(btn.pinnedApp.bundleIdentifier)
                }
                btn.onQuit = { [weak btn] in
                    guard let btn = btn else { return }
                    WindowActions.quitApplication(bundleIdentifier: btn.pinnedApp.bundleIdentifier)
                }
                addSubview(btn)
                pinnedButtonMap[app.bundleIdentifier] = btn
                orderedButtons.append(btn)
            }
        }
        
        self.pinnedButtons = orderedButtons
        
        // Refresh isPinned on existing task buttons
        for btn in taskButtons {
            btn.isPinned = newIDs.contains(btn.windowInfo.bundleID)
        }
        
        layoutComponents()
    }
    
    private func isAppRunning(bundleIdentifier: String, runningBundleIDs: Set<String>) -> Bool {
        if runningBundleIDs.contains(bundleIdentifier) { return true }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return runningApps.contains { !$0.isTerminated }
    }
    
    /// Returns the active PinnedButton for a given bundle identifier.
    public func pinnedButton(forBundleID bundleID: String) -> PinnedButton? {
        pinnedButtonMap[bundleID]
    }
    
    /// Returns all active PinnedButtons.
    public var allPinnedButtons: [PinnedButton] {
        pinnedButtons
    }
    
    /// Returns the active TaskButton associated with a WindowKey.
    public func button(forKey key: WindowKey) -> TaskButton? {
        buttonMap[key]
    }
    
    /// Returns the count of buttons currently hidden due to overflow.
    public var overflowCount: Int {
        taskButtons.filter { $0.isHidden }.count
    }
    
    private func layoutComponents() {
        visualEffectView.frame = bounds
        
        let padY = TaskbarConstants.Layout.taskbarVerticalPadding
        let btnH = max(TaskbarConstants.Layout.minimumButtonHeight, bounds.height - (padY * 2))
        let startBtnW = startButton.preferredWidth()
        startButton.frame = NSRect(
            x: TaskbarConstants.Layout.startButtonLeadingMargin,
            y: padY,
            width: startBtnW,
            height: btnH
        )
        
        var currentX = startButton.frame.maxX + TaskbarConstants.Layout.startButtonTrailingMargin
        
        // Layout Pinned Buttons
        for btn in pinnedButtons {
            btn.frame = NSRect(
                x: currentX,
                y: padY,
                width: btnH,
                height: btnH
            )
            currentX += btnH + TaskbarConstants.Layout.pinnedButtonSpacing
        }
        
        if !pinnedButtons.isEmpty {
            currentX += (TaskbarConstants.Layout.pinnedSectionTrailingMargin - TaskbarConstants.Layout.pinnedButtonSpacing)
        }
        
        let startX = currentX
        let totalAvailableW = max(0.0, bounds.width - startX - TaskbarConstants.Layout.taskbarTrailingMargin)
        
        // Initial layout calculation
        var layout = ButtonLayout.computeLayout(
            availableWidth: Double(totalAvailableW),
            itemCount: taskButtons.count,
            maxButtonWidth: maxButtonWidth,
            minButtonWidth: minButtonWidth,
            spacing: buttonSpacing,
            titleVisibilityThreshold: titleVisibilityThreshold
        )
        
        let overflowBtnW = TaskbarConstants.Layout.overflowButtonWidth
        if layout.hasOverflow {
            // Reserve space for the overflow chevron button on the right edge
            let netAvailableW = max(0.0, totalAvailableW - overflowBtnW - CGFloat(buttonSpacing))
            layout = ButtonLayout.computeLayout(
                availableWidth: Double(netAvailableW),
                itemCount: taskButtons.count,
                maxButtonWidth: maxButtonWidth,
                minButtonWidth: minButtonWidth,
                spacing: buttonSpacing,
                titleVisibilityThreshold: titleVisibilityThreshold
            )
            
            overflowButton.isHidden = false
            overflowButton.frame = NSRect(
                x: bounds.width - overflowBtnW - TaskbarConstants.Layout.overflowButtonTrailingMargin,
                y: padY,
                width: overflowBtnW,
                height: btnH
            )
        } else {
            overflowButton.isHidden = true
        }
        
        var taskBtnX = startX
        for (index, btn) in taskButtons.enumerated() {
            if index < layout.visibleCount {
                btn.isHidden = false
                btn.frame = NSRect(
                    x: taskBtnX,
                    y: padY,
                    width: CGFloat(layout.buttonWidth),
                    height: btnH
                )
                btn.showTitle = layout.showTitle
                taskBtnX += CGFloat(layout.buttonWidth) + CGFloat(buttonSpacing)
            } else {
                btn.isHidden = true
            }
        }
    }
    
    public override func layout() {
        super.layout()
        layoutComponents()
    }
    
    private func showOverflowMenu() {
        let menu = NSMenu(title: TaskbarStrings.Overflow.menuTitle)
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
        
        let menuOrigin = NSPoint(x: 0, y: bounds.height + TaskbarConstants.Layout.overflowMenuVerticalOffset)
        menu.popUp(positioning: nil, at: menuOrigin, in: overflowButton)
    }
    
    @objc private func handleOverflowItemClicked(_ sender: NSMenuItem) {
        guard let btn = sender.representedObject as? TaskButton else { return }
        btn.onClick?()
    }
    
    /// Current material applied to the underlying visual effect view.
    public var currentMaterial: NSVisualEffectView.Material {
        visualEffectView.material
    }
    
    /// Current blending mode applied to the underlying visual effect view.
    public var currentBlendingMode: NSVisualEffectView.BlendingMode {
        visualEffectView.blendingMode
    }
    
    private func applyTheme() {
        startButton.theme = theme
        overflowButton.theme = theme
        visualEffectView.isHidden = !theme.useTranslucency
        visualEffectView.material = VisualEffectMapping.resolveMaterial(theme.material)
        visualEffectView.blendingMode = VisualEffectMapping.resolveBlendingMode(theme.blendingMode)
        
        for btn in pinnedButtons {
            btn.theme = theme
        }
        
        for btn in buttonMap.values {
            btn.theme = theme
        }
        
        layoutComponents()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if !theme.useTranslucency || theme.backgroundColor.alpha > 0.0 {
            NSColor(rgba: theme.backgroundColor).setFill()
            bounds.fill()
        }
        
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
