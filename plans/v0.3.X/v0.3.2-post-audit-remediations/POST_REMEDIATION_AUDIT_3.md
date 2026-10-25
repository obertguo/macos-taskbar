# Taskbar — Third Post-Remediation Codebase Audit (`POST_REMEDIATION_AUDIT_3`)

**Date:** 2026-10-25  
**Commits Audited:** `e009d62` (`refactor: post-remediation pass 3`) & `ad6d88d` (`fix: resolve post-remediation regressions and synchronize documentation`) — 36 files changed, +1,272 / -255 lines since `81fc411`  
**Scope:** Verification of all 9 findings (`PR2-01` through `PR2-09`) from [`POST_REMEDIATION_AUDIT_2.md`](./POST_REMEDIATION_AUDIT_2.md) and the 3 user-reported regressions in [`post_remediation_2_regressions.md`](./post_remediation_2_regressions.md), plus a deep audit for any flaws or edge cases introduced by the latest fixes.

---

## 1. Executive Summary: Are We in a Better State Now?

**Yes — significantly.** All `P0` concurrency data races (`PR2-01`) and `P0` circuit-breaker data-loss regressions (`PR-01`) are **100% resolved** (**zero `P0` issues remain in the codebase**). Furthermore:
- **All 9 findings from `POST_REMEDIATION_AUDIT_2.md` (`PR2-01` through `PR2-09`) were addressed:**
  - `AppTracker.stopTracking()` and `performFullSweep()` now execute all `observers` and `knownWindowKeys` mutations strictly on `AXThread` (`PR2-01`).
  - `AppTracker` now aborts immediately on per-window `fetchWindowAttributesBatch()` timeouts without falling through to 7 sequential IPC calls, and preserves `knownWindowKeys` for backed-off PIDs (`PR2-03`).
  - `SettingsStore.reloadActiveTheme()` now properly updates `currentTheme`, custom theme metrics, and persistence when reloading themes from disk (`PR2-04`).
  - `DockController` now serializes `captureOriginalStateIfFirstRun()` and `sentinelKey` writes on `dockQueue` (`PR2-05`).
  - `WorkAreaEnforcer` now wraps test inspection properties in `syncOnAXThread` and intelligently gates Pass 1 / Pass 2 via `shouldContinueSettle(element:isResize:didClamp:)` (`PR2-07` & Regression 1).
  - `AppEnvironment.init` defaults to `AXThreadScheduler()`, `GroupWindowPopup.updateGroup` clamps horizontal X bounds, and `TaskbarPanel` dead methods were removed (`PR2-08`, `PR2-09`).

- **However, the fixes in `ad6d88d` for Regressions 2 & 3 (multi-monitor window focus & active button highlight sync) and `ScreenManager.updateWindows()` introduced 5 high-priority (`P1`) logic flaws (`PR3-01` through `PR3-05`):**
  1. **Background apps hijack `frontmostPID` & active window focus (`PR3-01`):** In `AppTracker`, `kAXWindowCreatedNotification` checks `if (isMain || isFront) && !isMin` (`L474`) and Tier 1 checks `if isMain && !isMin` (`L381, 389`) before calling `store.setFocusedWindow(key: key)`. Because `kAXMainAttribute` (`isMain`) is per-process (every single-window background app has `isMain == true`), **any background app opening a window, changing a tab title, or moving a window steals the active taskbar highlight away from the user's current app!**
  2. **`PrivateAPI.activateSingleWindow` is immediately undone when switching apps (`PR3-02`):** In `WindowActions.focusWindow` (`L62-68`) and `restoreAndFocusWindow` (`L107-110, 133-136`), right after `let activated = activateSingleWindow(key: key)`, the code checks `if !activated || (app != nil && !app!.isActive)` and calls `app?.activate(options: [])`. Because `NSRunningApplication.isActive` updates asynchronously on a later run-loop turn, `app!.isActive` is **always `false`** at that line when switching from App A to App B — so `app?.activate(options: [])` always runs and raises **all windows** of App B across all monitors!
  3. **`WindowActions.frontmostWindowID(forPID:)` in `inspectApp` runs before window filtering (`PR3-03`):** `inspectApp` (`L786-791`) queries `frontmostWindowID(forPID:)` *before* fetching `kAXWindowsAttribute` or filtering via `WindowFilter.shouldInclude`. If an app has a layer-0 overlay/popover/helper window $>20\times 20$, `focusedKey` is set to that non-taskbar window ID, skipping the `isMain` check (`L887`) and then getting wiped to `nil` by `WindowStore.syncSnapshot` (`L205`).
  4. **`ScreenManager.updateWindows()` bypasses `store.windows(forScreenID:screens:)` (`PR3-04`):** Because `ScreenManager.updateWindows()` (`L273-277`) manually partitions `store.allWindows` instead of calling `store.windows(forScreenID:screens:)`, `WindowStore.lastScreens` is permanently empty (`[]`) in production — breaking per-screen `.app(bundleID)` order pruning and skipping per-window custom order sorting.
  5. **Incomplete focus state sync on `PinnedButton` click, `.minimize`, and "Restore", plus a vacuous test (`PR3-05`):** Clicking a `PinnedButton` or right-click "Restore" activates the window without calling `onFocusRequested` or updating `store.setFocusedWindow`; left-clicking to `.minimize` does not clear `store.setFocusedWindow(key: nil)`; and `testLaunchOrActivateAppPrioritizesTargetScreen` (`PinnedAppsIntegrationTests.swift:474-521`) tests a copy-pasted local variable instead of calling `launchOrActivateApp`.

