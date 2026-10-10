// Sources/TaskbarKit/UI/Panels/GroupWindowContentView.swift

import AppKit
import TaskbarCore

/// A layered container view holding the frosted-glass background (NSVisualEffectView)
/// and the foreground rows view (GroupWindowRowsView) for a window group popup panel.
@MainActor
internal final class GroupWindowContentView: NSView {
    var theme: ThemeDefinition {
        didSet {
            applyTheme(theme)
        }
    }
    
    var windows: [WindowInfo] {
        get { rowsView.windows }
        set { rowsView.windows = newValue }
    }
    
    var focusedKey: WindowKey? {
        get { rowsView.focusedKey }
        set { rowsView.focusedKey = newValue }
    }
    
    var frontmostPID: pid_t? {
        get { rowsView.frontmostPID }
        set { rowsView.frontmostPID = newValue }
    }
    
    var selectedIndex: Int? {
        get { rowsView.selectedIndex }
        set { rowsView.selectedIndex = newValue }
    }
    
    var onSelect: ((WindowInfo) -> Void)? {
        get { rowsView.onSelect }
        set { rowsView.onSelect = newValue }
    }
    
    var onClose: ((WindowInfo) -> Void)? {
        get { rowsView.onClose }
        set { rowsView.onClose = newValue }
    }
    
    private let visualEffectView = NSVisualEffectView()
    private let rowsView: GroupWindowRowsView
    
    init(
        group: WindowGroup,
        theme: ThemeDefinition,
        focusedKey: WindowKey?,
        frontmostPID: pid_t?
    ) {
        self.theme = theme
        self.rowsView = GroupWindowRowsView(
            group: group,
            theme: theme,
            focusedKey: focusedKey,
            frontmostPID: frontmostPID
        )
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        layer?.masksToBounds = true
        
        // 1. Background visual effect view (frosted glass)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.isHidden = !theme.useTranslucency || theme.is3DBeveled
        visualEffectView.material = VisualEffectMapping.resolveMaterial(theme.material)
        visualEffectView.blendingMode = VisualEffectMapping.resolveBlendingMode(theme.blendingMode)
        addSubview(visualEffectView)
        
        // 2. Foreground rows view (rendered above visualEffectView)
        rowsView.autoresizingMask = [.width, .height]
        rowsView.wantsLayer = true
        addSubview(rowsView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override func layout() {
        super.layout()
        visualEffectView.frame = bounds
        rowsView.frame = bounds
    }
    
    private func applyTheme(_ theme: ThemeDefinition) {
        layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        visualEffectView.layer?.cornerRadius = theme.is3DBeveled ? 0 : TaskbarConstants.GroupPopup.cornerRadius
        visualEffectView.isHidden = !theme.useTranslucency || theme.is3DBeveled
        visualEffectView.material = VisualEffectMapping.resolveMaterial(theme.material)
        visualEffectView.blendingMode = VisualEffectMapping.resolveBlendingMode(theme.blendingMode)
        rowsView.theme = theme
    }
    
    func removeWindow(forKey key: WindowKey) {
        rowsView.removeWindow(forKey: key)
    }
    
    func currentlySelectedWindow() -> WindowInfo? {
        rowsView.currentlySelectedWindow()
    }
    
    func moveSelection(up: Bool) {
        rowsView.moveSelection(up: up)
    }
    
    func preferredSize() -> NSSize {
        rowsView.preferredSize()
    }
}
