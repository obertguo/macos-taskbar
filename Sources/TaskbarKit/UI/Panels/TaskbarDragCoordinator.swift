// Sources/TaskbarKit/UI/Panels/TaskbarDragCoordinator.swift

import AppKit
import TaskbarCore

/// Delegate protocol allowing `TaskbarDragCoordinator` to communicate reorder commits
/// and layout requests back to the owning `TaskbarView`.
@MainActor
internal protocol TaskbarDragCoordinatorDelegate: AnyObject {
    var taskButtons: [TaskButton] { get }
    var pinnedButtons: [PinnedButton] { get }
    var currentPinnedApps: [PinnedApp] { get }
    var buttonSpacing: Double { get }
    
    func currentLayoutParams() -> TaskbarLayoutParameters
    func moveTaskButton(from fromIndex: Int, to toIndex: Int)
    func movePinnedButton(from fromIndex: Int, to toIndex: Int, updatedPinnedApps: [PinnedApp])
    func dragCoordinatorDidEndDrag()
    func dragCoordinatorRequiresLayoutUpdate()
    func dragCoordinatorDidRequestPopupDismissal()
}

/// Coordinates drag-and-drop slot reordering for task and pinned buttons,
/// managing drag session states, insertion indicator rendering, and drop commits.
@MainActor
internal final class TaskbarDragCoordinator {
    internal enum DragKind: Sendable {
        case task
        case pinned
    }
    
    internal struct DragSession {
        let kind: DragKind
        let button: NSView
        let initialIndex: Int
        var currentTargetSlot: Int
        let initialFrame: NSRect
        let startMouseWindowX: CGFloat
    }
    
    internal private(set) var activeDragSession: DragSession?
    internal let insertionIndicatorView = NSView()
    
    internal var isDragging: Bool {
        activeDragSession != nil
    }
    
