// Sources/TaskbarCore/Logic/WorkAreaMath.swift

import Foundation
import CoreGraphics

public enum WorkAreaMath {
    /// Minimum allowed window height in points to prevent collapsing windows into unusable slices.
    public static let minimumWindowHeight: CGFloat = TaskbarConstants.WorkArea.minimumWindowHeight
    
    /// Overlap threshold in points to ignore sub-pixel or rounding differences.
    public static let overlapThreshold: CGFloat = TaskbarConstants.WorkArea.overlapTolerance
    
    /// Checks whether a window is considered vertically maximized or screen-filling (e.g. zoomed or split-tiled).
    public static func isVerticallyMaximized(
        _ windowFrame: CGRect,
        screenFrame: CGRect,
        taskbarHeight: CGFloat = CGFloat(TaskbarConstants.Layout.defaultBarHeight)
    ) -> Bool {
        guard screenFrame.height > 0 else { return false }
        
        // Window top starts in the upper portion of the screen (generous tolerance for notch, menu bar, and titlebar padding)
        let topTolerance = max(TaskbarConstants.WorkArea.screenTopToleranceBase, screenFrame.height * TaskbarConstants.WorkArea.screenTopToleranceRatio)
        let nearTop = windowFrame.minY <= screenFrame.minY + topTolerance
        
        // Window bottom extends into the taskbar reserved region
        let taskbarTopY = screenFrame.maxY - taskbarHeight
        let extendsIntoTaskbar = windowFrame.maxY > taskbarTopY + overlapThreshold
        
        // Window occupies a significant portion of screen height (e.g. >= 45% of screen)
        let isTall = windowFrame.height >= screenFrame.height * TaskbarConstants.WorkArea.screenHeightMaximizedRatio
        
        return nearTop && extendsIntoTaskbar && isTall
    }
    
    /// Checks whether a window is maximized or screen-filling along the relevant axis for the specified taskbar edge.
    public static func isMaximized(
        _ windowFrame: CGRect,
        screenFrame: CGRect,
        barDimension: Double,
        edge: TaskbarEdge
    ) -> Bool {
        guard screenFrame.width > 0 && screenFrame.height > 0 else { return false }
        let barDim = CGFloat(barDimension)
        
        switch edge {
        case .bottom:
            return isVerticallyMaximized(windowFrame, screenFrame: screenFrame, taskbarHeight: barDim)
            
        case .top:
            let topTolerance = max(TaskbarConstants.WorkArea.screenTopToleranceBase, screenFrame.height * TaskbarConstants.WorkArea.screenTopToleranceRatio)
            let taskbarBottomY = screenFrame.minY + barDim
            let extendsIntoTaskbar = windowFrame.minY < taskbarBottomY - overlapThreshold
            let nearBottom = windowFrame.maxY >= screenFrame.maxY - topTolerance
            let isTall = windowFrame.height >= screenFrame.height * TaskbarConstants.WorkArea.screenHeightMaximizedRatio
            return nearBottom && extendsIntoTaskbar && isTall
            
        case .left:
            let sideTolerance = max(TaskbarConstants.WorkArea.screenTopToleranceBase, screenFrame.width * TaskbarConstants.WorkArea.screenTopToleranceRatio)
            let taskbarRightX = screenFrame.minX + barDim
            let extendsIntoTaskbar = windowFrame.minX < taskbarRightX - overlapThreshold
            let nearRight = windowFrame.maxX >= screenFrame.maxX - sideTolerance
            let isWide = windowFrame.width >= screenFrame.width * TaskbarConstants.WorkArea.screenHeightMaximizedRatio
            return nearRight && extendsIntoTaskbar && isWide
            
        case .right:
            let sideTolerance = max(TaskbarConstants.WorkArea.screenTopToleranceBase, screenFrame.width * TaskbarConstants.WorkArea.screenTopToleranceRatio)
            let taskbarLeftX = screenFrame.maxX - barDim
            let extendsIntoTaskbar = windowFrame.maxX > taskbarLeftX + overlapThreshold
            let nearLeft = windowFrame.minX <= screenFrame.minX + sideTolerance
            let isWide = windowFrame.width >= screenFrame.width * TaskbarConstants.WorkArea.screenHeightMaximizedRatio
            return nearLeft && extendsIntoTaskbar && isWide
        }
    }
    
