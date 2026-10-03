// Sources/TaskbarCore/Logic/ScreenAssignment.swift

import Foundation
import CoreGraphics

public struct ScreenDescriptor: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let frame: CGRect
    public let isPrimary: Bool
    
    public init(id: UInt32, frame: CGRect, isPrimary: Bool = false) {
        self.id = id
        self.frame = frame
        self.isPrimary = isPrimary
    }
}

public enum ScreenAssignment {
    /// Determines which screen a window belongs to based on the screen that contains the majority of the window's area.
    public static func assignScreen(for windowFrame: CGRect, across screens: [ScreenDescriptor]) -> UInt32? {
        guard !screens.isEmpty else { return nil }
        
        var bestScreenID: UInt32? = nil
        var maxIntersectionArea: CGFloat = 0.0
        
        for screen in screens {
            let intersection = windowFrame.intersection(screen.frame)
            if !intersection.isNull && !intersection.isEmpty {
                let area = intersection.width * intersection.height
                if area > maxIntersectionArea {
                    maxIntersectionArea = area
                    bestScreenID = screen.id
                }
            }
        }
        
        // If window overlaps at least one screen, return screen with largest overlap
        if let best = bestScreenID, maxIntersectionArea > 0 {
            return best
        }
        
        // Fallback: If window is offscreen or minimized, pick the nearest screen by center distance
        let windowCenter = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        var minDistance: CGFloat = .infinity
        var closestScreenID: UInt32 = screens[0].id
        
        for screen in screens {
            let screenCenter = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let dx = windowCenter.x - screenCenter.x
            let dy = windowCenter.y - screenCenter.y
            let dist = sqrt(dx * dx + dy * dy)
            
            if dist < minDistance {
                minDistance = dist
                closestScreenID = screen.id
            }
        }
        
        return closestScreenID
    }
}