---

## 2. Scorecard of `POST_REMEDIATION_AUDIT_2.md` & Regression Fixes

| Reference | Target Issue | Status | Verification Summary |
| :--- | :--- | :---: | :--- |
| **PR2-01** | Data races on `AppTracker.observers` (`stopTracking`) & `knownWindowKeys` (`sweepNextChunk`) | **FIXED** | Both `stopTracking()` (`L918-925`) and `performFullSweep()` (`L636-646`) now hop to `AXThread.shared.async` before touching `observers` or `knownWindowKeys`. *(Minor: `preservedKeys` at `L659` can also filter `allActivePIDs.contains($0.pid)` — see `PR3-07`).* |
| **PR2-02** | Windowless running apps lose running dot & `TaskbarView` drops `runningBundleIDs` | **FIXED** | `ScreenManager.computeRunningBundleIDs()` unions `store.allWindows` with regular `NSWorkspace` apps, and `TaskbarView` persists `currentRunningBundleIDs`. *(See `PR3-07` to cache the `NSWorkspace` set instead of querying on every window event).* |
| **PR2-03** | Per-window `fetchWindowAttributesBatch()` timeouts fall through to 7 IPCs & `knownWindowKeys` wipe | **FIXED** | `handleNotificationEvent` (`L303`), `kAXWindowCreatedNotification` (`L415`), and `inspectApp` (`L819`) now `return` immediately after recording a timeout, and `sweepNextChunk` (`L659`) preserves `knownWindowKeys` for skipped PIDs. |
| **PR2-04** | "Reload Custom Themes" in `AppDelegate` bypasses `SettingsStore` | **FIXED** | Added `SettingsStore.reloadActiveTheme()` (`SettingsStore.swift:50-65`) and wired it in `AppDelegate.swift:70`. |
| **PR2-05** | `DockController` race between `captureOriginalStateIfFirstRun()` and `dockQueue` | **FIXED** | `hideDock()` and `restoreDock()` now serialize `captureOriginalStateIfFirstRun()` and `sentinelKey` mutations on `dockQueue`. |
| **PR2-06** | `ScreenManager.refreshFullScreenDetection()` queries WindowServer per monitor | **MOSTLY FIXED** | `CGWindowListCopyWindowInfo` is now called once outside the screen loop (`ScreenManager.swift:182`). *(Minor: still only runs at $t = 0\text{ms}$ on Space change — see `PR3-08`).* |
| **PR2-07** | Redundant `observeWindow` on drag & `WorkAreaEnforcer` pass gating / `syncOnAXThread` | **FIXED** | Removed `observeWindow` from move/resize in `AXAppObserver`, added `shouldContinueSettle` (`WorkAreaEnforcer.swift:376-393`), and wrapped test getters in `syncOnAXThread`. |
| **PR2-08** | `AppDelegate` `dockService`, `AppEnvironment.init` scheduler, `GroupWindowPopup` X clamp | **MOSTLY FIXED** | Fixed in `AppEnvironment.swift:573`, `GroupWindowPopup.swift:145-153`, and `AppDelegate.swift:127-129`. *(Minor: `AppDelegate.swift:33` still calls `DockController.shared.reconcileOnLaunch` directly — see `PR3-08`).* |
| **PR2-09** | Dead `TaskbarPanel` methods, duplicate theme block in `ScreenManager`, doc drift | **FIXED** | Removed dead methods and duplicate block; synced `docs/` and `README.md`. |
| **Regression 1** | Maximize animation flicker / failure to clamp at settle | **FIXED** | `shouldContinueSettle` (`WorkAreaEnforcer.swift:336, 376-393`) and `maxNudgeAttempts = 4` cleanly handle 200–300ms zoom animations. |
| **Regression 2** | Multi-monitor window activation raises wrong monitor or all windows | **PARTIAL** | Fixed `PrivateAPI` call order (`_SLPSSetFrontProcessWithOptions` before `SetFrontProcessWithOptions`), **but defeated when switching apps by `if !activated \|\| !app!.isActive` (`PR3-02`) and missing `onFocusRequested` on `PinnedButton` (`PR3-05`)**. |
| **Regression 3** | Double-click required & stuck active button highlights | **PARTIAL** | Fixed `ClickPolicy` (`Removed \|\| focusedKey == nil`) and sibling button reset, **but introduced background-app focus hijacking via `isMain` (`PR3-01`) and pre-filter `frontmostWindowID` (`PR3-03`)**. |

