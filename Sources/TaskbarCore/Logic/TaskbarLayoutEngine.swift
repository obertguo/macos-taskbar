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
    
    /// Primary dimension available along the taskbar's main layout axis (width for horizontal, height for vertical).
    public var primaryDimension: Double {
        edge.isHorizontal ? Double(containerSize.width) : Double(containerSize.height)
    }
    
    /// Cross dimension perpendicular to the taskbar's main layout axis (height for horizontal, width for vertical).
    public var crossDimension: Double {
        edge.isHorizontal ? Double(containerSize.height) : Double(containerSize.width)
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
    
    /// Identifies the task button slot index at the specified coordinate along the primary axis.
    public func slotIndex(forPosition position: CGFloat, edge: TaskbarEdge = .bottom) -> Int? {
        let isHorizontal = edge.isHorizontal
        for (index, frame) in taskButtonFrames.prefix(visibleTaskCount).enumerated() {
            let (minCoord, maxCoord) = isHorizontal ? (frame.minX, frame.maxX) : (frame.minY, frame.maxY)
            if position >= minCoord && position <= maxCoord {
                return index
            }
        }
        return nil
    }
    
    /// Backward-compatible helper for horizontal drag-and-drop hit testing.
    public func slotIndex(atX x: CGFloat) -> Int? {
        slotIndex(forPosition: x, edge: .bottom)
    }
    
    /// Identifies the insertion slot index (0...visibleTaskCount) for a dragged task button at position along the primary axis.
    public func taskInsertionSlot(forPosition position: CGFloat, edge: TaskbarEdge = .bottom) -> Int {
        let isHorizontal = edge.isHorizontal
        let visibleFrames = Array(taskButtonFrames.prefix(visibleTaskCount))
        guard !visibleFrames.isEmpty else { return 0 }
        
        for (index, frame) in visibleFrames.enumerated() {
            let midCoord = isHorizontal ? frame.midX : frame.midY
            if position < midCoord {
                return index
            }
        }
        return visibleFrames.count
    }
    
    /// Backward-compatible helper for task insertion slot along horizontal axis X.
    public func taskInsertionSlot(atX x: CGFloat) -> Int {
        taskInsertionSlot(forPosition: x, edge: .bottom)
    }
    
    /// Identifies the insertion slot index (0...pinnedItemCount) for a dragged pinned button at position along the primary axis.
    public func pinnedInsertionSlot(forPosition position: CGFloat, edge: TaskbarEdge = .bottom) -> Int {
        let isHorizontal = edge.isHorizontal
        guard !pinnedButtonFrames.isEmpty else { return 0 }
        
        for (index, frame) in pinnedButtonFrames.enumerated() {
            let midCoord = isHorizontal ? frame.midX : frame.midY
            if position < midCoord {
                return index
            }
        }
        return pinnedButtonFrames.count
    }
    
    /// Backward-compatible helper for pinned insertion slot along horizontal axis X.
    public func pinnedInsertionSlot(atX x: CGFloat) -> Int {
        pinnedInsertionSlot(forPosition: x, edge: .bottom)
    }
    
    /// Computes the primary axis coordinate for rendering the insertion indicator bar in the task area.
    public func taskInsertionIndicatorPosition(
        forSlot slot: Int,
        buttonSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.defaultButtonSpacing),
        edge: TaskbarEdge = .bottom
    ) -> CGFloat? {
        let visibleFrames = Array(taskButtonFrames.prefix(visibleTaskCount))
        guard !visibleFrames.isEmpty else { return nil }
        let clampedSlot = max(0, min(slot, visibleFrames.count))
        let isHorizontal = edge.isHorizontal
        
        if clampedSlot == 0 {
            let minCoord = isHorizontal ? visibleFrames[0].minX : visibleFrames[0].minY
            return minCoord - (buttonSpacing / 2.0)
        } else if clampedSlot == visibleFrames.count {
            let maxCoord = isHorizontal ? visibleFrames[visibleFrames.count - 1].maxX : visibleFrames[visibleFrames.count - 1].maxY
            return maxCoord + (buttonSpacing / 2.0)
        } else {
            let prevMax = isHorizontal ? visibleFrames[clampedSlot - 1].maxX : visibleFrames[clampedSlot - 1].maxY
            let nextMin = isHorizontal ? visibleFrames[clampedSlot].minX : visibleFrames[clampedSlot].minY
            return (prevMax + nextMin) / 2.0
        }
    }
    
    /// Backward-compatible helper for horizontal center X coordinate of the task insertion indicator.
    public func taskInsertionIndicatorX(
        forSlot slot: Int,
        buttonSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.defaultButtonSpacing)
    ) -> CGFloat? {
        taskInsertionIndicatorPosition(forSlot: slot, buttonSpacing: buttonSpacing, edge: .bottom)
    }
    
    /// Computes the primary axis coordinate for rendering the insertion indicator bar in the pinned area.
    public func pinnedInsertionIndicatorPosition(
        forSlot slot: Int,
        pinnedSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing),
        edge: TaskbarEdge = .bottom
    ) -> CGFloat? {
        guard !pinnedButtonFrames.isEmpty else { return nil }
        let clampedSlot = max(0, min(slot, pinnedButtonFrames.count))
        let isHorizontal = edge.isHorizontal
        
        if clampedSlot == 0 {
            let minCoord = isHorizontal ? pinnedButtonFrames[0].minX : pinnedButtonFrames[0].minY
            return minCoord - (pinnedSpacing / 2.0)
        } else if clampedSlot == pinnedButtonFrames.count {
            let maxCoord = isHorizontal ? pinnedButtonFrames[pinnedButtonFrames.count - 1].maxX : pinnedButtonFrames[pinnedButtonFrames.count - 1].maxY
            return maxCoord + (pinnedSpacing / 2.0)
        } else {
            let prevMax = isHorizontal ? pinnedButtonFrames[clampedSlot - 1].maxX : pinnedButtonFrames[clampedSlot - 1].maxY
            let nextMin = isHorizontal ? pinnedButtonFrames[clampedSlot].minX : pinnedButtonFrames[clampedSlot].minY
            return (prevMax + nextMin) / 2.0
        }
    }
    
    /// Backward-compatible helper for horizontal center X coordinate of the pinned insertion indicator.
    public func pinnedInsertionIndicatorX(
        forSlot slot: Int,
        pinnedSpacing: CGFloat = CGFloat(TaskbarConstants.Layout.pinnedButtonSpacing)
    ) -> CGFloat? {
        pinnedInsertionIndicatorPosition(forSlot: slot, pinnedSpacing: pinnedSpacing, edge: .bottom)
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
    
    /// Computes the complete geometry layout plan for all interactive components on the taskbar.
    public static func computeLayout(params: TaskbarLayoutParameters) -> TaskbarLayoutPlan {
        let isHorizontal = params.edge.isHorizontal
        let padCross = params.verticalPadding
        let crossDimension = CGFloat(params.crossDimension)
        let primaryDimension = CGFloat(params.primaryDimension)
        let btnThickness = max(params.minimumButtonHeight, crossDimension - (padCross * 2.0))
        
        func makeFrame(primary: CGFloat, length: CGFloat) -> CGRect {
            if isHorizontal {
                return CGRect(x: primary, y: padCross, width: length, height: btnThickness)
            } else {
                return CGRect(x: padCross, y: primary, width: btnThickness, height: length)
            }
        }
        
        let startBtnFrame = makeFrame(
            primary: params.startButtonLeadingMargin,
            length: params.startButtonWidth
        )
        
        var currentPrimary = params.startButtonLeadingMargin + params.startButtonWidth + params.startButtonTrailingMargin
        
        var pinnedFrames: [CGRect] = []
        pinnedFrames.reserveCapacity(params.pinnedItemCount)
        for _ in 0..<params.pinnedItemCount {
            let frame = makeFrame(primary: currentPrimary, length: btnThickness)
            pinnedFrames.append(frame)
            currentPrimary += btnThickness + params.pinnedButtonSpacing
        }
        
        if params.pinnedItemCount > 0 {
            currentPrimary += (params.pinnedSectionTrailingMargin - params.pinnedButtonSpacing)
        }
        
        let startPrimary = currentPrimary
        let totalAvailablePrimary = max(0.0, primaryDimension - startPrimary - params.taskbarTrailingMargin)
        
        var layout = ButtonLayout.computeLayout(
            availableWidth: Double(totalAvailablePrimary),
            itemCount: params.taskItemCount,
            maxButtonWidth: params.maxButtonWidth,
            minButtonWidth: params.minButtonWidth,
            spacing: params.buttonSpacing,
            titleVisibilityThreshold: params.titleVisibilityThreshold
        )
        
        var overflowFrame: CGRect? = nil
        let overflowBtnW = params.overflowButtonWidth
        
        if layout.hasOverflow {
            let netAvailablePrimary = max(0.0, totalAvailablePrimary - overflowBtnW - CGFloat(params.buttonSpacing))
            layout = ButtonLayout.computeLayout(
                availableWidth: Double(netAvailablePrimary),
                itemCount: params.taskItemCount,
                maxButtonWidth: params.maxButtonWidth,
                minButtonWidth: params.minButtonWidth,
                spacing: params.buttonSpacing,
                titleVisibilityThreshold: params.titleVisibilityThreshold
            )
            
            overflowFrame = makeFrame(
                primary: primaryDimension - overflowBtnW - params.overflowButtonTrailingMargin,
                length: overflowBtnW
            )
        }
        
        var taskFrames: [CGRect] = []
        taskFrames.reserveCapacity(params.taskItemCount)
        var taskBtnPrimary = startPrimary
        
        for index in 0..<params.taskItemCount {
            if index < layout.visibleCount {
                let frame = makeFrame(
                    primary: taskBtnPrimary,
                    length: CGFloat(layout.buttonWidth)
                )
                taskFrames.append(frame)
                taskBtnPrimary += CGFloat(layout.buttonWidth) + CGFloat(params.buttonSpacing)
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
