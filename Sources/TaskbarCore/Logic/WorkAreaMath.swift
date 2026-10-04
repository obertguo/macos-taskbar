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
    
    /// Calculates the clamped frame for a window given the screen bounds and taskbar height.
    /// Both `windowFrame` and `screenFrame` must be in the same coordinate space (Quartz / CoreGraphics display coordinates).
    ///
    /// - Parameters:
    ///   - windowFrame: The window's current frame (x, y, width, height).
    ///   - screenFrame: The target screen's bounds (x, y, width, height).
    ///   - taskbarHeight: The height reserved by the taskbar at the bottom of the screen.
    ///   - allowNonMaximized: If `false`, only vertically maximized/screen-filling windows are clamped. Defaults to `true`.
    /// - Returns: A new `CGRect` with clamped height if overlap exceeds `overlapThreshold`, or `nil` if no adjustment is needed.
    public static func clampWindowFrame(
        _ windowFrame: CGRect,
        screenFrame: CGRect,
        taskbarHeight: CGFloat,
        allowNonMaximized: Bool = true
    ) -> CGRect? {
        guard taskbarHeight > 0 else { return nil }
        
        if !allowNonMaximized {
            guard isVerticallyMaximized(windowFrame, screenFrame: screenFrame, taskbarHeight: taskbarHeight) else {
                return nil
            }
        }
        
        let taskbarTopY = screenFrame.maxY - taskbarHeight
        
        // Window top must be strictly above the taskbar top edge
        guard windowFrame.minY < taskbarTopY else { return nil }
        
        // Calculate how much the window extends into the taskbar reserved area
        let overlap = windowFrame.maxY - taskbarTopY
        guard overlap > overlapThreshold else { return nil }
        
        let newHeight = windowFrame.height - overlap
        guard newHeight >= minimumWindowHeight else { return nil }
        
        // Recursion guard: ignore adjustments of less than minimumClampingDelta
        guard abs(newHeight - windowFrame.height) >= TaskbarConstants.WorkArea.clampingRecursionGuardDelta else { return nil }
        
        return CGRect(
            x: windowFrame.origin.x,
            y: windowFrame.origin.y,
            width: windowFrame.width,
            height: newHeight
        )
    }
    
    /// Resolves the appropriate screen from `screens` and computes the clamped frame.
    ///
    /// - Parameters:
    ///   - windowFrame: The window's current frame in CoreGraphics coordinates.
    ///   - screens: The collection of available screen descriptors.
    ///   - taskbarHeight: The height reserved by the taskbar at the bottom of the screen.
    ///   - allowNonMaximized: If `false`, only vertically maximized/screen-filling windows are clamped. Defaults to `true`.
    /// - Returns: The clamped frame, or `nil` if no clamping is required or possible.
    public static func clampedFrameForWindow(
        _ windowFrame: CGRect,
        across screens: [ScreenDescriptor],
        taskbarHeight: CGFloat,
        allowNonMaximized: Bool = true
    ) -> CGRect? {
        guard let screenID = ScreenAssignment.assignScreen(for: windowFrame, across: screens),
              let screen = screens.first(where: { $0.id == screenID }) else {
            return nil
        }
        return clampWindowFrame(
            windowFrame,
            screenFrame: screen.frame,
            taskbarHeight: taskbarHeight,
            allowNonMaximized: allowNonMaximized
        )
    }
}
