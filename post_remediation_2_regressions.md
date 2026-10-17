# Post-Remediation 2 Regression Investigation & Plan

This document details the root cause analysis, empirical live test results, and remediation plan for the regressions identified following Post-Remediation Audit Pass 3.

---

## 1. Regression 1: Window Maximization Settle & Nudging Failure (`TC-EDGE-005` / `TC-EDGE-006`)

### Reported Behavior
> *"When I maximize a window, I sometimes see the window flicker as it tries to get nudged, but after settling, the window is covered by the taskbar and nudging fails."*

### Empirical Investigation & Root Causes

1. **Premature Settle Pass Termination (`WorkAreaEnforcer.swift:336, 352`):**
   - In PR2-07, `guard didClamp0 || effectiveResize` was changed to `guard didClamp0` and `guard didClamp1`.
   - A macOS zoom/maximize animation takes **200–300ms**.
   - **Scenario A (Pass 0 fires mid-animation at $t = 100\text{ms}$):**
     - The window is mid-flight and has not yet expanded far enough to overlap the taskbar reserved area.
     - `evaluateAndClampOnAX` returns `false` (`didClamp0 == false`).
     - `guard didClamp0` immediately exits, cancelling Pass 1 ($t = 220\text{ms}$) and Pass 2 ($t = 500\text{ms}$).
     - When the maximize animation completes at $\sim 250\text{ms}$, the window expands over the taskbar and remains covered because no follow-up passes run.
   - **Scenario B (Pass 0 clamps at $t = 100\text{ms}$ — the visible flicker):**
     - Pass 0 forces the window down to the clamped height (e.g. 826px), producing a visible flicker.
     - At $t = 220\text{ms}$, Pass 1 executes. Because the window is already at the clamped height from Pass 0, `clampedFrameForWindow` finds zero overlap and returns `nil`.
     - `evaluateAndClampOnAX` returns `false` (`didClamp1 == false`).
     - `guard didClamp1` immediately exits, cancelling Pass 2 ($t = 500\text{ms}$).
     - At $t = 250\text{–}300\text{ms}$, Chromium / macOS completes its zoom animation curve and resets the window to full screen height (870px). Because Pass 2 was dropped, the window remains permanently covered!

2. **Recursion Guard False-Positive Trip (`WorkAreaEnforcer.swift:463-487`):**
   - `TaskbarConstants.Timing.maxNudgeAttempts` was set to **`2` within `0.8s`** (`nudgeRecursionWindow`).
   - If Pass 0 nudges (`attempts = 1`), and the window zoom finish resets the window triggering another notification (`attempts = 2`), any follow-up pass or webview layout event trips `attempts >= maxAttempts` ($2 \ge 2$) and logs:
     `RECURSION GUARD BLOCKED winID: attempts=2, targetH=826.0`
     permanently refusing to clamp the window!

3. **Live System Verification:**
   - We tested setting Chrome Window 196 on the live machine directly to `(1440, 826)` via Accessibility API: Chrome accepted the clamped size immediately and stayed at `826px` after 50ms, 200ms, and 500ms without fighting back.
   - The failure was driven entirely by early timer drops and recursion guard starvation.

---

## 2. Regression 2: Multi-Monitor Window Focus Targeting

### Reported Behavior
> *"Setup: Have two instances of an app (e.g., chrome) in an inactive state on each of 2 monitors, and click on Chrome on one of the monitor (e.g., monitor #2). Expected: The chrome window opens only on monitor #2. Actual: Sometimes, Chrome window on monitor #1 opens, and sometimes both chrome windows on #1 and #2 opens."*

### Empirical Investigation & Root Causes

1. **Why Chrome on Monitor 1 opens (Screen Context Loss):**
   - In `TaskbarView.swift:383-387`, the pinned button click handler calls:
     ```swift
     AppEnvironment.current.windowActions.launchOrActivateApp(
         bundleIdentifier: btn.pinnedApp.bundleIdentifier,
         customPath: btn.pinnedApp.customPath,
         store: self.store
     )
     ```
   - In `WindowActions.swift:168-170`, `launchOrActivateApp` queried `store.allWindows` across **all screens** and executed:
     ```swift
     WindowGroup.primaryWindow(from: appWindows)
     ```
   - `primaryWindow` selected the window with the highest `focusOrder` globally across all screens. If the user last interacted with Chrome on Monitor 1, `primaryWindow` selected the window on Monitor 1, completely ignoring the fact that the user clicked on Monitor 2.

