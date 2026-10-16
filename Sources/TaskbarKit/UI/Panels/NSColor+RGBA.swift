// Sources/TaskbarKit/UI/Panels/NSColor+RGBA.swift

import AppKit
import TaskbarCore

public extension NSColor {
    convenience init(rgba: RGBAColor) {
        self.init(
            red: CGFloat(rgba.red),
            green: CGFloat(rgba.green),
            blue: CGFloat(rgba.blue),
            alpha: CGFloat(rgba.alpha)
        )
    }
}
