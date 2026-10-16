// Sources/TaskbarCore/Logic/TaskbarLayoutEngine.swift

import Foundation
import CoreGraphics

/// Immutable parameters passed to `TaskbarLayoutEngine` to calculate button geometry.
public struct TaskbarLayoutParameters: Equatable, Sendable {
    public let containerSize: CGSize
    public let startButtonWidth: CGFloat
    public let pinnedItemCount: Int
    public let taskItemCount: Int
    public let edge: TaskbarEdge
    public let minButtonWidth: Double
    public let maxButtonWidth: Double
    public let buttonSpacing: Double
    public let titleVisibilityThreshold: Double
    public let verticalPadding: CGFloat
    public let minimumButtonHeight: CGFloat
    public let startButtonLeadingMargin: CGFloat
    public let startButtonTrailingMargin: CGFloat
    public let pinnedButtonSpacing: CGFloat
    public let pinnedSectionTrailingMargin: CGFloat
    public let taskbarTrailingMargin: CGFloat
    public let overflowButtonWidth: CGFloat
    public let overflowButtonTrailingMargin: CGFloat
    
    /// Primary dimension available along the taskbar's main layout axis (horizontal in v0.3.0).
    public var primaryDimension: Double {
        Double(containerSize.width)
    }
    
    /// Cross dimension perpendicular to the taskbar's main layout axis (horizontal in v0.3.0).
    public var crossDimension: Double {
        Double(containerSize.height)
    }
    
    public init(
        containerSize: CGSize,
        startButtonWidth: CGFloat,
        pinnedItemCount: Int,
        taskItemCount: Int,
        edge: TaskbarEdge = .bottom,
        minButtonWidth: Double = TaskbarConstants.Layout.defaultMinButtonWidth,
        maxButtonWidth: Double = TaskbarConstants.Layout.defaultMaxButtonWidth,
        buttonSpacing: Double = TaskbarConstants.Layout.defaultButtonSpacing,
        titleVisibilityThreshold: Double = TaskbarConstants.Layout.defaultTitleVisibilityThreshold,
        verticalPadding: CGFloat = TaskbarConstants.Layout.taskbarVerticalPadding,
        minimumButtonHeight: CGFloat = TaskbarConstants.Layout.minimumButtonHeight,
        startButtonLeadingMargin: CGFloat = TaskbarConstants.Layout.startButtonLeadingMargin,
        startButtonTrailingMargin: CGFloat = TaskbarConstants.Layout.startButtonTrailingMargin,
        pinnedButtonSpacing: CGFloat = TaskbarConstants.Layout.pinnedButtonSpacing,
        pinnedSectionTrailingMargin: CGFloat = TaskbarConstants.Layout.pinnedSectionTrailingMargin,
        taskbarTrailingMargin: CGFloat = TaskbarConstants.Layout.taskbarTrailingMargin,
        overflowButtonWidth: CGFloat = TaskbarConstants.Layout.overflowButtonWidth,
        overflowButtonTrailingMargin: CGFloat = TaskbarConstants.Layout.overflowButtonTrailingMargin
    ) {
        self.containerSize = containerSize
        self.startButtonWidth = startButtonWidth
        self.pinnedItemCount = max(0, pinnedItemCount)
        self.taskItemCount = max(0, taskItemCount)
        self.edge = edge
        self.minButtonWidth = minButtonWidth
        self.maxButtonWidth = maxButtonWidth
        self.buttonSpacing = buttonSpacing
        self.titleVisibilityThreshold = titleVisibilityThreshold
        self.verticalPadding = verticalPadding
        self.minimumButtonHeight = minimumButtonHeight
        self.startButtonLeadingMargin = startButtonLeadingMargin
        self.startButtonTrailingMargin = startButtonTrailingMargin
        self.pinnedButtonSpacing = pinnedButtonSpacing
        self.pinnedSectionTrailingMargin = pinnedSectionTrailingMargin
        self.taskbarTrailingMargin = taskbarTrailingMargin
        self.overflowButtonWidth = overflowButtonWidth
        self.overflowButtonTrailingMargin = overflowButtonTrailingMargin
    }
}

/// Fully calculated layout geometry plan returned by `TaskbarLayoutEngine`.
public struct TaskbarLayoutPlan: Equatable, Sendable {
    public let buttonHeight: CGFloat
    public let startButtonFrame: CGRect
    public let pinnedButtonFrames: [CGRect]
    public let taskButtonFrames: [CGRect]
    public let overflowButtonFrame: CGRect?
    public let visibleTaskCount: Int
    public let showTitle: Bool
    public let hasOverflow: Bool
    public let taskButtonWidth: Double
    
