// Sources/TaskbarCore/Logic/ButtonLayout.swift

import Foundation
import CoreGraphics

public struct ButtonLayoutResult: Equatable, Sendable {
    public let buttonWidth: Double
    public let visibleCount: Int
    public let showTitle: Bool
    public let hasOverflow: Bool
    
    public init(buttonWidth: Double, visibleCount: Int, showTitle: Bool, hasOverflow: Bool) {
        self.buttonWidth = buttonWidth
        self.visibleCount = visibleCount
        self.showTitle = showTitle
        self.hasOverflow = hasOverflow
    }
}

public enum ButtonLayout {
    /// Computes the uniform button width and visibility attributes for a row of task buttons.
    public static func computeLayout(
        availableWidth: Double,
        itemCount: Int,
        maxButtonWidth: Double = 160.0,
        minButtonWidth: Double = 80.0,
        spacing: Double = 2.0
    ) -> ButtonLayoutResult {
        guard itemCount > 0, availableWidth > 0 else {
            return ButtonLayoutResult(buttonWidth: maxButtonWidth, visibleCount: 0, showTitle: true, hasOverflow: false)
        }
        
        let totalSpacing = Double(itemCount - 1) * spacing
        let widthPerButton = (availableWidth - totalSpacing) / Double(itemCount)
        
        if widthPerButton >= maxButtonWidth {
            // Enough room for full-width buttons
            return ButtonLayoutResult(
                buttonWidth: maxButtonWidth,
                visibleCount: itemCount,
                showTitle: true,
                hasOverflow: false
            )
        } else if widthPerButton >= minButtonWidth {
            // Compressed buttons (shrinking evenly)
            let showTitle = widthPerButton >= 50.0
            return ButtonLayoutResult(
                buttonWidth: widthPerButton,
                visibleCount: itemCount,
                showTitle: showTitle,
                hasOverflow: false
            )
        } else {
            // Crowded bar: buttons fixed at minButtonWidth with overflow
            let maxVisible = Int(floor((availableWidth + spacing) / (minButtonWidth + spacing)))
            let visibleCount = max(0, min(itemCount, maxVisible))
            let hasOverflow = itemCount > visibleCount
            return ButtonLayoutResult(
                buttonWidth: minButtonWidth,
                visibleCount: visibleCount,
                showTitle: false,
                hasOverflow: hasOverflow
            )
        }
    }
}
