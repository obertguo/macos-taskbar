# macOS Accessibility Lifecycle & Functional Test Harness Hardening

This document records the investigation, root causes, architectural fixes, and verification results for the macOS Accessibility (`AXUIElement`) event tracking and test harness failures diagnosed prior to Milestone 3 of v0.2.0.

---

## 1. Executive Summary

During pre-Milestone 3 verification via `./scripts/test-functional.sh --quick`, test failures were observed across the `WindowLifecycleIntegrationTests` suite:
- `TC-FUNC-002: Window minimization state tracking` (`minimized == true -> false`)
- `TC-FUNC-003: Window restoration / deminiaturization state tracking` (`restored == true -> false`)
- `TC-FUNC-005: Dynamic window title mutation` (`titleChanged == true -> false`)
- `TC-FUNC-006: Window close and taskbar store teardown` (`closed == true -> false`)
- `TC-FUNC-007: Application termination and observer cleanup` (`cleared == true -> false`)

Detailed profiling and diagnostic logging revealed that the failures were not random flakiness, but resulted from five distinct architectural and OS-level quirks:
1. **macOS Accessibility Subrole Mutation on Minimization (`AXDialog`):** When Cocoa windows are minimized into the Dock, macOS Accessibility dynamically mutates their accessibility subrole to `AXDialog`. `WindowFilter` was rejecting dialog subroles prior to evaluating minimization status.
2. **In-Flight Reconciliation Event Dropping in `AppTracker`:** During rapid notification bursts (such as deminiaturization), notifications arriving while `AppTracker.reconcileWindows()` was actively executing were silently discarded because `guard !isRefreshing else { return }` lacked a pending re-trigger flag.
3. **Multi-Window Collisions on Test Fixture Launch:** Launching TextEdit opens an "Untitled" document window by default. Spawning another document via AppleScript resulted in two windows competing for 1-based index targeting.
4. **Premature `isTerminated` Latch in `TestFixtureApp`:** `launchTextEdit` called `fixture.terminate()` to clean prior dangling instances, which inadvertently set `self.isTerminated = true` on the newly instantiated fixture before the test ran, neutralizing subsequent termination calls.
5. **Swift Testing Default Parallel Execution on Singleton OS Apps:** Swift Testing executes test cases within a `@Suite` concurrently by default. Running multiple tests concurrently against a single shared macOS application (`TextEdit`) caused race conditions across window counts and process lifetimes.

---

## 2. Deep Dive: Bug Diagnoses & Fixes

### 1. Minimization Subrole Morphing (`WindowFilter.swift`)

#### Symptoms
In `TC-FUNC-002`, `store.allWindows.first(where: { $0.appName == "TextEdit" })?.isMinimized` remained `false` even though TextEdit was visibly minimized into the Dock.

#### Root Cause Analysis
Diagnostic tracking in `reconcileWindows` captured the following state before and after minimization:
```
# Prior to minimize:
[DEBUG TRACKER] TextEdit win: role=AXWindow subrole=AXStandardWindow isMin=false title=MiniDoc_... frame=(170, 93, 586, 488)

# After minimize:
[DEBUG AX] handleNotification: AXWindowMiniaturized
[DEBUG TRACKER] TextEdit win: role=AXWindow subrole=AXDialog isMin=true title=MiniDoc_... frame=(170, 93, 586, 488)
```
When a Cocoa window is miniaturized, macOS WindowServer/AppKit alters its accessibility subrole from `AXStandardWindow` to `AXDialog`. In `WindowFilter.swift`, the filtering rules were structured as:
```swift
// Prior logic:
// 4. Reject modal dialogs, sheets, palettes, and popovers
if let subrole = subrole, TaskbarConstants.Accessibility.rejectedSubroles.contains(subrole) {
    return false
}

// 5. Minimized windows are preserved regardless of frame size
if isMinimized {
    return true
}
```
Because `"AXDialog"` was listed in `TaskbarConstants.Accessibility.rejectedSubroles`, step 4 rejected the window *before* step 5 could check `if isMinimized`. The minimized window was purged from `WindowStore`, causing `store.allWindows` to either return `nil` or an unminimized secondary window.

