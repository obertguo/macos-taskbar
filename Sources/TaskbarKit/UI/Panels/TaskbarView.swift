// Sources/TaskbarKit/UI/Panels/TaskbarView.swift

import AppKit
import TaskbarCore

@MainActor
public final class TaskbarView: NSView {
    public var theme: ThemeDefinition {
        didSet {
            guard oldValue != theme else { return }
            applyTheme()
        }
    }
    
    public var launcherAction: LauncherAction
    
    private let visualEffectView = NSVisualEffectView()
    public let startButton: StartButton
    public let overflowButton: OverflowButton
    public internal(set) var taskButtons: [TaskButton] = []
    private var groupButtonMap: [String: TaskButton] = [:]
    public private(set) var activeGroupPopup: GroupWindowPopup?
    private var activePopupGroupID: String?
    
    public var groupingMode: WindowGroupingMode = .always {
        didSet {
            if oldValue != groupingMode {
                updateWindows(windows: currentWindows, focusedKey: focusedKey, frontmostPID: frontmostPID, runningBundleIDs: currentRunningBundleIDs)
            }
        }
    }
    
    public internal(set) var pinnedButtons: [PinnedButton] = []
    private var pinnedButtonMap: [String: PinnedButton] = [:]
    public internal(set) var currentPinnedApps: [PinnedApp] = []
    
    public var onPinRequested: ((_ bundleID: String, _ appName: String) -> Void)?
    public var onUnpinRequested: ((_ bundleID: String) -> Void)?
    public var onPinnedReorderRequested: (([PinnedApp]) -> Void)?
    public var screenID: CGDirectDisplayID?
    public weak var store: WindowStore?
    
    private var dragCoordinator: TaskbarDragCoordinator!
    
    private var currentWindows: [WindowInfo] = []
    private var focusedKey: WindowKey?
    private var frontmostPID: pid_t?
    private var currentRunningBundleIDs: Set<String> = []
    private var pendingWindowUpdate: (windows: [WindowInfo], focusedKey: WindowKey?, frontmostPID: pid_t?, runningBundleIDs: Set<String>?)?
    private var pendingPinnedUpdate: (pinnedApps: [PinnedApp], runningBundleIDs: Set<String>)?
    