    /// Calculates the clamped frame for a window given screen bounds, taskbar dimension, and anchor edge.
    /// Both `windowFrame` and `screenBounds` must be in the same coordinate space (Quartz display coordinates).
    ///
    /// - Parameters:
    ///   - windowFrame: The window's current frame (x, y, width, height).
    ///   - screenBounds: The target screen's bounds (x, y, width, height).
    ///   - barDimension: The dimension reserved by the taskbar (height for top/bottom, width for left/right).
    ///   - edge: The screen edge where the taskbar is anchored. Defaults to `.bottom`.
    ///   - overlapThreshold: The tolerance threshold in points before clamping engages.
    ///   - allowNonMaximized: If `false`, only maximized/screen-filling windows are clamped. Defaults to `true`.
    /// - Returns: A new `CGRect` adjusted to avoid taskbar overlap, or `nil` if no adjustment is needed.
    public static func clampedFrame(
        windowFrame: CGRect,
        screenBounds: CGRect,
        barDimension: Double,
        edge: TaskbarEdge = .bottom,
        overlapThreshold: Double = TaskbarConstants.Clamping.subpixelOverlapThreshold,
        allowNonMaximized: Bool = true
    ) -> CGRect? {
        guard barDimension > 0 else { return nil }
        
        if !allowNonMaximized {
            guard isMaximized(windowFrame, screenFrame: screenBounds, barDimension: barDimension, edge: edge) else {
                return nil
            }
        }
        
        let threshold = CGFloat(overlapThreshold)
        let barDim = CGFloat(barDimension)
        
        switch edge {
        case .bottom:
            let taskbarTopY = screenBounds.maxY - barDim
            guard windowFrame.minY < taskbarTopY else { return nil }
            let overlap = windowFrame.maxY - taskbarTopY
            guard overlap > threshold else { return nil }
            let newHeight = windowFrame.height - overlap
            guard newHeight >= minimumWindowHeight else { return nil }
            guard abs(newHeight - windowFrame.height) >= TaskbarConstants.WorkArea.clampingRecursionGuardDelta else { return nil }
            return CGRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: windowFrame.width, height: newHeight)
            
        case .top:
            let taskbarBottomY = screenBounds.minY + barDim
            guard windowFrame.maxY > taskbarBottomY else { return nil }
            let overlap = taskbarBottomY - windowFrame.minY
            guard overlap > threshold else { return nil }
            let newHeight = windowFrame.height - overlap
            guard newHeight >= minimumWindowHeight else { return nil }
            guard abs(newHeight - windowFrame.height) >= TaskbarConstants.WorkArea.clampingRecursionGuardDelta else { return nil }
            return CGRect(x: windowFrame.origin.x, y: taskbarBottomY, width: windowFrame.width, height: newHeight)
            
        case .left:
            let taskbarRightX = screenBounds.minX + barDim
            guard windowFrame.maxX > taskbarRightX else { return nil }
            let overlap = taskbarRightX - windowFrame.minX
            guard overlap > threshold else { return nil }
            let newWidth = windowFrame.width - overlap
            guard newWidth >= TaskbarConstants.WorkArea.minimumWindowDimension else { return nil }
            guard abs(newWidth - windowFrame.width) >= TaskbarConstants.WorkArea.clampingRecursionGuardDelta else { return nil }
            return CGRect(x: taskbarRightX, y: windowFrame.origin.y, width: newWidth, height: windowFrame.height)
            
        case .right:
            let taskbarLeftX = screenBounds.maxX - barDim
            guard windowFrame.minX < taskbarLeftX else { return nil }
            let overlap = windowFrame.maxX - taskbarLeftX
            guard overlap > threshold else { return nil }
            let newWidth = windowFrame.width - overlap
            guard newWidth >= TaskbarConstants.WorkArea.minimumWindowDimension else { return nil }
            guard abs(newWidth - windowFrame.width) >= TaskbarConstants.WorkArea.clampingRecursionGuardDelta else { return nil }
            return CGRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: newWidth, height: windowFrame.height)
        }
    }
    
    /// Backward-compatible method calculating clamped frame for bottom-anchored taskbar.
    public static func clampWindowFrame(
        _ windowFrame: CGRect,
        screenFrame: CGRect,
        taskbarHeight: CGFloat,
        allowNonMaximized: Bool = true
    ) -> CGRect? {
        clampedFrame(
            windowFrame: windowFrame,
            screenBounds: screenFrame,
            barDimension: Double(taskbarHeight),
            edge: .bottom,
            overlapThreshold: Double(overlapThreshold),
            allowNonMaximized: allowNonMaximized
        )
    }
    
    /// Resolves the appropriate screen from `screens` and computes the clamped frame for multi-edge taskbars.
    public static func clampedFrameForWindow(
        _ windowFrame: CGRect,
        across screens: [ScreenDescriptor],
        barDimension: Double,
        edge: TaskbarEdge = .bottom,
        overlapThreshold: Double = TaskbarConstants.Clamping.subpixelOverlapThreshold,
        allowNonMaximized: Bool = true
    ) -> CGRect? {
        guard let screenID = ScreenAssignment.assignScreen(for: windowFrame, across: screens),
              let screen = screens.first(where: { $0.id == screenID }) else {
            return nil
        }
        return clampedFrame(
            windowFrame: windowFrame,
            screenBounds: screen.frame,
            barDimension: barDimension,
            edge: edge,
            overlapThreshold: overlapThreshold,
            allowNonMaximized: allowNonMaximized
        )
    }
    
    /// Backward-compatible resolution across screens for bottom-anchored taskbar.
    public static func clampedFrameForWindow(
        _ windowFrame: CGRect,
        across screens: [ScreenDescriptor],
        taskbarHeight: CGFloat,
        allowNonMaximized: Bool = true
    ) -> CGRect? {
        clampedFrameForWindow(
            windowFrame,
            across: screens,
            barDimension: Double(taskbarHeight),
            edge: .bottom,
            overlapThreshold: Double(overlapThreshold),
            allowNonMaximized: allowNonMaximized
        )
    }
}