#### Fix Implementation
Updated rule 4 in `Sources/TaskbarCore/Logic/WindowFilter.swift` to only reject dialog subroles when `!isMinimized`:
```swift
// 4. Reject modal dialogs, sheets, palettes, and popovers (unless minimized, as macOS may report minimized windows with AXDialog)
if !isMinimized, let subrole = subrole, TaskbarConstants.Accessibility.rejectedSubroles.contains(subrole) {
    return false
}

// 5. Minimized windows are preserved regardless of frame size (docked windows shrink to 0x0)
if isMinimized {
    return true
}
```

---

### 2. In-Flight Reconciliation Starvation & Event Dropping (`AppTracker.swift`)

#### Symptoms
In `TC-FUNC-003`, restoring a window generated an `AXWindowDeminiaturized` notification, but `store.allWindows` never updated `isMinimized = false`.

#### Root Cause Analysis
When a window restores and gains focus, macOS dispatches a flurry of AX notifications in quick succession:
1. `AXFocusedWindowChanged`
2. `AXMainWindowChanged`
3. `AXWindowDeminiaturized`

The first notification invoked `scheduleReconcile()`, which launched `reconcileWindows()` on the background `AXThread` and set `isRefreshing = true`. When `AXWindowDeminiaturized` arrived a few milliseconds later, `reconcileWindows()` encountered:
```swift
guard !isRefreshing, AccessibilityPermission.isGranted() else { return }
```
Because `isRefreshing` was already `true`, the deminiaturization event was dropped entirely without rescheduling. The first pass completed before the OS had updated the window's minimized attribute, leaving the store stuck on `isMinimized = true`.

#### Fix Implementation
Added a `needsReconcileAgain` latch to `AppTracker.swift`:
```swift
private var isRefreshing = false
private var needsReconcileAgain = false

private func reconcileWindows() {
    guard AccessibilityPermission.isGranted() else { return }
    if isRefreshing {
        needsReconcileAgain = true
        return
    }
    isRefreshing = true
    needsReconcileAgain = false
    
    // ... perform snapshot reconciliation on AXThread ...
    
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        // ... apply updates to WindowStore ...
        self.isRefreshing = false
        self.onWindowsChanged?()
        
        if self.needsReconcileAgain {
            self.needsReconcileAgain = false
            self.scheduleReconcile(delay: TaskbarConstants.Timing.frameRenderDebounce)
        }
    }
}
```
Now, any AX event received while a reconciliation pass is active flags `needsReconcileAgain`, guaranteeing a follow-up reconciliation pass runs immediately after the in-flight snapshot commits.

---

### 3. Premature Termination Latch in Test Fixture (`TestFixtureApp.swift`)

#### Symptoms
In `TC-FUNC-007: Application termination and observer cleanup`, terminating TextEdit failed to remove the window from `WindowStore`.

#### Root Cause Analysis
In `TestFixtureApp.swift`:
```swift
// Prior logic:
public static func launchTextEdit(documentTitle: String = "TaskbarTestDoc") async throws -> TestFixtureApp {
    let fixture = TestFixtureApp(appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
    
    // Ensure any previous dangling instances are cleanly quit
    fixture.terminate() // <-- Sets fixture.isTerminated = true!
    ...
    return fixture
}
```
`fixture.terminate()` guarded with:
```swift
guard !isTerminated else { return }
isTerminated = true
```
Calling `fixture.terminate()` inside `launchTextEdit` permanently set `isTerminated = true` on that instance. When `TC-FUNC-007` later called `fixture.terminate()`, the guard immediately exited without sending any termination signal to `TextEdit`.