---

## 3. Master Priority & Complexity Ranking (`PR3-01` $\to$ `PR3-08`)

| ID | Priority | Category | Title | Primary Locations | Complexity |
| :--- | :---: | :--- | :--- | :--- | :---: |
| **PR3-01** | **P1** | Correctness / Focus | Background apps hijack `frontmostPID` & active taskbar highlight because `isMain` is per-process, not system-wide | `AppTracker.swift:381-383, 389-391, 473-477` | **XS** |
| **PR3-02** | **P1** | Correctness / Focus | `if !activated \|\| (app != nil && !app!.isActive)` in `WindowActions` immediately calls `app?.activate(options: [])`, defeating `PrivateAPI.activateSingleWindow` when switching apps | `WindowActions.swift:62-68, 107-110, 133-136` | **XS** |
| **PR3-03** | **P1** | Correctness / Perf | `AppTracker.inspectApp` calls `WindowActions.frontmostWindowID(forPID:)` before fetching/filtering `appWindows`, risking phantom `focusedKey` & unnecessary WindowServer IPC | `AppTracker.swift:786-791, 887-889` | **XS** |
| **PR3-04** | **P1** | Correctness / Order | `ScreenManager.updateWindows()` bypasses `store.windows(forScreenID:screens:)`, leaving `WindowStore.lastScreens` empty and skipping per-screen custom order sorting & pruning | `ScreenManager.swift:273-277`, `WindowStore.swift:268-302` | **S** |
| **PR3-05** | **P1** | Correctness / Tests | Missing focus sync on `PinnedButton` click, left-click `.minimize`, and right-click "Restore", plus vacuous `testLaunchOrActivateAppPrioritizesTargetScreen` | `TaskbarView.swift:257-301, 390-398`, `WindowActions.swift:191-197`, `PinnedAppsIntegrationTests.swift:474-521` | **S** |
| **PR3-06** | **P2** | Correctness / AX | `AppTracker.reconcileDirtyPIDs()` clears `focusedWindowKey` when `frontmostPID` is backed off or times out | `AppTracker.swift:578-582` | **XS** |
| **PR3-07** | **P2** | Performance / AX | Uncached `NSWorkspace.shared.runningApplications` on every `updateWindows()`, duplicate launch/terminate observers in `ScreenManager`, and duplicate `win.windowID` IPC in `inspectApp` | `ScreenManager.swift:33-44, 128-135, 271`, `AppTracker.swift:659, 810, 861` | **XS** |
| **PR3-08** | **P2** | Polish / Hygiene | Minor leftovers: `AppDelegate` direct `DockController.shared.reconcileOnLaunch` & dead `applyTheme` extension, `ScreenManager` Space-settle fullscreen check, and 2 doc typos | `AppDelegate.swift:33, 136-142`, `ScreenManager.swift:167-170, 285`, `docs/ARCHITECTURE.md:306, 349` | **XS** |