2. **Why both Chrome windows open (Carbon Front-Window Activation & Bulk Fallback):**
   - In `PrivateAPI.swift`:
     ```swift
     _ = setFront(&psn, 1) // SetFrontProcessWithOptions(&psn, kSetFrontProcessFrontWindowOnly)
     _ = slpsSetFront(&psn, windowID, 0x200) // _SLPSSetFrontProcessWithOptions
     ```
   - WindowServer / SkyLight logs revealed:
     ```
     TaskbarApp: (HIServices) SetFrontProcess: asn=... options=1
     TaskbarApp: (SkyLight) SLPSetFrontProcess(window=0 options=0x0)      <-- Raises default front window on Monitor 1!
     TaskbarApp: (SkyLight) SLPSetFrontProcess(window=32227 options=0x200) <-- Raises target window on Monitor 2!
     ```
   - Calling `SetFrontProcessWithOptions(&psn, 1)` tells macOS to raise the application's default front window (Monitor 1). 6 milliseconds later, `_SLPSSetFrontProcessWithOptions` raised the target window on Monitor 2. Both windows were brought to the foreground!
   - In `WindowActions.swift:53`, the fallback path called `NSRunningApplication.activate()` with default arguments (`.activateAllWindows`), raising every window of that app across all monitors simultaneously.

3. **Live System Verification:**
   - Calling `_SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200)` **first** marks the target window as frontmost inside the app, and `SetFrontProcessWithOptions(&psn, 1)` **second** elevates the app while raising exclusively that designated window.

---

## 3. Regression 3: Multi-Window Focus Latency (Double-Click) & Active Button State Synchronization

### Reported Behavior
1. **Double Click Required:** In multi-window apps (especially Chrome, VS Code, and Electron apps), clicking a taskbar window button on another monitor or when the app is active sometimes requires clicking twice to bring it up.
2. **Active States Sticking (Multiple Active Buttons):** Multiple window buttons in the taskbar remain in the highlighted active state simultaneously and do not reset when clicking between windows or when a new window is opened.

### Empirical Findings & Root Cause Analysis

1. **ClickPolicy Premature Minimization:**
   - In `ClickPolicy.leftClickAction`:
     ```swift
     if isFrontmostApp {
         if focusedKey == window.key || window.isMain || focusedKey == nil {
             return .minimize
         }
     }
     ```
   - Chromium and Electron apps (Chrome, VS Code, GitHub Desktop) return `kAXErrorNoValue` (-25212) for `kAXFocusedWindowAttribute`. Thus `focusedKey` was often `nil`.
   - When Chrome or VS Code was frontmost, clicking a secondary window evaluated `isFrontmostApp == true` and `focusedKey == nil`, returning `.minimize` on Click 1!
   - On Click 2, the window was now minimized, so ClickPolicy returned `.restoreAndFocus`, bringing the window up on the second click.

2. **Optimistic Visual Update Did Not Reset Sibling Buttons:**
   - In `TaskbarView.swift:btn.onClick`:
     When action was `.focus` or `.restoreAndFocus`, it set `btn.isFocusedWindow = true`, but never set `other.isFocusedWindow = false` on the remaining task buttons.

3. **No Cross-Panel Synchronization on Click:**
   - When clicking a button on Monitor 2, Monitor 1's taskbar was never notified to clear its active button highlight because `ScreenManager.updateWindows()` was not triggered synchronously across panels.

4. **Window Creation Did Not Focus Frontmost Windows in Store:**
   - When a new window was created (`kAXWindowCreatedNotification`), `self.store.addOrUpdateWindow(info)` was called, but `store.setFocusedWindow` and `store.setFrontmostPID` were not updated. Thus, the previous window retained the active highlight.

5. **Lack of Resilient Frontmost Window Resolution:**
   - Because Chromium/Electron omit `kAXFocusedWindowAttribute`, `inspectApp` returned `nil` for `focusedKey`. `reconcileDirtyPIDs` never updated `store.focusedWindowKey`.
   - By querying WindowServer front-to-back Z-order (`CGWindowListCopyWindowInfo` with layer 0), the frontmost window can be resolved instantly even for Chromium/Electron apps.

---

## 4. Consolidated Remediations Applied