    public var minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth {
        didSet {
            if oldValue != minButtonWidth {
                if groupingMode == .whenCrowded {
                    updateWindows(windows: currentWindows, focusedKey: focusedKey, frontmostPID: frontmostPID, runningBundleIDs: currentRunningBundleIDs)
                } else {
                    layoutComponents()
                }
            }
        }
    }
    public var maxButtonWidth: Double = TaskbarConstants.Layout.defaultMaxButtonWidth {
        didSet {
            if oldValue != maxButtonWidth { layoutComponents() }
        }
    }
    public var buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing {
        didSet {
            if oldValue != buttonSpacing {
                if groupingMode == .whenCrowded {
                    updateWindows(windows: currentWindows, focusedKey: focusedKey, frontmostPID: frontmostPID, runningBundleIDs: currentRunningBundleIDs)
                } else {
                    layoutComponents()
                }
            }
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
        groupingMode: WindowGroupingMode = .always,
        pinnedApps: [PinnedApp] = [],
        store: WindowStore? = nil
    ) {
        self.theme = theme
        self.launcherAction = launcherAction
        self.minButtonWidth = minButtonWidth
        self.maxButtonWidth = maxButtonWidth
        self.buttonSpacing = buttonSpacing
        self.titleVisibilityThreshold = titleVisibilityThreshold
        self.groupingMode = groupingMode
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
        
        self.dragCoordinator = TaskbarDragCoordinator(hostView: self, theme: theme)
        self.dragCoordinator.delegate = self
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutComponents()
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutComponents()
    }
    
    public func updateWindows(
        windows: [WindowInfo],
        focusedKey: WindowKey?,
        frontmostPID: pid_t?,
        runningBundleIDs: Set<String>? = nil
    ) {
        if let running = runningBundleIDs {
            self.currentRunningBundleIDs = running
        }
        if dragCoordinator != nil && (dragCoordinator.isDragging || dragCoordinator.activeDragSession != nil) {
            pendingWindowUpdate = (windows: windows, focusedKey: focusedKey, frontmostPID: frontmostPID, runningBundleIDs: runningBundleIDs)
            return
        }
        
        self.currentWindows = windows
        self.focusedKey = focusedKey
        self.frontmostPID = frontmostPID
        
        let runningIDs = runningBundleIDs ?? (self.currentRunningBundleIDs.isEmpty ? Set(windows.map { $0.bundleID }) : self.currentRunningBundleIDs)
        let pinnedIDs = Set(currentPinnedApps.map { $0.bundleIdentifier })
        
        // Update isRunning for pinned buttons
        for btn in pinnedButtons {
            btn.isRunning = isAppRunning(bundleIdentifier: btn.pinnedApp.bundleIdentifier, runningBundleIDs: runningIDs)
        }
        
        // Compute available horizontal space for the dynamic task button area
        let availableWidth = TaskbarLayoutEngine.availableTaskAreaLength(params: currentLayoutParams())
        
        // 1. Group windows according to active WindowGroupingMode
        let groups = WindowGroupingLogic.groupWindows(
            windows,
            mode: groupingMode,
            availableWidth: Double(availableWidth),
            minButtonWidth: minButtonWidth,
            buttonSpacing: buttonSpacing
        )
        
        // 2. Apply custom ordering from WindowStore
        let orderedGroups: [WindowGroup]
        if let screenID = self.screenID, let customOrder = store?.customOrder(forScreenID: UInt32(screenID)) {
            orderedGroups = WindowOrderingLogic.applyCustomOrder(items: groups, customOrder: customOrder)
        } else {
            orderedGroups = groups
        }
        
        let currentGroupIDs = Set(orderedGroups.map { $0.id })
        
        // 3. Synchronize active popup or dismiss if no longer valid
        if let popup = activeGroupPopup, let popupGroupID = activePopupGroupID {
            if let matchingGroup = orderedGroups.first(where: { $0.id == popupGroupID }), matchingGroup.windows.count >= 2 {
                popup.updateGroup(matchingGroup, focusedKey: focusedKey, frontmostPID: frontmostPID, theme: theme)
            } else {
                popup.dismiss()
                activeGroupPopup = nil
                activePopupGroupID = nil
            }
        }
        
        // 4. Re-use existing buttons, recycle across grouping threshold, or instantiate new ones
        var orderedButtons: [TaskButton] = []
        for grp in orderedGroups {
            let isFocused = grp.isFocused(focusedKey: focusedKey, frontmostPID: frontmostPID)
            let isPinned = pinnedIDs.contains(grp.bundleID)
            
            if let existing = groupButtonMap[grp.id] {
                existing.group = grp
                existing.isFocusedWindow = isFocused
                existing.isPinned = isPinned
                existing.theme = theme
                orderedButtons.append(existing)
            } else if let recycled = groupButtonMap.values.first(where: { !currentGroupIDs.contains($0.group.id) && $0.group.bundleID == grp.bundleID }) {
                groupButtonMap.removeValue(forKey: recycled.group.id)
                groupButtonMap[grp.id] = recycled
                recycled.group = grp
                recycled.isFocusedWindow = isFocused
                recycled.isPinned = isPinned
                recycled.theme = theme
                orderedButtons.append(recycled)
            } else {
                let btn = TaskButton(
                    group: grp,
                    isFocused: isFocused,
                    showTitle: true,
                    theme: theme
                )
                btn.isPinned = isPinned
                btn.onTogglePin = { [weak self, weak btn] in
                    guard let self = self, let btn = btn else { return }
                    if btn.isPinned {
                        self.onUnpinRequested?(btn.group.bundleID)
                    } else {
                        self.onPinRequested?(btn.group.bundleID, btn.group.appName)
                    }
                }
                
                btn.onGroupClick = { [weak self, weak btn] in
                    guard let self = self, let btn = btn else { return }
                    self.showGroupPopup(for: btn)
                }
                
                btn.onMinimizeOrRestore = { [weak btn] in
                    guard let btn = btn else { return }
                    let grp = btn.group
                    if grp.isGrouped {
                        if grp.isMinimized {
                            let primary = grp.primaryWindow
                            for win in grp.windows where win.key != primary?.key {
                                AppEnvironment.current.windowActions.restoreAndFocusWindow(win.key)
                            }
                            if let primary = primary {
                                AppEnvironment.current.windowActions.restoreAndFocusWindow(primary.key)
                            }
                        } else {
                            for win in grp.windows where !win.isMinimized {
                                AppEnvironment.current.windowActions.minimizeWindow(win.key)
                            }
                        }
                    } else if let primary = grp.primaryWindow {
                        if primary.isMinimized {
                            AppEnvironment.current.windowActions.restoreAndFocusWindow(primary.key)
                        } else {
                            AppEnvironment.current.windowActions.minimizeWindow(primary.key)
                        }
                    }
                }
                
                btn.onClick = { [weak self, weak btn] in
                    guard let self = self, let btn = btn else { return }
                    if btn.group.isGrouped {
                        self.showGroupPopup(for: btn)
                    } else if let primary = btn.group.primaryWindow {
                        let action = ClickPolicy.leftClickAction(
                            for: primary,
                            focusedKey: self.focusedKey,
                            isFrontmostApp: (self.frontmostPID == primary.pid)
                        )
                        AppEnvironment.current.windowActions.performAction(action, for: primary.key)
                        
                        // Optimistic visual update
                        switch action {
                        case .minimize:
                            btn.isFocusedWindow = false
                        case .restoreAndFocus:
                            btn.isFocusedWindow = true
                        case .focus:
                            btn.isFocusedWindow = true
                        }
                    }
                }
                
                btn.onClose = { [weak btn] in
                    guard let btn = btn, let primary = btn.group.primaryWindow else { return }
                    AppEnvironment.current.windowActions.closeWindow(primary.key)
                }
                
                btn.onCloseAll = { [weak btn] in
                    guard let btn = btn else { return }
                    for win in btn.group.windows {
                        AppEnvironment.current.windowActions.closeWindow(win.key)
                    }
                }
                
                btn.onQuit = { [weak btn] in
                    guard let btn = btn else { return }
                    if let pid = btn.group.primaryWindow?.pid {
                        AppEnvironment.current.windowActions.quitApplication(pid: pid)
                    } else {
                        AppEnvironment.current.windowActions.quitApplication(bundleIdentifier: btn.group.bundleID)
                    }
                }
                
                dragCoordinator.configureTaskButtonDrag(btn)
                addSubview(btn)
                groupButtonMap[grp.id] = btn
                orderedButtons.append(btn)
            }
        }
        
        // 5. Remove buttons for closed groups
        for (id, btn) in groupButtonMap {
            if !currentGroupIDs.contains(id) {
                btn.removeFromSuperview()
                groupButtonMap.removeValue(forKey: id)
            }
        }
        
        self.taskButtons = orderedButtons
        layoutComponents()
    }
    
    public func updatePinnedApps(_ apps: [PinnedApp], runningBundleIDs: Set<String>? = nil) {
        if let running = runningBundleIDs {
            self.currentRunningBundleIDs = running
        }
        let runningIDs = runningBundleIDs ?? (self.currentRunningBundleIDs.isEmpty ? Set(currentWindows.map { $0.bundleID }) : self.currentRunningBundleIDs)
        if dragCoordinator != nil && (dragCoordinator.isDragging || dragCoordinator.activeDragSession != nil) {
            pendingPinnedUpdate = (pinnedApps: apps, runningBundleIDs: runningIDs)
            return
        }
        self.currentPinnedApps = apps
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
                    AppEnvironment.current.windowActions.launchOrActivateApp(
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
                    AppEnvironment.current.windowActions.quitApplication(bundleIdentifier: btn.pinnedApp.bundleIdentifier)
                }
                
                dragCoordinator.configurePinnedButtonDrag(btn)
                addSubview(btn)
                pinnedButtonMap[app.bundleIdentifier] = btn
                orderedButtons.append(btn)
            }
        }
        