    internal func isDragging(button: NSView) -> Bool {
        guard let session = activeDragSession else { return false }
        return session.button === button
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
    
    // MARK: - Drag Configuration
    
    func configureTaskButtonDrag(_ btn: TaskButton) {
        btn.onDragStarted = { [weak self, weak btn] in
            guard let self = self, let btn = btn else { return }
            guard let initialIndex = self.delegate?.taskButtons.firstIndex(where: { $0 === btn }) else { return }
            self.handleDragStarted(kind: .task, button: btn, initialIndex: initialIndex)
        }
        btn.onDragged = { [weak self, weak btn] loc in
            guard let self = self, let btn = btn else { return }
            self.handleDragged(kind: .task, button: btn, currentWindowLocation: loc)
        }
        btn.onDragEnded = { [weak self, weak btn] cancelled in
            guard let self = self, let btn = btn else { return }
            self.handleDragEnded(kind: .task, button: btn, cancelled: cancelled)
        }
    }
    
    func configurePinnedButtonDrag(_ btn: PinnedButton) {
        btn.onDragStarted = { [weak self, weak btn] in
            guard let self = self, let btn = btn else { return }
            guard let initialIndex = self.delegate?.pinnedButtons.firstIndex(where: { $0 === btn }) else { return }
            self.handleDragStarted(kind: .pinned, button: btn, initialIndex: initialIndex)
        }
        btn.onDragged = { [weak self, weak btn] loc in
            guard let self = self, let btn = btn else { return }
            self.handleDragged(kind: .pinned, button: btn, currentWindowLocation: loc)
        }
        btn.onDragEnded = { [weak self, weak btn] cancelled in
            guard let self = self, let btn = btn else { return }
            self.handleDragEnded(kind: .pinned, button: btn, cancelled: cancelled)
        }
    }
    
    // MARK: - Shared Drag Handling
    
    private func handleDragStarted(kind: DragKind, button: NSView, initialIndex: Int) {
        guard let delegate = delegate, let hostView = hostView else { return }
        delegate.dragCoordinatorDidRequestPopupDismissal()
        
        let startX = button.window?.mouseLocationOutsideOfEventStream.x ?? button.frame.midX
        activeDragSession = DragSession(
            kind: kind,
            button: button,
            initialIndex: initialIndex,
            currentTargetSlot: initialIndex,
            initialFrame: button.frame,
            startMouseWindowX: startX
        )
        button.alphaValue = TaskbarConstants.Drag.draggedButtonAlpha
        button.layer?.zPosition = TaskbarConstants.Drag.draggedButtonZPosition
        
        let params = delegate.currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        showInsertionIndicator(kind: kind, plan: plan, slot: initialIndex, hostView: hostView)
    }
    
    private func handleDragged(kind: DragKind, button: NSView, currentWindowLocation: NSPoint) {
        guard let session = activeDragSession, let delegate = delegate, let hostView = hostView else { return }
        let deltaX = currentWindowLocation.x - session.startMouseWindowX
        var draggedFrame = session.initialFrame
        draggedFrame.origin.x += deltaX
        button.frame = draggedFrame
        
        let localPoint = hostView.convert(currentWindowLocation, from: nil)
        let params = delegate.currentLayoutParams()
        let plan = TaskbarLayoutEngine.computeLayout(params: params)
        
        let slot: Int
        switch kind {
        case .task:
            slot = plan.taskInsertionSlot(atX: localPoint.x)
        case .pinned:
            slot = plan.pinnedInsertionSlot(atX: localPoint.x)
        }
        
        activeDragSession?.currentTargetSlot = slot
        showInsertionIndicator(kind: kind, plan: plan, slot: slot, hostView: hostView)
    }
    
    private func handleDragEnded(kind: DragKind, button: NSView, cancelled: Bool) {
        insertionIndicatorView.isHidden = true
        button.alphaValue = 1.0
        button.layer?.zPosition = 0
        
        guard let session = activeDragSession, let delegate = delegate else {
            delegate?.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        activeDragSession = nil
        
        if cancelled {
            button.frame = session.initialFrame
            delegate.dragCoordinatorDidEndDrag()
            delegate.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        
        guard session.button === button, session.kind == kind else {
            delegate.dragCoordinatorDidEndDrag()
            delegate.dragCoordinatorRequiresLayoutUpdate()
            return
        }
        
        let initialIndex = session.initialIndex
        let targetSlot = session.currentTargetSlot
        let destinationIndex = (initialIndex < targetSlot) ? (targetSlot - 1) : targetSlot
        
        switch kind {
        case .task:
            if initialIndex != destinationIndex && initialIndex >= 0 && initialIndex < delegate.taskButtons.count && destinationIndex >= 0 && destinationIndex < delegate.taskButtons.count {
                delegate.moveTaskButton(from: initialIndex, to: destinationIndex)
            } else {
                delegate.dragCoordinatorDidEndDrag()
            }
        case .pinned:
            if initialIndex != destinationIndex && initialIndex >= 0 && initialIndex < delegate.currentPinnedApps.count && destinationIndex >= 0 && destinationIndex < delegate.currentPinnedApps.count {
                var updated = delegate.currentPinnedApps
                let moved = updated.remove(at: initialIndex)
                updated.insert(moved, at: destinationIndex)
                delegate.movePinnedButton(from: initialIndex, to: destinationIndex, updatedPinnedApps: updated)
            } else {
                delegate.dragCoordinatorDidEndDrag()
            }
        }
        delegate.dragCoordinatorRequiresLayoutUpdate()
    }
    
    private func showInsertionIndicator(
        kind: DragKind,
        plan: TaskbarLayoutPlan,
        slot: Int,
        hostView: NSView
    ) {
        guard let delegate = delegate else { return }
        let indX: CGFloat?
        switch kind {
        case .task:
            indX = plan.taskInsertionIndicatorX(forSlot: slot, buttonSpacing: CGFloat(delegate.buttonSpacing))
        case .pinned:
            indX = plan.pinnedInsertionIndicatorX(forSlot: slot, pinnedSpacing: CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing))
        }
        
        if let indX = indX {
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
