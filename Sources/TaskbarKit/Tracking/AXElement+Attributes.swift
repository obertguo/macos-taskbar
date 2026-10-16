// Sources/TaskbarKit/Tracking/AXElement+Attributes.swift

import ApplicationServices
import Foundation
import CoreGraphics
import TaskbarCore

public struct RawWindowAttributes: Sendable {
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let isMinimized: Bool
    public let frame: CGRect?
    public let isMain: Bool
    public let isFullScreen: Bool
    
    public init(
        role: String?,
        subrole: String?,
        title: String?,
        isMinimized: Bool,
        frame: CGRect?,
        isMain: Bool,
        isFullScreen: Bool
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.isMinimized = isMinimized
        self.frame = frame
        self.isMain = isMain
        self.isFullScreen = isFullScreen
    }
}

extension AXUIElement {
    public func setTimeout(_ seconds: Float = TaskbarConstants.Timing.axTimeout) {
        AXUIElementSetMessagingTimeout(self, seconds)
    }
    
    public func attribute<T>(_ attribute: CFString) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute, &value)
        guard result == .success, let unwrapped = value else {
            return nil
        }
        return unwrapped as? T
    }
    
    public var role: String? {
        attribute(kAXRoleAttribute as CFString)
    }
    
    public var subrole: String? {
        attribute(kAXSubroleAttribute as CFString)
    }
    
    public var title: String? {
        attribute(kAXTitleAttribute as CFString)
    }
    
    public var isMinimized: Bool {
        let val: NSNumber? = attribute(kAXMinimizedAttribute as CFString)
        return val?.boolValue ?? false
    }
    
    public var isMain: Bool {
        let val: NSNumber? = attribute(kAXMainAttribute as CFString)
        return val?.boolValue ?? false
    }
    
    public var isFullScreen: Bool {
        let val: NSNumber? = attribute("AXFullScreen" as CFString)
        return val?.boolValue ?? false
    }
    
    public var isSizeSettable: Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(self, kAXSizeAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }
    
    @discardableResult
    public func setSize(_ size: CGSize) -> Bool {
        var newSize = size
        guard let val = AXValueCreate(.cgSize, &newSize) else { return false }
        let result = AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, val)
        return result == .success
    }
    
    @discardableResult
    public func setPosition(_ position: CGPoint) -> Bool {
        var newPosition = position
        guard let val = AXValueCreate(.cgPoint, &newPosition) else { return false }
        let result = AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, val)
        return result == .success
    }
    
    public var minimizeButton: AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXMinimizeButtonAttribute as CFString, &value)
        guard result == .success, let unwrapped = value,
              CFGetTypeID(unwrapped) == AXUIElementGetTypeID() else {
            return nil
        }
        return (unwrapped as! AXUIElement)
    }
    
    public var frame: CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        
        guard AXUIElementCopyAttributeValue(self, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(self, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posAx = posValue,
              let sizeAx = sizeValue,
              CFGetTypeID(posAx) == AXValueGetTypeID(),
              CFGetTypeID(sizeAx) == AXValueGetTypeID() else {
            return nil
        }
        
        var point = CGPoint.zero
        var size = CGSize.zero
        
        let pointOk = AXValueGetValue(posAx as! AXValue, .cgPoint, &point)
        let sizeOk = AXValueGetValue(sizeAx as! AXValue, .cgSize, &size)
        
        guard pointOk && sizeOk else { return nil }
        return CGRect(origin: point, size: size)
    }
    
    public var windows: [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else {
            return []
        }
        return array
    }
    
    public var focusedWindow: AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let win = value,
              CFGetTypeID(win) == AXUIElementGetTypeID() else {
            return nil
        }
        return (win as! AXUIElement)
    }
    
    public func fetchWindowAttributesBatch() -> RawWindowAttributes? {
        let attributes: [CFString] = [
            kAXRoleAttribute as CFString,
            kAXSubroleAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXMinimizedAttribute as CFString,
            kAXPositionAttribute as CFString,
            kAXSizeAttribute as CFString,
            kAXMainAttribute as CFString,
            "AXFullScreen" as CFString
        ]
        var valuesRef: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(
            self,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &valuesRef
        )
        guard result == .success, let values = valuesRef as? [AnyObject], values.count >= 8 else {
            return nil
        }
        
        let role = values[0] as? String
        let subrole = values[1] as? String
        let title = values[2] as? String
        let isMinimized = (values[3] as? NSNumber)?.boolValue ?? false
        
        var frame: CGRect? = nil
        let posVal = values[4]
        let sizeVal = values[5]
        if CFGetTypeID(posVal) == AXValueGetTypeID(),
           CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var size = CGSize.zero
            let pointOk = AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
            let sizeOk = AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            if pointOk && sizeOk {
                frame = CGRect(origin: point, size: size)
            }
        }
        
        let isMain = (values[6] as? NSNumber)?.boolValue ?? false
        let isFullScreen = (values[7] as? NSNumber)?.boolValue ?? false
        
        return RawWindowAttributes(
            role: role,
            subrole: subrole,
            title: title,
            isMinimized: isMinimized,
            frame: frame,
            isMain: isMain,
            isFullScreen: isFullScreen
        )
    }

    /// Stable numerical identity based on native CGWindowID
    public var windowID: UInt64? {
        if let wid = PrivateAPI.getWindowID(for: self) {
            return UInt64(wid)
        }
        return nil
    }
}