1. **`TaskbarConstants.swift`:**
   - Increased `Timing.maxNudgeAttempts` from `2` to `4` within `0.8s` window to allow Pass 0, Pass 1, Pass 2, and 1 intermediate animation frame to settle naturally without premature recursion guard blocking.

2. **`WorkAreaEnforcer.swift`:**
   - Ensured maximize settle continuation: if Pass 0 clamps (`didClamp0 == true`) or if the window is resizing near the taskbar boundary, Pass 1 and Pass 2 proceed through full animation completion (up to 500ms) rather than prematurely terminating.

3. **`ClickPolicy.swift`:**
   - Removed `|| focusedKey == nil`. Only returns `.minimize` if `focusedKey == window.key`, or if `focusedKey == nil && window.isMain`. Secondary windows of frontmost apps always return `.focus` on the first click.

4. **`PrivateAPI.swift` (Elevation Order Fix):**
   - Executed `slpsSetFront(&psn, windowID, 0x200)` FIRST to designate the target window as frontmost inside the owning process.
   - Executed `setFrontProcessWithOptions(&psn, 1)` SECOND using `kSetFrontProcessFrontWindowOnly`. Because `windowID` is already designated as front, macOS elevates the application and raises ONLY the target window, leaving the secondary window on the other monitor in the background.

5. **`WindowActions.swift` (Synchronous Elevation & Screen Awareness):**
   - In `focusWindow`: invokes `activateSingleWindow(key: key)` immediately and synchronously on click without blocking behind the serial `AXThread` queue.
   - Added `frontmostWindowID(forPID:)` via `CGWindowListCopyWindowInfo` for resilient WindowServer Z-order front window resolution.
   - Updated `launchOrActivateApp` with `preferredWindows: [WindowInfo]?` and safe `activate(options: [])` to prioritize target display windows and avoid bulk window raising.

6. **`AppTracker.swift`:**
   - In `inspectApp`: added fallback to `WindowActions.frontmostWindowID(forPID: pid)` when `isFrontmost` is true and `kAXFocusedWindowAttribute` returns no value.
   - In `reconcileDirtyPIDs`: synchronized `store.setFrontmostPID(frontmostPID)` and cleared/set `focusedWindowKey` appropriately.
   - In `kAXWindowCreatedNotification`: immediately sets `store.setFrontmostPID` and `store.setFocusedWindow` if the new window belongs to the frontmost app.

7. **`TaskbarView.swift` & `ScreenManager.swift`:**
   - In `TaskbarView.btn.onClick`: reset all sibling task buttons (`for other in self.taskButtons { other.isFocusedWindow = (other === btn) }`).
   - Added `onFocusRequested: ((WindowKey) -> Void)?` callback wired in `ScreenManager` to immediately update `store.setFrontmostPID`, `store.setFocusedWindow`, and call `updateWindows()` across all physical display panels simultaneously.

---

## 5. Automated Test Suite & Verification Results

### Unit & Integration Test Coverage
- **Total Tests Passed:** **236 tests across 32 suites** (124 Unit/Core tests + 112 Integration tests).
- **Core Tests:** `Tests/TaskbarCoreTests` — 124 tests in 16 suites (0 failures).
- **Integration Tests:** `Tests/TaskbarIntegrationTests` — 112 tests in 16 suites (0 failures).

### Added Test Specifications
1. `ClickPolicyTests.testClickSecondaryWindowOfFrontmostAppWithNilFocusedKey`:
   - Verifies that clicking a secondary window when `focusedKey` is `nil` returns `.focus`, not `.minimize`.
2. `ClickPolicyTests.testClickSecondaryWindowOfFrontmostAppWhenAnotherWindowIsFocused`:
   - Verifies that clicking a secondary window when another window is focused returns `.focus`.
3. `PinnedAppsIntegrationTests.testTaskbarViewClickResetsActiveStateOnOtherButtons`:
   - Verifies clicking a button resets `isFocusedWindow` on all other buttons in the panel.
4. `PinnedAppsIntegrationTests.testScreenManagerSynchronizesFocusAcrossMultiScreenPanels`:
   - Verifies multi-screen focus synchronization updates all display panels.
5. `WorkAreaEnforcerTests.testRecursionGuardAllowsUpToMaxAttempts`:
   - Verifies 4 attempts within the recursion window before blocking.
6. `AppEnvironmentTests.testLaunchOrActivateAppWithPreferredWindowsOnTargetScreen`:
   - Verifies multi-monitor display targeting for pinned/running apps.