---

## 4. Detailed Findings & Concise Remediation Feedback

---

### `PR3-01` [P1 | Complexity: XS] — Background Apps Hijack `frontmostPID` & Active Button Highlight Because `isMain` Is Per-Process, Not System-Wide

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:473-477` (`kAXWindowCreatedNotification`)
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:381-383, 389-391` (`handleNotificationEvent` Tier 1)
- **The Problem:**
  1. In macOS Accessibility, `kAXMainAttribute` (`isMain`) indicates whether a window is the **main window of its own application process** — almost every single-window background application has `isMain == true` even when inactive!
  2. In `kAXWindowCreatedNotification` (`AppTracker.swift:473-477`), commit `ad6d88d` added:
     ```swift
     let isFront = (event.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier)
     if (isMain || isFront) && !isMin {
         self.store.setFrontmostPID(event.pid)
         self.store.setFocusedWindow(key: key)
     }
     ```
     Because the condition uses `(isMain || isFront)`, whenever **any background application** creates a normal window (where `isMain == true`), `AppTracker` overwrites `self.store.setFrontmostPID(event.pid)` and `self.store.setFocusedWindow(key: key)` — hijacking the active taskbar button highlight away from the user's actual frontmost application!
  3. Similarly, in Tier 1 `handleNotificationEvent` (`AppTracker.swift:381-383` and `389-391`):
     ```swift
     if isMain && !isMin {
         self.store.setFocusedWindow(key: key)
     }
     ```
     Whenever **any background application** emits `kAXTitleChangedNotification` (e.g. a background browser tab, Slack message, or Terminal window updating its title) or moves/resizes its main window (`isMain == true`), Tier 1 unconditionally overwrites `self.store.setFocusedWindow(key: key)` without checking `event.pid == self.store.frontmostPID`! This steals `focusedWindowKey` away from the real active window and breaks click-to-minimize on the active window.
- **How to Fix:**
  - In `kAXWindowCreatedNotification` (`L474`), require `isFront`:
    ```swift
    if isFront && !isMin {
        self.store.setFrontmostPID(event.pid)
        self.store.setFocusedWindow(key: key)
    }
    ```
  - In Tier 1 `handleNotificationEvent` (`L381` and `L389`), guard on `event.pid == self.store.frontmostPID`:
    ```swift
    if isMain && !isMin && event.pid == self.store.frontmostPID {
        self.store.setFocusedWindow(key: key)
    }
    ```

---

### `PR3-02` [P1 | Complexity: XS] — `if !activated || (app != nil && !app!.isActive)` in `WindowActions` Immediately Calls `app?.activate(options: [])`, Undoing `PrivateAPI.activateSingleWindow` When Switching Apps

- **Locations:**
  - `Sources/TaskbarKit/Actions/WindowActions.swift:62-68` (`focusWindow`)
  - `Sources/TaskbarKit/Actions/WindowActions.swift:105-111, 131-137` (`restoreAndFocusWindow`)