    public init(
        buttonHeight: CGFloat,
        startButtonFrame: CGRect,
        pinnedButtonFrames: [CGRect],
        taskButtonFrames: [CGRect],
        overflowButtonFrame: CGRect?,
        visibleTaskCount: Int,
        showTitle: Bool,
        hasOverflow: Bool,
        taskButtonWidth: Double
    ) {
        self.buttonHeight = buttonHeight
        self.startButtonFrame = startButtonFrame
        self.pinnedButtonFrames = pinnedButtonFrames
        self.taskButtonFrames = taskButtonFrames
        self.overflowButtonFrame = overflowButtonFrame
        self.visibleTaskCount = visibleTaskCount
        self.showTitle = showTitle
        self.hasOverflow = hasOverflow
        self.taskButtonWidth = taskButtonWidth
    }
    
    /// Identifies the task button slot index at the specified coordinate along the horizontal axis.
    public func slotIndex(atX x: CGFloat) -> Int? {
        for (index, frame) in taskButtonFrames.prefix(visibleTaskCount).enumerated() {
            if x >= frame.minX && x <= frame.maxX {
                return index
            }
        }
        return nil
    }
    
    /// Identifies the task button slot index at the specified coordinate along the primary axis.
    public func slotIndex(forPosition position: CGFloat, edge: TaskbarEdge = .bottom) -> Int? {
        slotIndex(atX: position)
    }
    
    /// Identifies the insertion slot index (0...visibleTaskCount) for a dragged task button at position along the horizontal axis.
    public func taskInsertionSlot(atX x: CGFloat) -> Int {
        let visibleFrames = Array(taskButtonFrames.prefix(visibleTaskCount))
        guard !visibleFrames.isEmpty else { return 0 }
        
        for (index, frame) in visibleFrames.enumerated() {
            if x < frame.midX {
                return index
            }
        }
        return visibleFrames.count
    }
    
    /// Identifies the insertion slot index (0...visibleTaskCount) for a dragged task button at position along the primary axis.
    public func taskInsertionSlot(forPosition position: CGFloat, edge: TaskbarEdge = .bottom) -> Int {
        taskInsertionSlot(atX: position)
    }
    
    /// Identifies the insertion slot index (0...pinnedItemCount) for a dragged pinned button at position along the horizontal axis.
    public func pinnedInsertionSlot(atX x: CGFloat) -> Int {
        guard !pinnedButtonFrames.isEmpty else { return 0 }
        
        for (index, frame) in pinnedButtonFrames.enumerated() {
            if x < frame.midX {
                return index
            }
        }
        return pinnedButtonFrames.count
    }
    
    /// Identifies the insertion slot index (0...pinnedItemCount) for a dragged pinned button at position along the primary axis.
    public func pinnedInsertionSlot(forPosition position: CGFloat, edge: TaskbarEdge = .bottom) -> Int {
        pinnedInsertionSlot(atX: position)
    }
    
    /// Computes the horizontal center X coordinate of the task insertion indicator.
    public func taskInsertionIndicatorX(
        forSlot slot: Int,
        buttonSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.defaultButtonSpacing)
    ) -> CGFloat? {
        let visibleFrames = Array(taskButtonFrames.prefix(visibleTaskCount))
        guard !visibleFrames.isEmpty else { return nil }
        let clampedSlot = max(0, min(slot, visibleFrames.count))
        
        if clampedSlot == 0 {
            return visibleFrames[0].minX - (buttonSpacing / 2.0)
        } else if clampedSlot == visibleFrames.count {
            return visibleFrames[visibleFrames.count - 1].maxX + (buttonSpacing / 2.0)
        } else {
            let prevMax = visibleFrames[clampedSlot - 1].maxX
            let nextMin = visibleFrames[clampedSlot].minX
            return (prevMax + nextMin) / 2.0
        }
    }
    
    /// Computes the primary axis coordinate for rendering the insertion indicator bar in the task area.
    public func taskInsertionIndicatorPosition(
        forSlot slot: Int,
        buttonSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.defaultButtonSpacing),
        edge: TaskbarEdge = .bottom
    ) -> CGFloat? {
        taskInsertionIndicatorX(forSlot: slot, buttonSpacing: buttonSpacing)
    }
    
    /// Computes the horizontal center X coordinate of the pinned insertion indicator.
    public func pinnedInsertionIndicatorX(
        forSlot slot: Int,
        pinnedSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing)
    ) -> CGFloat? {
        guard !pinnedButtonFrames.isEmpty else { return nil }
        let clampedSlot = max(0, min(slot, pinnedButtonFrames.count))
        
        if clampedSlot == 0 {
            return pinnedButtonFrames[0].minX - (pinnedSpacing / 2.0)
        } else if clampedSlot == pinnedButtonFrames.count {
            return pinnedButtonFrames[pinnedButtonFrames.count - 1].maxX + (pinnedSpacing / 2.0)
        } else {
            let prevMax = pinnedButtonFrames[clampedSlot - 1].maxX
            let nextMin = pinnedButtonFrames[clampedSlot].minX
            return (prevMax + nextMin) / 2.0
        }
    }
    
    /// Computes the primary axis coordinate for rendering the insertion indicator bar in the pinned area.
    public func pinnedInsertionIndicatorPosition(
        forSlot slot: Int,
        pinnedSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing),
        edge: TaskbarEdge = .bottom
    ) -> CGFloat? {
        pinnedInsertionIndicatorX(forSlot: slot, pinnedSpacing: pinnedSpacing)
    }
}

