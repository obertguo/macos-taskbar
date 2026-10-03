// Sources/TaskbarApp/UI/TaskbarView.swift

import AppKit
import TaskbarCore

public final class TaskbarView: NSView {
    public var theme: ThemeDefinition {
        didSet {
            applyTheme()
        }
    }
    
    public var launcherAction: LauncherAction {
        didSet {
            // Updated launcher preference
        }
    }
    
    private let visualEffectView = NSVisualEffectView()
    public let startButton: StartButton
    
    public init(theme: ThemeDefinition, launcherAction: LauncherAction) {
        self.theme = theme
        self.launcherAction = launcherAction
        self.startButton = StartButton(theme: theme)
        super.init(frame: .zero)
        
        setupViews()
        applyTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        wantsLayer = true
        
        // Setup visual effect view for Modern Hybrid mode
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .underWindowBackground
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.frame = bounds
        addSubview(visualEffectView)
        
        // Setup StartButton
        startButton.onClick = { [weak self] in
            guard let self = self else { return }
            Launcher.launch(self.launcherAction)
        }
        addSubview(startButton)
    }
    
    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutComponents()
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutComponents()
    }
    
    private func layoutComponents() {
        visualEffectView.frame = bounds
        
        let padY: CGFloat = 2.0
        let btnH = max(18.0, bounds.height - (padY * 2))
        let btnW: CGFloat = (theme.style == .retroClassic) ? 56.0 : 62.0
        startButton.frame = NSRect(x: 3.0, y: padY, width: btnW, height: btnH)
    }
    
    private func applyTheme() {
        startButton.theme = theme
        visualEffectView.isHidden = !theme.useTranslucency
        layoutComponents()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        switch theme.style {
        case .retroClassic:
            // Solid classic gray
            NSColor(rgba: theme.backgroundColor).setFill()
            bounds.fill()
            
            // Top 1px white highlight line
            if let topBorder = theme.topBorderColor {
                NSColor(rgba: topBorder).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
                path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
                path.lineWidth = 1.0
                path.stroke()
            }
            
        case .modernHybrid:
            // Top subtle 1px border over the translucent material
            if let topBorder = theme.topBorderColor {
                NSColor(rgba: topBorder).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: bounds.minX, y: bounds.maxY - 0.5))
                path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
                path.lineWidth = 1.0
                path.stroke()
            }
        }
    }
}