#### Fix Implementation
Extracted static teardown logic in `Tests/TaskbarIntegrationTests/Helpers/TestFixtureApp.swift`:
```swift
public static func terminateApp(appName: String = "TextEdit", bundleIdentifier: String = "com.apple.TextEdit") {
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleIdentifier {
        app.terminate()
    }
    let script = """
    if application "\(appName)" is running then
        tell application "\(appName)" to quit saving no
    end if
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try? process.run()
    process.waitUntilExit()
}
```
`launchTextEdit` now calls `Self.terminateApp()` prior to instantiating `fixture`, ensuring the instance's `isTerminated` property remains `false` until explicitly torn down by the test.

---

### 4. Clean Single-Document Fixture Environment

#### Symptoms
Title mutation and close tests occasionally observed unexpected `Untitled` documents interfering with index-based window queries.

#### Root Cause Analysis
By default, TextEdit opens an `Untitled` document upon launching. When `launchTextEdit` called `make new document`, TextEdit wound up with two open documents. Subsequent AppleScript commands operating on `window 1` targeted the frontmost window, which fluctuated depending on focus.

#### Fix Implementation
Updated `launchTextEdit` in `TestFixtureApp.swift` to close any default untitled documents before creating the test document:
```applescript
tell application "TextEdit"
    activate
    close every document saving no
    make new document with properties {name:"\(documentTitle)"}
end tell
```
Additionally, `restoreWindow` now explicitly raises and activates the deminiaturized window via `AXRaise` and AppKit activation.

---

### 5. Suite Serialization (`WindowLifecycleIntegrationTests.swift`)

#### Symptoms
Running all lifecycle tests in a single invocation led to cross-test race conditions where one test's teardown terminated `TextEdit` while another test was initializing.

#### Root Cause Analysis
Swift Testing parallelizes test execution within a `@Suite` by default. Because macOS allows only a single instance of `com.apple.TextEdit` per user session, tests targeting TextEdit cannot safely run concurrently.

#### Fix Implementation
Decorated the suite with `.serialized` in `Tests/TaskbarIntegrationTests/WindowLifecycleIntegrationTests.swift`:
```swift
@Suite("Window Lifecycle Integration Suite", .serialized)
@MainActor
struct WindowLifecycleIntegrationTests { ... }
```

---

## 3. Verification & Results

Following these changes, both the automated functional test script and the comprehensive test suite passed with 100% success:

### Quick Functional Test Run (`./scripts/test-functional.sh --quick`)
```
======================================================
   Taskbar Automated Test Runner (Mode: quick)
======================================================
✓ OS check passed: macOS 27.0.1 (required: >= 14.0)
Checking Accessibility permissions... ✓ Accessibility permissions GRANTED
==> Running Quick Window Lifecycle Suite (TC-FUNC-*)...
Building for debugging...
Build complete! (0.52 secs.)
◇ Test run started.
◇ Suite "Window Lifecycle Integration Suite" started.
✔ Test "TC-FUNC-001: Window creation and taskbar store discovery" passed after 3.740 seconds.
✔ Test "TC-FUNC-002: Window minimization state tracking" passed after 4.045 seconds.
✔ Test "TC-FUNC-003: Window restoration / deminiaturization state tracking" passed after 4.733 seconds.
✔ Test "TC-FUNC-005: Dynamic window title mutation" passed after 3.568 seconds.
✔ Test "TC-FUNC-006: Window close and taskbar store teardown" passed after 3.630 seconds.
✔ Test "TC-FUNC-007: Application termination and observer cleanup" passed after 3.385 seconds.
✔ Suite "Window Lifecycle Integration Suite" passed after 23.106 seconds.
✔ Test run with 6 tests in 1 suite passed after 23.106 seconds.
======================================================
   Test Execution Summary
======================================================
Mode:          quick
Duration:      28s
Taskbar RSS:   22.32 MB -> 22.89 MB (within 45.0 MB bound)
✓ ALL TEST SUITES PASSED SUCCESSFULLY!
```

### Full Repository Test Suite (`swift test`)
- `TaskbarCoreTests`: **59 tests passed, 0 failures**
- `TaskbarIntegrationTests`: **16 tests passed, 0 failures**
- **Total: 75 tests passing, 0 regressions.**
