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
    private var groupButtonMap: [String: TaskButton] = [:]
    public private(set) var activeGroupPopup: GroupWindowPopup?
    
    public var groupingMode: WindowGroupingMode = .always {
        didSet {
            if oldValue != groupingMode {
                updateWindows(windows: currentWindows, focusedKey: focusedKey, frontmostPID: frontmostPID)
            }
        }
    }
    
    private var pinnedButtons: [PinnedButton] = []
    private var pinnedButtonMap: [String: PinnedButton] = [:]
    public private(set) var currentPinnedApps: [PinnedApp] = []
    
    public var onPinRequested: ((_ bundleID: String, _ appName: String) -> Void)?
    public var onUnpinRequested: ((_ bundleID: String) -> Void)?
    public var onPinnedReorderRequested: (([PinnedApp]) -> Void)?
    public var screenID: CGDirectDisplayID?
    public weak var store: WindowStore?
    
    private let insertionIndicatorView = NSView()
    
    private enum DragSessionTarget {
        case task(button: TaskButton, initialIndex: Int)
        case pinned(button: PinnedButton, initialIndex: Int)
    }
    
    private struct DragSession {
        let target: DragSessionTarget
        var currentTargetSlot: Int
        let initialFrame: NSRect
        let startMouseWindowX: CGFloat
    }
    
    private var activeDragSession: DragSession?
    
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
        
        insertionIndicatorView.wantsLayer = true
        insertionIndicatorView.layer?.cornerRadius = TaskbarConstants.Drag.insertionIndicatorCornerRadius
        insertionIndicatorView.layer?.zPosition = TaskbarConstants.Drag.insertionIndicatorZPosition
        insertionIndicatorView.isHidden = true
        addSubview(insertionIndicatorView)
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
        
        // Compute available horizontal space for the dynamic task button area
        let startW = startButton.preferredWidth()
        let pinnedW = CGFloat(pinnedButtons.count) * (CGFloat(theme.iconSize) + CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing) + 8.0)
        let margins = TaskbarConstants.Layout.startButtonLeadingMargin + TaskbarConstants.Layout.startButtonTrailingMargin + TaskbarConstants.Layout.pinnedSectionTrailingMargin + TaskbarConstants.Layout.taskbarTrailingMargin
        let availableWidth = max(0, bounds.width - startW - pinnedW - margins)
        
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
        
        // 3. Remove buttons for closed groups
        for (id, btn) in groupButtonMap {
            if !currentGroupIDs.contains(id) {
                btn.removeFromSuperview()
                groupButtonMap.removeValue(forKey: id)
            }
        }
        
        // If active popup belongs to a closed group, dismiss it
        if let active = activeGroupPopup, !currentGroupIDs.contains(active.group.id) {
            active.dismiss()
            activeGroupPopup = nil
        }
        
        // 4. Re-use existing buttons or instantiate new ones
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
                        WindowActions.performAction(action, for: primary.key)
                        
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
                    WindowActions.closeWindow(primary.key)
                }
                
                btn.onCloseAll = { [weak btn] in
                    guard let btn = btn else { return }
                    for win in btn.group.windows {
                        WindowActions.closeWindow(win.key)
                    }
                }
                
                btn.onQuit = { [weak btn] in
                    guard let btn = btn else { return }
                    if let pid = btn.group.primaryWindow?.pid {
                        WindowActions.quitApplication(pid: pid)
                    } else {
                        WindowActions.quitApplication(bundleIdentifier: btn.group.bundleID)
                    }
                }
                
                configureTaskButtonDrag(btn)
                addSubview(btn)
                groupButtonMap[grp.id] = btn
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
                
                configurePinnedButtonDrag(btn)
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
    
    private func currentLayoutParams() -> TaskbarLayoutParameters {
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
    
    private func layoutComponents() {
        visualEffectView.frame = bounds
        
        let params = currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        startButton.frame = plan.startButtonFrame
        
        for (index, btn) in pinnedButtons.enumerated() {
            if let session = activeDragSession, case let .pinned(draggedBtn, _) = session.target, draggedBtn === btn {
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
                if let session = activeDragSession, case let .task(draggedBtn, _) = session.target, draggedBtn === btn {
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
    
    // MARK: - Drag-and-Drop Management
    
    private func configureTaskButtonDrag(_ btn: TaskButton) {
        btn.onDragStarted = { [weak self, weak btn] in
            guard let self = self, let btn = btn else { return }
            self.handleTaskDragStarted(btn)
        }
        btn.onDragged = { [weak self, weak btn] loc in
            guard let self = self, let btn = btn else { return }
            self.handleTaskDragged(btn, currentWindowLocation: loc)
        }
        btn.onDragEnded = { [weak self, weak btn] cancelled in
            guard let self = self, let btn = btn else { return }
            self.handleTaskDragEnded(btn, cancelled: cancelled)
        }
    }
    
    private func handleTaskDragStarted(_ btn: TaskButton) {
        activeGroupPopup?.dismiss()
        activeGroupPopup = nil
        guard let initialIndex = taskButtons.firstIndex(where: { $0 === btn }) else { return }
        let startX = btn.window?.mouseLocationOutsideOfEventStream.x ?? btn.frame.midX
        activeDragSession = DragSession(
            target: .task(button: btn, initialIndex: initialIndex),
            currentTargetSlot: initialIndex,
            initialFrame: btn.frame,
            startMouseWindowX: startX
        )
        btn.alphaValue = TaskbarConstants.Drag.draggedButtonAlpha
        btn.layer?.zPosition = TaskbarConstants.Drag.draggedButtonZPosition
        showTaskInsertionIndicator(forSlot: initialIndex)
    }
    
    private func handleTaskDragged(_ btn: TaskButton, currentWindowLocation: NSPoint) {
        guard let session = activeDragSession else { return }
        let deltaX = currentWindowLocation.x - session.startMouseWindowX
        var draggedFrame = session.initialFrame
        draggedFrame.origin.x += deltaX
        btn.frame = draggedFrame
        
        let localPoint = convert(currentWindowLocation, from: nil)
        let params = currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        let slot = plan.taskInsertionSlot(atX: localPoint.x)
        activeDragSession?.currentTargetSlot = slot
        showTaskInsertionIndicator(forSlot: slot)
    }
    
    private func handleTaskDragEnded(_ btn: TaskButton, cancelled: Bool) {
        insertionIndicatorView.isHidden = true
        btn.alphaValue = 1.0
        btn.layer?.zPosition = 0
        
        guard let session = activeDragSession else {
            layoutComponents()
            return
        }
        activeDragSession = nil
        
        if cancelled {
            btn.frame = session.initialFrame
            layoutComponents()
            return
        }
        
        let initialIndex: Int
        switch session.target {
        case let .task(draggedBtn, idx):
            guard draggedBtn === btn else { layoutComponents(); return }
            initialIndex = idx
        case .pinned:
            layoutComponents()
            return
        }
        
        let targetSlot = session.currentTargetSlot
        let destinationIndex = (initialIndex < targetSlot) ? (targetSlot - 1) : targetSlot
        
        if initialIndex != destinationIndex && initialIndex >= 0 && initialIndex < taskButtons.count && destinationIndex >= 0 && destinationIndex < taskButtons.count {
            let moved = taskButtons.remove(at: initialIndex)
            taskButtons.insert(moved, at: destinationIndex)
            
            // Commit customOrder to WindowStore keyed by WindowGroup.id and individual window IDs
            var orderMap: [String: Int] = [:]
            for (idx, b) in taskButtons.enumerated() {
                orderMap[b.group.id] = idx
                for win in b.group.windows {
                    let winKey = TaskbarConstants.Identifiers.windowID(pid: win.key.pid, id: win.key.id)
                    orderMap[winKey] = idx
                }
            }
            if let screenID = self.screenID {
                store?.setCustomOrder(orderMap, forScreenID: UInt32(screenID))
            }
        }
        layoutComponents()
    }
    
    private func showTaskInsertionIndicator(forSlot slot: Int) {
        let params = currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        if let indX = plan.taskInsertionIndicatorX(forSlot: slot, buttonSpacing: CGFloat(buttonSpacing)) {
            let indicatorW: CGFloat = TaskbarConstants.Drag.insertionIndicatorWidth
            let indicatorH = max(TaskbarConstants.Drag.insertionIndicatorMinHeight, bounds.height - TaskbarConstants.Drag.insertionIndicatorVerticalInset)
            let indicatorY = (bounds.height - indicatorH) / 2.0
            insertionIndicatorView.frame = NSRect(x: round(indX - (indicatorW / 2.0)), y: indicatorY, width: indicatorW, height: indicatorH)
            insertionIndicatorView.isHidden = false
        } else {
            insertionIndicatorView.isHidden = true
        }
    }
    
    private func configurePinnedButtonDrag(_ btn: PinnedButton) {
        btn.onDragStarted = { [weak self, weak btn] in
            guard let self = self, let btn = btn else { return }
            self.handlePinnedDragStarted(btn)
        }
        btn.onDragged = { [weak self, weak btn] loc in
            guard let self = self, let btn = btn else { return }
            self.handlePinnedDragged(btn, currentWindowLocation: loc)
        }
        btn.onDragEnded = { [weak self, weak btn] cancelled in
            guard let self = self, let btn = btn else { return }
            self.handlePinnedDragEnded(btn, cancelled: cancelled)
        }
    }
    
    private func handlePinnedDragStarted(_ btn: PinnedButton) {
        activeGroupPopup?.dismiss()
        activeGroupPopup = nil
        guard let initialIndex = pinnedButtons.firstIndex(where: { $0 === btn }) else { return }
        let startX = btn.window?.mouseLocationOutsideOfEventStream.x ?? btn.frame.midX
        activeDragSession = DragSession(
            target: .pinned(button: btn, initialIndex: initialIndex),
            currentTargetSlot: initialIndex,
            initialFrame: btn.frame,
            startMouseWindowX: startX
        )
        btn.alphaValue = TaskbarConstants.Drag.draggedButtonAlpha
        btn.layer?.zPosition = TaskbarConstants.Drag.draggedButtonZPosition
        showPinnedInsertionIndicator(forSlot: initialIndex)
    }
    
    private func handlePinnedDragged(_ btn: PinnedButton, currentWindowLocation: NSPoint) {
        guard let session = activeDragSession else { return }
        let deltaX = currentWindowLocation.x - session.startMouseWindowX
        var draggedFrame = session.initialFrame
        draggedFrame.origin.x += deltaX
        btn.frame = draggedFrame
        
        let localPoint = convert(currentWindowLocation, from: nil)
        let params = currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        let slot = plan.pinnedInsertionSlot(atX: localPoint.x)
        activeDragSession?.currentTargetSlot = slot
        showPinnedInsertionIndicator(forSlot: slot)
    }
    
    private func handlePinnedDragEnded(_ btn: PinnedButton, cancelled: Bool) {
        insertionIndicatorView.isHidden = true
        btn.alphaValue = 1.0
        btn.layer?.zPosition = 0
        
        guard let session = activeDragSession else {
            layoutComponents()
            return
        }
        activeDragSession = nil
        
        if cancelled {
            btn.frame = session.initialFrame
            layoutComponents()
            return
        }
        
        let initialIndex: Int
        switch session.target {
        case let .pinned(draggedBtn, idx):
            guard draggedBtn === btn else { layoutComponents(); return }
            initialIndex = idx
        case .task:
            layoutComponents()
            return
        }
        
        let targetSlot = session.currentTargetSlot
        let destinationIndex = (initialIndex < targetSlot) ? (targetSlot - 1) : targetSlot
        
        if initialIndex != destinationIndex && initialIndex >= 0 && initialIndex < currentPinnedApps.count && destinationIndex >= 0 && destinationIndex < currentPinnedApps.count {
            var updated = currentPinnedApps
            let moved = updated.remove(at: initialIndex)
            updated.insert(moved, at: destinationIndex)
            self.currentPinnedApps = updated
            
            let movedBtn = pinnedButtons.remove(at: initialIndex)
            pinnedButtons.insert(movedBtn, at: destinationIndex)
            
            onPinnedReorderRequested?(updated)
        }
        layoutComponents()
    }
    
    private func showPinnedInsertionIndicator(forSlot slot: Int) {
        let params = currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        if let indX = plan.pinnedInsertionIndicatorX(forSlot: slot, pinnedSpacing: CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing)) {
            let indicatorW: CGFloat = TaskbarConstants.Drag.insertionIndicatorWidth
            let indicatorH = max(TaskbarConstants.Drag.insertionIndicatorMinHeight, bounds.height - TaskbarConstants.Drag.insertionIndicatorVerticalInset)
            let indicatorY = (bounds.height - indicatorH) / 2.0
            insertionIndicatorView.frame = NSRect(x: round(indX - (indicatorW / 2.0)), y: indicatorY, width: indicatorW, height: indicatorH)
            insertionIndicatorView.isHidden = false
        } else {
            insertionIndicatorView.isHidden = true
        }
    }
    
    public override func layout() {
        super.layout()
        layoutComponents()
    }
    
    // MARK: - Multi-Window Group Popup
    
    /// Displays or toggles the lightweight window list popup anchored above the given task button.
    public func showGroupPopup(for btn: TaskButton) {
        if let active = activeGroupPopup, active.group.id == btn.group.id {
            active.dismiss()
            activeGroupPopup = nil
            return
        }
        
        activeGroupPopup?.dismiss()
        
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
            WindowActions.restoreAndFocusWindow(win.key)
        }
        popup.onCloseWindow = { key in
            WindowActions.closeWindow(key)
        }
        popup.onDismiss = { [weak self] in
            self?.activeGroupPopup = nil
        }
        self.activeGroupPopup = popup
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
            item.image = IconCache.shared.icon(for: btn.group.bundleID, pid: btn.group.primaryWindow?.pid ?? 0)
            
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
        
        let indicatorColor = NSColor(rgba: theme.buttonBorderPressed)
        insertionIndicatorView.layer?.backgroundColor = indicatorColor.cgColor
        
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