/// Pure Swift layout calculation engine for the Taskbar.
public enum TaskbarLayoutEngine {
    
    /// Static helper for slot hit testing across any edge.
    public static func slotIndex(
        forPosition position: Double,
        edge: TaskbarEdge = .bottom,
        in plan: TaskbarLayoutPlan
    ) -> Int? {
        plan.slotIndex(forPosition: CGFloat(position), edge: edge)
    }
    
    /// Computes the total available primary-axis length allocated for the task buttons area.
    public static func availableTaskAreaLength(params: TaskbarLayoutParameters) -> CGFloat {
        let primaryDimension = CGFloat(params.primaryDimension)
        let startPrimary = params.startButtonLeadingMargin + params.startButtonWidth + params.startButtonTrailingMargin
        let btnThickness = max(params.minimumButtonHeight, CGFloat(params.crossDimension) - (params.verticalPadding * 2.0))
        
        var currentPrimary = startPrimary
        if params.pinnedItemCount > 0 {
            currentPrimary += CGFloat(params.pinnedItemCount) * btnThickness + CGFloat(params.pinnedItemCount - 1) * params.pinnedButtonSpacing + params.pinnedSectionTrailingMargin
        }
        return max(0.0, primaryDimension - currentPrimary - params.taskbarTrailingMargin)
    }
    
    /// Computes the complete geometry layout plan for all interactive components on the taskbar.
    public static func computeLayout(params: TaskbarLayoutParameters) -> TaskbarLayoutPlan {
        let padCross = params.verticalPadding
        let crossDimension = CGFloat(params.crossDimension)
        let primaryDimension = CGFloat(params.primaryDimension)
        let btnThickness = max(params.minimumButtonHeight, crossDimension - (padCross * 2.0))
        
        func makeFrame(x: CGFloat, length: CGFloat) -> CGRect {
            CGRect(x: x, y: padCross, width: length, height: btnThickness)
        }
        
        let startBtnFrame = makeFrame(
            x: params.startButtonLeadingMargin,
            length: params.startButtonWidth
        )
        
        var currentX = params.startButtonLeadingMargin + params.startButtonWidth + params.startButtonTrailingMargin
        
        var pinnedFrames: [CGRect] = []
        pinnedFrames.reserveCapacity(params.pinnedItemCount)
        for _ in 0..<params.pinnedItemCount {
            let frame = makeFrame(x: currentX, length: btnThickness)
            pinnedFrames.append(frame)
            currentX += btnThickness + params.pinnedButtonSpacing
        }
        
        if params.pinnedItemCount > 0 {
            currentX += (params.pinnedSectionTrailingMargin - params.pinnedButtonSpacing)
        }
        
        let startX = currentX
        let totalAvailableX = max(0.0, primaryDimension - startX - params.taskbarTrailingMargin)
        
        var layout = ButtonLayout.computeLayout(
            availableWidth: Double(totalAvailableX),
            itemCount: params.taskItemCount,
            maxButtonWidth: params.maxButtonWidth,
            minButtonWidth: params.minButtonWidth,
            spacing: params.buttonSpacing,
            titleVisibilityThreshold: params.titleVisibilityThreshold
        )
        
        var overflowFrame: CGRect? = nil
        let overflowBtnW = params.overflowButtonWidth
        
        if layout.hasOverflow {
            let netAvailableX = max(0.0, totalAvailableX - overflowBtnW - CGFloat(params.buttonSpacing))
            layout = ButtonLayout.computeLayout(
                availableWidth: Double(netAvailableX),
                itemCount: params.taskItemCount,
                maxButtonWidth: params.maxButtonWidth,
                minButtonWidth: params.minButtonWidth,
                spacing: params.buttonSpacing,
                titleVisibilityThreshold: params.titleVisibilityThreshold
            )
            
            overflowFrame = makeFrame(
                x: primaryDimension - overflowBtnW - params.overflowButtonTrailingMargin,
                length: overflowBtnW
            )
        }
        
        var taskFrames: [CGRect] = []
        taskFrames.reserveCapacity(params.taskItemCount)
        var taskBtnX = startX
        
        for index in 0..<params.taskItemCount {
            if index < layout.visibleCount {
                let frame = makeFrame(
                    x: taskBtnX,
                    length: CGFloat(layout.buttonWidth)
                )
                taskFrames.append(frame)
                taskBtnX += CGFloat(layout.buttonWidth) + CGFloat(params.buttonSpacing)
            } else {
                taskFrames.append(.zero)
            }
        }
        
        return TaskbarLayoutPlan(
            buttonHeight: btnThickness,
            startButtonFrame: startBtnFrame,
            pinnedButtonFrames: pinnedFrames,
            taskButtonFrames: taskFrames,
            overflowButtonFrame: overflowFrame,
            visibleTaskCount: layout.visibleCount,
            showTitle: layout.showTitle,
            hasOverflow: layout.hasOverflow,
            taskButtonWidth: layout.buttonWidth
        )
    }
}
