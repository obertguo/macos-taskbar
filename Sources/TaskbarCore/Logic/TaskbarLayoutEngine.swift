// Sources/TaskbarCore/Logic/TaskbarLayoutEngine.swift

import Foundation
import CoreGraphics

/// Immutable parameters passed to `TaskbarLayoutEngine` to calculate button geometry.
public struct TaskbarLayoutParameters: Equatable, Sendable {
    public let containerSize: CGSize
    public let startButtonWidth: CGFloat
    public let pinnedItemCount: Int
    public let taskItemCount: Int
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
    
    public init(
        containerSize: CGSize,
        startButtonWidth: CGFloat,
        pinnedItemCount: Int,
        taskItemCount: Int,
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
    
    /// Helper for drag-and-drop hit testing: identifies the task button slot index at horizontal coordinate X.
    public func slotIndex(atX x: CGFloat) -> Int? {
        for (index, frame) in taskButtonFrames.prefix(visibleTaskCount).enumerated() {
            if x >= frame.minX && x <= frame.maxX {
                return index
            }
        }
        return nil
    }
}

/// Pure Swift layout calculation engine for the Taskbar.
public enum TaskbarLayoutEngine {
    /// Computes the complete geometry layout plan for all interactive components on the taskbar.
    public static func computeLayout(params: TaskbarLayoutParameters) -> TaskbarLayoutPlan {
        let padY = params.verticalPadding
        let btnH = max(params.minimumButtonHeight, params.containerSize.height - (padY * 2.0))
        
        let startBtnFrame = CGRect(
            x: params.startButtonLeadingMargin,
            y: padY,
            width: params.startButtonWidth,
            height: btnH
        )
        
        var currentX = startBtnFrame.maxX + params.startButtonTrailingMargin
        
        var pinnedFrames: [CGRect] = []
        pinnedFrames.reserveCapacity(params.pinnedItemCount)
        for _ in 0..<params.pinnedItemCount {
            let frame = CGRect(
                x: currentX,
                y: padY,
                width: btnH,
                height: btnH
            )
            pinnedFrames.append(frame)
            currentX += btnH + params.pinnedButtonSpacing
        }
        
        if params.pinnedItemCount > 0 {
            currentX += (params.pinnedSectionTrailingMargin - params.pinnedButtonSpacing)
        }
        
        let startX = currentX
        let totalAvailableW = max(0.0, params.containerSize.width - startX - params.taskbarTrailingMargin)
        
        var layout = ButtonLayout.computeLayout(
            availableWidth: Double(totalAvailableW),
            itemCount: params.taskItemCount,
            maxButtonWidth: params.maxButtonWidth,
            minButtonWidth: params.minButtonWidth,
            spacing: params.buttonSpacing,
            titleVisibilityThreshold: params.titleVisibilityThreshold
        )
        
        var overflowFrame: CGRect? = nil
        let overflowBtnW = params.overflowButtonWidth
        
        if layout.hasOverflow {
            let netAvailableW = max(0.0, totalAvailableW - overflowBtnW - CGFloat(params.buttonSpacing))
            layout = ButtonLayout.computeLayout(
                availableWidth: Double(netAvailableW),
                itemCount: params.taskItemCount,
                maxButtonWidth: params.maxButtonWidth,
                minButtonWidth: params.minButtonWidth,
                spacing: params.buttonSpacing,
                titleVisibilityThreshold: params.titleVisibilityThreshold
            )
            
            overflowFrame = CGRect(
                x: params.containerSize.width - overflowBtnW - params.overflowButtonTrailingMargin,
                y: padY,
                width: overflowBtnW,
                height: btnH
            )
        }
        
        var taskFrames: [CGRect] = []
        taskFrames.reserveCapacity(params.taskItemCount)
        var taskBtnX = startX
        
        for index in 0..<params.taskItemCount {
            if index < layout.visibleCount {
                let frame = CGRect(
                    x: taskBtnX,
                    y: padY,
                    width: CGFloat(layout.buttonWidth),
                    height: btnH
                )
                taskFrames.append(frame)
                taskBtnX += CGFloat(layout.buttonWidth) + CGFloat(params.buttonSpacing)
            } else {
                taskFrames.append(.zero)
            }
        }
        
        return TaskbarLayoutPlan(
            buttonHeight: btnH,
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
