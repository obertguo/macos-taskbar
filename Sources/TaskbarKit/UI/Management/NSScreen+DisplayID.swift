// Sources/TaskbarKit/UI/Management/NSScreen+DisplayID.swift

import AppKit
import TaskbarCore

public extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
    
    var screenDescriptor: ScreenDescriptor {
        ScreenDescriptor(
            id: displayID ?? 0,
            frame: frame,
            isPrimary: self == NSScreen.screens.first
        )
    }
}