        self.pinnedButtons = orderedButtons
        
        // Refresh isPinned on existing task buttons
        for btn in taskButtons {
            btn.isPinned = newIDs.contains(btn.group.bundleID)
        }
        
        layoutComponents()
    }
    
    public func apply(settings: Settings, theme: ThemeDefinition) {
        self.theme = theme
        self.minButtonWidth = settings.minButtonWidth
        self.maxButtonWidth = settings.maxButtonWidth
        self.buttonSpacing = settings.buttonSpacing
        self.titleVisibilityThreshold = settings.titleVisibilityThreshold
        self.groupingMode = settings.windowGroupingMode
        self.updatePinnedApps(settings.pinnedApps, runningBundleIDs: self.currentRunningBundleIDs)
    }
    
    private func isAppRunning(bundleIdentifier: String, runningBundleIDs: Set<String>) -> Bool {
        runningBundleIDs.contains(bundleIdentifier)
    }
    
    /// Returns the active PinnedButton for a given bundle identifier.
    public func pinnedButton(forBundleID bundleID: String) -> PinnedButton? {
        pinnedButtonMap[bundleID]
    }
    
    /// Returns all active PinnedButtons.
    public var allPinnedButtons: [PinnedButton] {
        pinnedButtons
    }
    
    /// Returns the active TaskButton representing a given WindowKey.
    public func button(forKey key: WindowKey) -> TaskButton? {
        taskButtons.first { $0.group.windows.contains { $0.key == key } }
    }
    
    /// Returns the active TaskButton associated with a group identifier.
    public func button(forGroupID groupID: String) -> TaskButton? {
        groupButtonMap[groupID]
    }
    
    /// Returns the count of buttons currently hidden due to overflow.
    public var overflowCount: Int {
        taskButtons.filter { $0.isHidden }.count
    }
    
    internal func currentLayoutParams() -> TaskbarLayoutParameters {
        TaskbarLayoutParameters(
            containerSize: bounds.size,
            startButtonWidth: startButton.preferredWidth(),
            pinnedItemCount: pinnedButtons.count,
            taskItemCount: taskButtons.count,
            minButtonWidth: minButtonWidth,
            maxButtonWidth: maxButtonWidth,
            buttonSpacing: buttonSpacing,
            titleVisibilityThreshold: titleVisibilityThreshold
        )
    }
    
    internal func layoutComponents() {
        visualEffectView.frame = bounds
        
        let params = currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        startButton.frame = plan.startButtonFrame
        
        for (index, btn) in pinnedButtons.enumerated() {
            if dragCoordinator != nil && dragCoordinator.isDragging(button: btn) {
                // Dragged pinned button manages its own dragged frame during live drag
            } else {
                btn.frame = plan.pinnedButtonFrames[index]
            }
        }
        
        if let overflowFrame = plan.overflowButtonFrame {
            overflowButton.isHidden = false
            overflowButton.frame = overflowFrame
        } else {
            overflowButton.isHidden = true
        }
        
        for (index, btn) in taskButtons.enumerated() {
            if index < plan.visibleTaskCount {
                btn.isHidden = false
                if dragCoordinator != nil && dragCoordinator.isDragging(button: btn) {
                    // Dragged task button manages its own dragged frame during live drag
                } else {
                    btn.frame = plan.taskButtonFrames[index]
                }
                btn.showTitle = plan.showTitle
            } else {
                btn.isHidden = true
            }
        }
    }
    
    private func commitCustomOrderToStore() {
        guard let screenID = self.screenID else { return }
        let orderMap = WindowOrderingLogic.rebuildOrderMap(for: taskButtons.map(\.group))
        store?.setCustomOrder(orderMap, forScreenID: UInt32(screenID))
    }
    
    private func flushPendingWindowUpdate() {
        guard dragCoordinator?.activeDragSession == nil else { return }
        if let pendingPinned = pendingPinnedUpdate {
            pendingPinnedUpdate = nil
            updatePinnedApps(pendingPinned.pinnedApps, runningBundleIDs: pendingPinned.runningBundleIDs)
        }
        guard let pending = pendingWindowUpdate else { return }
        pendingWindowUpdate = nil
        updateWindows(windows: pending.windows, focusedKey: pending.focusedKey, frontmostPID: pending.frontmostPID, runningBundleIDs: pending.runningBundleIDs)
    }
    
    public override func layout() {
        super.layout()
        layoutComponents()
    }
    
    // MARK: - Multi-Window Group Popup
    
    /// Displays or toggles the lightweight window list popup anchored above the given task button.
    public func showGroupPopup(for btn: TaskButton) {
        if let active = activeGroupPopup, activePopupGroupID == btn.group.id {
            active.dismiss()
            activeGroupPopup = nil
            activePopupGroupID = nil
            return
        }
        
        activeGroupPopup?.dismiss()
        activePopupGroupID = nil
        
        let screen = self.window?.screen ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let buttonRectOnScreen: NSRect
        if let win = self.window {
            let rectInWindow = btn.convert(btn.bounds, to: nil)
            buttonRectOnScreen = win.convertToScreen(rectInWindow)
        } else {
            buttonRectOnScreen = btn.frame
        }
        
        let popup = GroupWindowPopup(
            group: btn.group,
            theme: theme,
            focusedKey: focusedKey,
            frontmostPID: frontmostPID
        )
        popup.onSelectWindow = { win in
            AppEnvironment.current.windowActions.restoreAndFocusWindow(win.key)
        }
        popup.onCloseWindow = { key in
            AppEnvironment.current.windowActions.closeWindow(key)
        }
        popup.onDismiss = { [weak self] in
            self?.activeGroupPopup = nil
            self?.activePopupGroupID = nil
        }
        self.activeGroupPopup = popup
        self.activePopupGroupID = btn.group.id
        popup.show(
            anchoredTo: buttonRectOnScreen,
            in: screen,
            focusedKey: focusedKey,
            frontmostPID: frontmostPID
        )
    }
    
    /// Dismisses any currently visible window group popup panel.
    public func dismissGroupPopup() {
        activeGroupPopup?.dismiss()
        activeGroupPopup = nil
        activePopupGroupID = nil
    }
    
    private func showOverflowMenu() {
        let menu = NSMenu(title: TaskbarStrings.Overflow.menuTitle)
        menu.autoenablesItems = false
        
        let overflowingButtons = taskButtons.filter { $0.isHidden }
        guard !overflowingButtons.isEmpty else { return }
        
        for btn in overflowingButtons {
            let item = NSMenuItem(
                title: btn.group.displayTitle,
                action: #selector(handleOverflowItemClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = btn
            item.image = IconCache.shared.icon(
                for: btn.group.bundleID,
                pid: btn.group.primaryWindow?.pid ?? 0,
                size: NSSize(width: theme.iconSize, height: theme.iconSize)
            )
            
            let isActive = btn.group.isFocused(focusedKey: focusedKey, frontmostPID: frontmostPID)
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
        
        for btn in groupButtonMap.values {
            btn.theme = theme
        }
        activeGroupPopup?.theme = theme
        
        dragCoordinator?.updateTheme(theme)
        
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

// MARK: - TaskbarDragCoordinatorDelegate

extension TaskbarView: TaskbarDragCoordinatorDelegate {
    func moveTaskButton(from fromIndex: Int, to toIndex: Int) {
        dragCoordinatorDidCommitTaskReorder(from: fromIndex, to: toIndex)
    }
    
    func dragCoordinatorDidCommitTaskReorder(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex >= 0, fromIndex < taskButtons.count,
              toIndex >= 0, toIndex < taskButtons.count else { return }
        let moved = taskButtons.remove(at: fromIndex)
        taskButtons.insert(moved, at: toIndex)
        commitCustomOrderToStore()
        flushPendingWindowUpdate()
    }
    
    func movePinnedButton(from fromIndex: Int, to toIndex: Int, updatedPinnedApps: [PinnedApp]) {
        dragCoordinatorDidCommitPinnedReorder(from: fromIndex, to: toIndex, updatedPinnedApps: updatedPinnedApps)
    }
    
    func dragCoordinatorDidCommitPinnedReorder(from fromIndex: Int, to toIndex: Int, updatedPinnedApps: [PinnedApp]) {
        self.currentPinnedApps = updatedPinnedApps
        guard fromIndex >= 0, fromIndex < pinnedButtons.count,
              toIndex >= 0, toIndex < pinnedButtons.count else { return }
        let movedBtn = pinnedButtons.remove(at: fromIndex)
        pinnedButtons.insert(movedBtn, at: toIndex)
        onPinnedReorderRequested?(updatedPinnedApps)
        flushPendingWindowUpdate()
    }
    
    func dragCoordinatorDidEndDrag() {
        flushPendingWindowUpdate()
    }
    
    func dragCoordinatorRequiresLayoutUpdate() {
        flushPendingWindowUpdate()
        layoutComponents()
    }
    
    func dragCoordinatorDidRequestPopupDismissal() {
        dismissGroupPopup()
    }
}

