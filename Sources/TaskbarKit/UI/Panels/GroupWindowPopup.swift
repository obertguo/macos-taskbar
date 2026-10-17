// Sources/TaskbarKit/UI/Panels/GroupWindowPopup.swift

import AppKit
import TaskbarCore

/// A lightweight popup panel displaying all open windows belonging to a grouped application.
/// Anchored directly above the corresponding taskbar button, supporting mouse selection,
/// keyboard navigation (Up/Down/Return/Escape), individual window closing, and active focus indicators.
@MainActor
public final class GroupWindowPopup: NSPanel {
    public private(set) var group: WindowGroup
    public var theme: ThemeDefinition {
        didSet {
            popupContentView.theme = theme
            popupContentView.needsDisplay = true
        }
    }
    
    public var windows: [WindowInfo] {
        get { popupContentView.windows }
        set { popupContentView.windows = newValue }
    }
    
    public var selectedIndex: Int? {
        get { popupContentView.selectedIndex }
        set { popupContentView.selectedIndex = newValue }
    }
    
    public var onSelectWindow: ((WindowInfo) -> Void)?
    public var onCloseWindow: ((WindowKey) -> Void)?
    public var onDismiss: (() -> Void)?
    
    private let popupContentView: GroupWindowContentView
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var isDismissing: Bool = false
    
    public init(
        group: WindowGroup,
        theme: ThemeDefinition,
        focusedKey: WindowKey? = nil,
        frontmostPID: pid_t? = nil
    ) {
        self.group = group
        self.theme = theme
        self.popupContentView = GroupWindowContentView(
            group: group,
            theme: theme,
            focusedKey: focusedKey,
            frontmostPID: frontmostPID
        )
        
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.contentView = popupContentView
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        
        popupContentView.onSelect = { [weak self] win in
            self?.selectWindow(win)
        }
        
        popupContentView.onClose = { [weak self] win in
            self?.handleCloseWindow(win)
        }
    }
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
    
    public override func resignKey() {
        super.resignKey()
        if !isDismissing {
            dismiss()
        }
    }
    
    public func show(
        anchoredTo buttonRect: NSRect,
        in screen: NSScreen,
        focusedKey: WindowKey?,
        frontmostPID: pid_t?
    ) {
        isDismissing = false
        popupContentView.focusedKey = focusedKey
        popupContentView.frontmostPID = frontmostPID
        
        let preferredSize = popupContentView.preferredSize()
        let screenFrame = screen.visibleFrame.isEmpty ? screen.frame : screen.visibleFrame
        
        var originX = buttonRect.minX
        if originX + preferredSize.width > screenFrame.maxX - 4.0 {
            originX = screenFrame.maxX - preferredSize.width - 4.0
        }
        if originX < screenFrame.minX + 4.0 {
            originX = screenFrame.minX + 4.0
        }
        
        let originY = buttonRect.maxY + TaskbarConstants.GroupPopup.verticalOffset
        let panelFrame = NSRect(
            x: originX,
            y: originY,
            width: preferredSize.width,
            height: preferredSize.height
        )
        
        setFrame(panelFrame, display: true)
        orderFrontRegardless()
        makeKey()
        
        installEventMonitor()
    }
    
    public func updateGroup(
        _ group: WindowGroup,
        focusedKey: WindowKey?,
        frontmostPID: pid_t?,
        theme: ThemeDefinition
    ) {
        self.group = group
        self.theme = theme
        popupContentView.theme = theme
        popupContentView.focusedKey = focusedKey
        popupContentView.frontmostPID = frontmostPID
        popupContentView.windows = group.windows
        popupContentView.needsDisplay = true
        
        let preferredSize = popupContentView.preferredSize()
        var newFrame = frame
        newFrame.size.width = preferredSize.width
        newFrame.size.height = preferredSize.height
        if let targetScreen = self.screen ?? NSScreen.main ?? NSScreen.screens.first {
            let screenFrame = targetScreen.visibleFrame.isEmpty ? targetScreen.frame : targetScreen.visibleFrame
            if newFrame.origin.x + preferredSize.width > screenFrame.maxX - 4.0 {
                newFrame.origin.x = screenFrame.maxX - preferredSize.width - 4.0
            }
            if newFrame.origin.x < screenFrame.minX + 4.0 {
                newFrame.origin.x = screenFrame.minX + 4.0
            }
        }
        setFrame(newFrame, display: true, animate: false)
    }
    
    public func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        removeEventMonitor()
        orderOut(nil)
        onDismiss?()
    }
    
    public func selectWindow(_ window: WindowInfo) {
        onSelectWindow?(window)
        dismiss()
    }
    
    private func handleCloseWindow(_ window: WindowInfo) {
        onCloseWindow?(window.key)
        popupContentView.removeWindow(forKey: window.key)
        
        if popupContentView.windows.isEmpty {
            dismiss()
        } else {
            // Resize panel smoothly for remaining items
            let preferredSize = popupContentView.preferredSize()
            var newFrame = frame
            newFrame.size.height = preferredSize.height
            setFrame(newFrame, display: true, animate: true)
        }
    }
    
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case TaskbarConstants.KeyCodes.escape:
            dismiss()
        case TaskbarConstants.KeyCodes.upArrow:
            popupContentView.moveSelection(up: true)
        case TaskbarConstants.KeyCodes.downArrow:
            popupContentView.moveSelection(up: false)
        case TaskbarConstants.KeyCodes.returnKey:
            if let selected = popupContentView.currentlySelectedWindow() {
                selectWindow(selected)
            }
        default:
            super.keyDown(with: event)
        }
    }
    
    private func installEventMonitor() {
        removeEventMonitor()
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            let clickLoc = NSEvent.mouseLocation
            if !self.frame.contains(clickLoc) {
                self.dismiss()
            }
            return event
        }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.dismiss()
                }
            }
        }
        
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }
    
    private func removeEventMonitor() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceObserver = nil
        }
    }
    
    deinit {
        MainActor.assumeIsolated {
            removeEventMonitor()
        }
    }
}

