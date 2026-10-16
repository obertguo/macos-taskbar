// Sources/TaskbarKit/Tracking/AXElement+Attributes.swift

import ApplicationServices
import Foundation
import CoreGraphics

extension AXUIElement {
    public func setTimeout(_ seconds: Float = 0.3) {
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
    
    private typealias AXUIElementGetWindowFunc = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let axUIElementGetWindowFn: AXUIElementGetWindowFunc? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: AXUIElementGetWindowFunc.self)
    }()

    /// Stable numerical identity based on native CGWindowID, falling back to CFHash
    public var windowID: UInt64 {
        var wid: CGWindowID = 0
        if let fn = Self.axUIElementGetWindowFn, fn(self, &wid) == .success, wid != 0 {
            return UInt64(wid)
        }
        return UInt64(bitPattern: Int64(CFHash(self)))
    }
}