- **The Problem:**
  - To fix Regression 2 (where clicking a Chrome window on Monitor 2 also raised Chrome's window on Monitor 1), `PrivateAPI.activateSingleWindow` was updated to call `_SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200)` followed by `SetFrontProcessWithOptions(&psn, 1)` (`kSetFrontProcessFrontWindowOnly`).
  - However, in `WindowActions.focusWindow` (`L62-68`):
    ```swift
    let activated = activateSingleWindow(key: key)
    let app = NSRunningApplication(processIdentifier: key.pid)
    if !activated || (app != nil && !app!.isActive) {
        app?.activate(options: [])
    }
    ```
    (and identically in `restoreAndFocusWindow` at `L108` and `L134`).
  - `NSRunningApplication.isActive` is an AppKit property updated asynchronously via WindowServer/Workspace notifications on the main run loop — it is **never** updated synchronously within the same microsecond that `SetFrontProcessWithOptions` returns!
  - Consequently, whenever the user is in App A (e.g. Terminal) and clicks a Chrome window on Monitor 2, `app!.isActive` is guaranteed to be `false` at line 66! The `if` condition evaluates to `true` and immediately calls `app?.activate(options: [])`, which on macOS 14+ activates **all windows** of Chrome across all monitors — completely defeating `activateSingleWindow` whenever switching applications!
- **How to Fix:**
  - Only fall back to `app?.activate(options: [])` when `!activated` (i.e. when `activateSingleWindow(key:)` returned `false`):
    ```swift
    let activated = activateSingleWindow(key: key)
    if !activated {
        NSRunningApplication(processIdentifier: key.pid)?.activate(options: [])
    }
    ```

---

### `PR3-03` [P1 | Complexity: XS] — `AppTracker.inspectApp` Calls `WindowActions.frontmostWindowID(forPID:)` Before Fetching/Filtering `appWindows`, Risking a Phantom `focusedKey` & Unnecessary WindowServer IPC

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:786-791, 887-889`
  - `Sources/TaskbarKit/Actions/WindowActions.swift:35-51`
- **The Problem:**
  - In `AppTracker.inspectApp(app:isFrontmost:)` (`L786-791`), commit `ad6d88d` added a fallback to `WindowActions.frontmostWindowID(forPID: pid)` **before** `kAXWindowsAttribute` is fetched (`L795`) and **before** `WindowFilter.shouldInclude` filters the app's windows (`L850-859`).
  - This causes two issues:
    1. **Phantom `focusedKey` & bypassed `isMain` check:** `WindowActions.frontmostWindowID(forPID:)` returns the first on-screen layer-0 `CGWindowID` with bounds $>20\times 20$. If the frontmost app has a layer-0 popover, tooltip, completion overlay, or floating helper window $>20\times 20$ that `WindowFilter.shouldInclude` excludes from `appWindows`, `focusedKey` is set to that non-taskbar window at `L789`. Then:
       - At `L887`, `if isFrontmost && focusedKey == nil && isMain` is **skipped** because `focusedKey` is already non-nil!
       - When `reconcileDirtyPIDs` or `finishFullSweep` runs `store.syncSnapshot(forPID: pid, currentWindows: wins)` (`WindowStore.swift:205`), `if let focused = focusedWindowKey, windows[focused] == nil { focusedWindowKey = nil }` immediately wipes `focusedWindowKey` to `nil` because the phantom window ID is not in `WindowStore`!
    2. **Unnecessary WindowServer IPC:** Running `CGWindowListCopyWindowInfo` at `L787` *before* checking `isMain` (`L887`) or whether `appWindows` is even non-empty fires a full-system WindowServer query even when `isMain` would have resolved the focused window without any WindowServer IPC, or when the frontmost app has 0 open windows.
- **How to Fix:**
  - Move the `WindowActions.frontmostWindowID(forPID: pid)` fallback to **after** the `for win in windowElements` loop (`after L890`), so it only executes when `isFrontmost && focusedKey == nil && !appWindows.isEmpty`, and filter candidates to IDs present in `appWindows` (`let trackedIDs = Set(appWindows.map { UInt32($0.key.id) })`).

---

### `PR3-04` [P1 | Complexity: S] — `ScreenManager.updateWindows()` Bypasses `store.windows(forScreenID:screens:)`, Leaving `WindowStore.lastScreens` Empty and Skipping Per-Screen Custom Order Sorting & Pruning

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:273-285`
  - `Sources/TaskbarCore/Logic/WindowStore.swift:52-80, 92-120, 209-239, 268-302`
- **The Problem:**
  - In `ScreenManager.updateWindows()` (`L273-277`), windows are partitioned across screens by manually looping over `store.allWindows`:
    ```swift
    var windowsByScreen: [UInt32: [WindowInfo]] = [:]
    for win in store.allWindows {
        let assignedScreen = ScreenAssignment.assignScreen(for: win.frame, across: descriptors) ?? ...
        windowsByScreen[assignedScreen, default: []].append(win)
    }
    ```
  - As a result, `store.windows(forScreenID: UInt32(displayID), screens: descriptors)` (`WindowStore.swift:268-302`) has **zero callers in production (`Sources/`)**!
  - Bypassing `store.windows(forScreenID:screens:)` breaks three things:
    1. **`WindowStore.lastScreens` is permanently `[]` in production (`WindowStore.swift:13, 269`):** Because `windows(forScreenID:screens:)` is the only method that sets `self.lastScreens = screens`, `removeWindow(key:)`, `removeWindows(forPID:)`, and `syncSnapshot(forPID:currentWindows:)` always take the `else` branch (`lastScreens.isEmpty`), defeating the `PR-15` fix for per-screen `.app(bundleID)` order pruning!
    2. **`pruneCustomOrder(forScreenID:activeKeys:activeBundleIDs:)` is never called when windows move between monitors (`WindowStore.swift:275`).**
    3. **Per-window custom order sorting in `WindowStore.windows(forScreenID:screens:)` (`L282-301`) is never applied.**
- **How to Fix:**
  - In `ScreenManager.updateWindows()`, obtain `let screenWindows = store.windows(forScreenID: UInt32(displayID), screens: descriptors)` for each panel (or add a single-pass `store.windowsByScreen(screens: descriptors)` method on `WindowStore` that updates `lastScreens`, prunes custom orders per screen, and returns the sorted per-screen window arrays).

---

### `PR3-05` [P1 | Complexity: S] — Missing Focus State Sync on `PinnedButton` Click, Left-Click `.minimize`, and Right-Click "Restore", Plus Vacuous `testLaunchOrActivateAppPrioritizesTargetScreen`

- **Locations:**
  - `Sources/TaskbarKit/UI/Panels/TaskbarView.swift:257-301, 390-398`
  - `Sources/TaskbarKit/Actions/WindowActions.swift:170-204`
  - `Tests/TaskbarIntegrationTests/PinnedAppsIntegrationTests.swift:474-521`
- **The Problem:**
  1. **Clicking a `PinnedButton` does not sync focus state across panels (`TaskbarView.swift:390-398`, `WindowActions.swift:191-197`):** When a user clicks a `PinnedButton` for a running app on Monitor 2, `launchOrActivateApp` calls `focusWindow(targetWindow.key)` or `restoreAndFocusWindow(targetWindow.key)`, but **never** calls `store.setFrontmostPID(targetWindow.pid)`, `store.setFocusedWindow(key: targetWindow.key)`, or `self.onFocusRequested?(targetWindow.key)`. For Chromium/Electron apps (or when switching between two windows of an already-active app via its pinned button), the taskbar active highlight does not move to Monitor 2!
  2. **Left-clicking a `TaskButton` to `.minimize` does not update `store` (`TaskbarView.swift:296-301`):** In `case .minimize:`, `TaskbarView` sets `btn.isFocusedWindow = false` and `self.focusedKey = nil`, but never calls `self.store?.setFocusedWindow(key: nil)`. If `ScreenManager.updateWindows()` runs before the AX minimize notification arrives, it reads the old `store.focusedWindowKey` and re-highlights the button.
  3. **Right-click "Restore" (`TaskbarView.swift:261-263, 271`) does not call `onFocusRequested`:** Restoring a minimized window via the context menu calls `restoreAndFocusWindow` without updating `onFocusRequested`.
  4. **Vacuous Test (`PinnedAppsIntegrationTests.swift:474-521`):** `testLaunchOrActivateAppPrioritizesTargetScreen` never calls `launchOrActivateApp`, `SpyWindowActions`, `TaskbarView`, or `PinnedButton` — it copy-pastes the `let matching = preferredWindows.filter ...` logic inline into the test and asserts on its own local variable!
- **How to Fix:**
  - In `WindowActions.launchOrActivateApp` (`L191-197`), update `store.setFrontmostPID(targetWindow.pid)` and `store.setFocusedWindow(key: targetWindow.key)`, and in `TaskbarView`'s `PinnedButton.onClick` (`L390-398`) and `TaskButton.onMinimizeOrRestore` restore path (`L261-271`), trigger `onFocusRequested` / `ScreenManager.updateWindows()`.
  - In `TaskbarView` `case .minimize:` (`L296-301`), call `self.store?.setFocusedWindow(key: nil)`.
  - Update `testLaunchOrActivateAppPrioritizesTargetScreen` in `PinnedAppsIntegrationTests.swift` to invoke `PinnedButton.onClick` on a `TaskbarView` with `SpyWindowActions` and assert that `spyActions.invocations` records `.launchOrActivateApp` with `preferredWindows` from that screen.

---

### `PR3-06` [P2 | Complexity: XS] — `AppTracker.reconcileDirtyPIDs()` Clears `focusedWindowKey` When `frontmostPID` Is Backed Off or Times Out

- **Location:** `Sources/TaskbarKit/Tracking/AppTracker.swift:578-582`
- **The Problem:**
  - Unlike `finishFullSweep` (`L731-740`, which checks `else if !isFrontmostBackedOff`), `reconcileDirtyPIDs()` (`L578-582`) writes:
    ```swift
    } else if let frontmostPID = frontmostPID, validPIDs.contains(frontmostPID) {
        if self.store.setFocusedWindow(key: nil) {
            didChange = true
        }
    }
    ```
  - If `frontmostPID` is in `validPIDs` and was skipped due to `AppTracker.isPIDBackedOff(pid)` (`L549`) or timed out inside `inspectApp` (`L555`), `focusedKey` is `nil`, and `reconcileDirtyPIDs()` wipes `store.setFocusedWindow(key: nil)`.
- **How to Fix:**
  - Add `, !AppTracker.isPIDBackedOff(frontmostPID)` to line 578.

---

### `PR3-07` [P2 | Complexity: XS] — Uncached `NSWorkspace.shared.runningApplications` on Every `updateWindows()`, Duplicate Launch/Terminate Observers in `ScreenManager`, and Duplicate `win.windowID` IPC in `inspectApp`

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:33-44, 128-135, 172-174, 271`
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:659, 810, 861`
- **The Problem:**
  1. `ScreenManager.computeRunningBundleIDs()` (`L128-135`) queries `NSWorkspace.shared.runningApplications` on every single `updateWindows()` call (`L271` — every focus change, title change, or window open/close), and `ScreenManager` registers duplicate `didLaunchApplicationNotification` / `didTerminateApplicationNotification` observers (`L33-44`) alongside `AppTracker`.
  2. In `AppTracker.inspectApp` (`L810` and `L861`), `win.windowID` (`_AXUIElementGetWindow` IPC) is called twice per window inside the `for win in windowElements` loop.
  3. In `AppTracker.sweepNextChunk` (`L659`), `let preservedKeys = self.knownWindowKeys.filter { !accumulatedWindows.keys.contains($0.pid) }` does not filter by `allActivePIDs.contains($0.pid)`.
- **How to Fix:**
  - Cache `private var workspaceRunningBundleIDs: Set<String>` on `ScreenManager` (refreshed only in `init` and `handleApplicationLifecycleChanged`), and union it with `store.allWindows.map(\.bundleID)` in `computeRunningBundleIDs()`.
  - Bind `guard let wid = win.windowID else { continue }` once at the top of the `for win in windowElements` loop in `AppTracker.inspectApp`.
  - Add `&& allActivePIDs.contains($0.pid)` to `preservedKeys` at `AppTracker.swift:659`.

---

### `PR3-08` [P2 | Complexity: XS] — Minor Leftovers in `AppDelegate`, `ScreenManager` Space-Settle Fullscreen Check, and Docs

- **Locations:**
  - `Sources/TaskbarKit/AppDelegate.swift:33, 136-142`
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:167-170, 268-310`
  - `docs/ARCHITECTURE.md:306-310, 349`, `docs/TESTING.md:54, 73`
- **The Problem:**
  1. `AppDelegate.swift:33` still calls `DockController.shared.reconcileOnLaunch(...)` directly instead of `AppEnvironment.current.dockService.reconcileOnLaunch(...)`, and `AppDelegate.swift:136-142` retains an unused `extension ScreenManager { public func applyTheme(...) }` shim.
  2. `ScreenManager.handleActiveSpaceChanged()` (`L167-170`) only runs `refreshFullScreenDetection()` once at $t = 0\text{ms}$ when the Space transition begins, and does not refresh `cachedFullScreenDisplayIDs` when `AppTracker`'s Space-settle sweeps (`50ms` / `350ms`) call `updateWindows()`.
  3. `docs/ARCHITECTURE.md:349` has a minor typo (`"win_<pid>_<id>"` instead of `"window_<pid>_<id>"`), and `docs/TESTING.md:54, 73` / `README.md:88, 124` state `236` tests (`112` integration) whereas the suite now has **237** tests (`113` integration, after adding `TC-DOCK-008`).
- **How to Fix:**
  - Route `reconcileOnLaunch` through `AppEnvironment.current.dockService`, delete the dead `applyTheme` extension in `AppDelegate.swift`, refresh fullscreen detection on Space-settle updates, and update the 2 doc strings.
