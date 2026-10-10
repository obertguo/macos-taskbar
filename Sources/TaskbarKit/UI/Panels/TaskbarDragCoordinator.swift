// Sources/TaskbarKit/UI/Panels/TaskbarDragCoordinator.swift

import AppKit
import TaskbarCore

/// Delegate protocol allowing `TaskbarDragCoordinator` to communicate reorder commits
/// and layout requests back to the owning `TaskbarView`.
@MainActor
internal protocol TaskbarDragCoordinatorDelegate: AnyObject {
    var taskButtons: [TaskButton] { get set }
    var pinnedButtons: [PinnedButton] { get set }
    var currentPinnedApps: [PinnedApp] { get set }
    var buttonSpacing: Double { get }
    
    func currentLayoutParams() -> TaskbarLayoutParameters
    func dragCoordinatorDidCommitTaskReorder(from fromIndex: Int, to toIndex: Int)
    func dragCoordinatorDidCommitPinnedReorder(from fromIndex: Int, to toIndex: Int, updatedPinnedApps: [PinnedApp])
    func dragCoordinatorRequiresLayoutUpdate()
    func dragCoordinatorDidRequestPopupDismissal()
}

/// Coordinates drag-and-drop slot reordering for task and pinned buttons,
/// managing drag session states, insertion indicator rendering, and drop commits.
@MainActor
internal final class TaskbarDragCoordinator {
    internal enum DragSessionTarget {
        case task(button: TaskButton, initialIndex: Int)
        case pinned(button: PinnedButton, initialIndex: Int)
    }
    
    internal struct DragSession {
        let target: DragSessionTarget
        var currentTargetSlot: Int
        let initialFrame: NSRect
        let startMouseWindowX: CGFloat
    }
    
    internal private(set) var activeDragSession: DragSession?
    internal let insertionIndicatorView = NSView()
    
    internal func isDragging(button: NSView) -> Bool {
        guard let session = activeDragSession else { return false }
        switch session.target {
        case let .task(btn, _):
            return btn === button
        case let .pinned(btn, _):
            return btn === button
        }
    }
    
    internal weak var delegate: TaskbarDragCoordinatorDelegate?
    private weak var hostView: NSView?
    
    init(hostView: NSView, theme: ThemeDefinition) {
        self.hostView = hostView
        setupIndicatorView(theme: theme)
    }
    
    private func setupIndicatorView(theme: ThemeDefinition) {
        insertionIndicatorView.wantsLayer = true
        insertionIndicatorView.isHidden = true
        insertionIndicatorView.layer?.cornerRadius = TaskbarConstants.Drag.insertionIndicatorCornerRadius
        updateTheme(theme)
        hostView?.addSubview(insertionIndicatorView)
    }
    
    func updateTheme(_ theme: ThemeDefinition) {
        let indicatorColor = NSColor(rgba: theme.buttonBorderPressed)
        insertionIndicatorView.layer?.backgroundColor = indicatorColor.cgColor
    }
    
    // MARK: - Task Button Drag Configuration
    
    func configureTaskButtonDrag(_ btn: TaskButton) {
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
        guard let delegate = delegate, let hostView = hostView else { return }
        delegate.dragCoordinatorDidRequestPopupDismissal()
        
        guard let initialIndex = delegate.taskButtons.firstIndex(where: { $0 === btn }) else { return }
        let startX = btn.window?.mouseLocationOutsideOfEventStream.x ?? btn.frame.midX
        activeDragSession = DragSession(
            target: .task(button: btn, initialIndex: initialIndex),
            currentTargetSlot: initialIndex,
            initialFrame: btn.frame,
            startMouseWindowX: startX
        )
        btn.alphaValue = TaskbarConstants.Drag.draggedButtonAlpha
        btn.layer?.zPosition = TaskbarConstants.Drag.draggedButtonZPosition
        showTaskInsertionIndicator(forSlot: initialIndex, in: hostView)
    }
    
    private func handleTaskDragged(_ btn: TaskButton, currentWindowLocation: NSPoint) {
        guard let session = activeDragSession, let delegate = delegate, let hostView = hostView else { return }
        let deltaX = currentWindowLocation.x - session.startMouseWindowX
        var draggedFrame = session.initialFrame
        draggedFrame.origin.x += deltaX
        btn.frame = draggedFrame
        
        let localPoint = hostView.convert(currentWindowLocation, from: nil)
        let params = delegate.currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        let slot = plan.taskInsertionSlot(atX: localPoint.x)
        activeDragSession?.currentTargetSlot = slot
        showTaskInsertionIndicator(forSlot: slot, in: hostView)
    }
    
