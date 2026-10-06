// Sources/TaskbarKit/Tracking/AXThread.swift

import Foundation

public final class AXThread: @unchecked Sendable {
    public static let shared = AXThread()
    
    private var thread: Thread!
    private var runLoopRef: CFRunLoop?
    private let initSemaphore = DispatchSemaphore(value: 0)
    
    private init() {
        thread = Thread { [weak self] in
            guard let self = self else { return }
            self.runLoopRef = CFRunLoopGetCurrent()
            
            // Add a persistent dummy source to prevent the RunLoop from exiting immediately
            var context = CFRunLoopSourceContext()
            if let dummySource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), dummySource, .commonModes)
            }
            
            self.initSemaphore.signal()
            CFRunLoopRun()
        }
        thread.name = "com.taskbar.ax-thread"
        thread.qualityOfService = .userInteractive
        thread.start()
        
        initSemaphore.wait()
    }
    
    public var runLoop: CFRunLoop {
        runLoopRef ?? CFRunLoopGetMain()
    }
    
    public func async(_ block: @escaping @Sendable () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            block()
        }
        CFRunLoopWakeUp(runLoop)
    }
}