    private func handleTaskDragEnded(_ btn: TaskButton, cancelled: Bool) {
        insertionIndicatorView.isHidden = true
        btn.alphaValue = 1.0
        btn.layer?.zPosition = 0
        
        guard let session = activeDragSession, let delegate = delegate else {
            delegate?.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        activeDragSession = nil
        
        if cancelled {
            btn.frame = session.initialFrame
            delegate.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        
        let initialIndex: Int
        switch session.target {
        case let .task(draggedBtn, idx):
            guard draggedBtn === btn else {
                delegate.dragCoordinatorRequiresLayoutUpdate()
                return
            }
            initialIndex = idx
        case .pinned:
            delegate.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        
        let targetSlot = session.currentTargetSlot
        let destinationIndex = (initialIndex < targetSlot) ? (targetSlot - 1) : targetSlot
        
        if initialIndex != destinationIndex && initialIndex >= 0 && initialIndex < delegate.taskButtons.count && destinationIndex >= 0 && destinationIndex < delegate.taskButtons.count {
            delegate.dragCoordinatorDidCommitTaskReorder(from: initialIndex, to: destinationIndex)
        }
        delegate.dragCoordinatorRequiresLayoutUpdate()
    }
    
    private func showTaskInsertionIndicator(forSlot slot: Int, in hostView: NSView) {
        guard let delegate = delegate else { return }
        let params = delegate.currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        if let indX = plan.taskInsertionIndicatorX(forSlot: slot, buttonSpacing: CGFloat(delegate.buttonSpacing)) {
            let indicatorW: CGFloat = TaskbarConstants.Drag.insertionIndicatorWidth
            let indicatorH = max(TaskbarConstants.Drag.insertionIndicatorMinHeight, hostView.bounds.height - TaskbarConstants.Drag.insertionIndicatorVerticalInset)
            let indicatorY = (hostView.bounds.height - indicatorH) / 2.0
            insertionIndicatorView.frame = NSRect(x: round(indX - (indicatorW / 2.0)), y: indicatorY, width: indicatorW, height: indicatorH)
            insertionIndicatorView.isHidden = false
        } else {
            insertionIndicatorView.isHidden = true
        }
    }
    
    // MARK: - Pinned Button Drag Configuration
    
    func configurePinnedButtonDrag(_ btn: PinnedButton) {
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
        guard let delegate = delegate, let hostView = hostView else { return }
        delegate.dragCoordinatorDidRequestPopupDismissal()
        
        guard let initialIndex = delegate.pinnedButtons.firstIndex(where: { $0 === btn }) else { return }
        let startX = btn.window?.mouseLocationOutsideOfEventStream.x ?? btn.frame.midX
        activeDragSession = DragSession(
            target: .pinned(button: btn, initialIndex: initialIndex),
            currentTargetSlot: initialIndex,
            initialFrame: btn.frame,
            startMouseWindowX: startX
        )
        btn.alphaValue = TaskbarConstants.Drag.draggedButtonAlpha
        btn.layer?.zPosition = TaskbarConstants.Drag.draggedButtonZPosition
        showPinnedInsertionIndicator(forSlot: initialIndex, in: hostView)
    }
    
    private func handlePinnedDragged(_ btn: PinnedButton, currentWindowLocation: NSPoint) {
        guard let session = activeDragSession, let delegate = delegate, let hostView = hostView else { return }
        let deltaX = currentWindowLocation.x - session.startMouseWindowX
        var draggedFrame = session.initialFrame
        draggedFrame.origin.x += deltaX
        btn.frame = draggedFrame
        
        let localPoint = hostView.convert(currentWindowLocation, from: nil)
        let params = delegate.currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        let slot = plan.pinnedInsertionSlot(atX: localPoint.x)
        activeDragSession?.currentTargetSlot = slot
        showPinnedInsertionIndicator(forSlot: slot, in: hostView)
    }
    
    private func handlePinnedDragEnded(_ btn: PinnedButton, cancelled: Bool) {
        insertionIndicatorView.isHidden = true
        btn.alphaValue = 1.0
        btn.layer?.zPosition = 0
        
        guard let session = activeDragSession, let delegate = delegate else {
            delegate?.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        activeDragSession = nil
        
        if cancelled {
            btn.frame = session.initialFrame
            delegate.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        
        let initialIndex: Int
        switch session.target {
        case let .pinned(draggedBtn, idx):
            guard draggedBtn === btn else {
                delegate.dragCoordinatorRequiresLayoutUpdate()
                return
            }
            initialIndex = idx
        case .task:
            delegate.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        
        let targetSlot = session.currentTargetSlot
        let destinationIndex = (initialIndex < targetSlot) ? (targetSlot - 1) : targetSlot
        
        if initialIndex != destinationIndex && initialIndex >= 0 && initialIndex < delegate.currentPinnedApps.count && destinationIndex >= 0 && destinationIndex < delegate.currentPinnedApps.count {
            var updated = delegate.currentPinnedApps
            let moved = updated.remove(at: initialIndex)
            updated.insert(moved, at: destinationIndex)
            delegate.dragCoordinatorDidCommitPinnedReorder(from: initialIndex, to: destinationIndex, updatedPinnedApps: updated)
        }
        delegate.dragCoordinatorRequiresLayoutUpdate()
    }
    
    private func showPinnedInsertionIndicator(forSlot slot: Int, in hostView: NSView) {
        guard let delegate = delegate else { return }
        let params = delegate.currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        if let indX = plan.pinnedInsertionIndicatorX(forSlot: slot, pinnedSpacing: CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing)) {
            let indicatorW: CGFloat = TaskbarConstants.Drag.insertionIndicatorWidth
            let indicatorH = max(TaskbarConstants.Drag.insertionIndicatorMinHeight, hostView.bounds.height - TaskbarConstants.Drag.insertionIndicatorVerticalInset)
            let indicatorY = (hostView.bounds.height - indicatorH) / 2.0
            insertionIndicatorView.frame = NSRect(x: round(indX - (indicatorW / 2.0)), y: indicatorY, width: indicatorW, height: indicatorH)
            insertionIndicatorView.isHidden = false
        } else {
            insertionIndicatorView.isHidden = true
        }
    }
}
