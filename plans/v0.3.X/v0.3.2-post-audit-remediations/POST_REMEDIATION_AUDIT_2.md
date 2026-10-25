# Taskbar — Second Post-Remediation Codebase Audit (`POST_REMEDIATION_AUDIT_2`)

**Date:** 2026-10-17  
**Commits Audited:** `975adc3` (`refactor: post-remediation pass 1`) & `81fc411` (`refactor: post-remediation pass 2`) — 37 files changed, +1,245 / -496 lines since `7c73e0b`  
**Scope:** Verification of all 16 findings (`PR-01` through `PR-16`) from [`POST_REMEDIATION_AUDIT.md`](./POST_REMEDIATION_AUDIT.md), plus a deep audit of the updated codebase for newly introduced regressions, race conditions, edge cases, and remaining hygiene gaps.

---

## 1. Executive Summary

Gemini 3.8 executed the two-pass follow-up plan in commits `975adc3` and `81fc411`, touching 37 files and adding new tests across `AXEventRouterAndCircuitBreakerTests`, `DeterministicLifecycleTests`, `DockControllerTests`, and `WorkAreaEnforcerTests`.

- **What was cleanly resolved in Pass 1 & Pass 2:**
  - **Batch AX attribute unpacking (`PR-04`):** `AXElement.fetchWindowAttributesBatch()` now returns `nil` if `role == nil`, and all three inspection sites in `AppTracker` branch on `if let batch = batch` without firing individual fallback AX IPC calls when optional attributes (`subrole`, `title`) are `nil`.
  - **Popup vertical anchor (`PR-06`):** `GroupWindowPopup` no longer subtracts `heightDelta` from `newFrame.origin.y`, keeping the popup anchored above the taskbar when windows open or close.
  - **Zero-alloc rendering & icon rasterization (`PR-07`):** `IconCache.icon(for:pid:size:)` now calls `Self.rasterize(...)`, `TaskButton` passes `theme.iconSize` and `theme: resolved`, all buttons use `BevelDrawing.draw...(in:theme: resolved)`, and `ResolvedTheme.startButtonPreferredWidth` respects `theme.fontBold`.
  - **`StatusMenu` dead code purge & Dock restore deduplication (`PR-05` / `PR-16`):** Removed 10 mirrored state properties and 11 dead `update*` methods from `StatusMenu`, wired `old.dockHideDelay != new.dockHideDelay` in `AppDelegate`, and fixed the double `killall Dock` on "Restore System Dock".
  - **Multi-monitor `.app(bundleID)` order pruning & bundle-less PID fallback (`PR-15`):** `WindowStore` now prunes `.app(bundleID)` per-screen using `lastScreens`, `WindowOrderingLogic.rebuildOrderMap` preserves the first window's index (`if map[.app(item.bundleID)] == nil`), and `WindowInfo.init` normalizes empty `bundleID` to `"pid:\(pid)"`.
  - **`TaskbarView` DI wiring & `DeterministicLifecycleTests` (`PR-09`):** `TaskbarView` now routes all 14 window actions through `AppEnvironment.current.windowActions`, `AppEnvironment.live.scheduler` is `AXThreadScheduler()`, and `DeterministicLifecycleTests` exercises real `TaskbarView` / `TaskButton` callbacks.
  - **CI test runner (`PR-10`):** `scripts/test-functional.sh` now runs the entire test suite in `--all` and `--coverage` modes without skipping the 7 new suites or blocking headless runs on Accessibility permissions.

- **What went wrong or remains incomplete (9 findings: `PR2-01` through `PR2-09`):**
  1. **`P0` Cross-Thread Data Races Introduced in `AppTracker` (`PR2-01`):**
     - In `stopTracking()` (`@MainActor`, `AppTracker.swift:878-879`), Pass 2 added `let currentObservers = Array(self.observers.values); self.observers.removeAll()` **directly on `@MainActor`** before dispatching to `AXThread`, creating a concurrent read/write data race on the `AXThread`-confined `observers` dictionary.
     - In `performFullSweep()` (`@MainActor`, `AppTracker.swift:614, 632-633`), `sweepNextChunk` is invoked synchronously on `@MainActor` before hopping to `AXThread`; when `remainingApps.isEmpty`, `self.knownWindowKeys = ...` (`L633`) mutates `AXThread`-confined `knownWindowKeys` on `@MainActor`.
  2. **`P1` Regression in Pinned App Running State (`PR2-02`):**
     - Removing `NSRunningApplication.runningApplications(withBundleIdentifier:)` from `TaskbarView.isAppRunning` while `ScreenManager` computes `runningBundleIDs` solely from `store.allWindows` broke running detection for **all running apps with 0 open windows** (e.g. Finder, Safari, Terminal, Music with closed windows lose their running dot and right-click "Quit" option).
     - Worse, `TaskbarView.apply(settings:theme:)` (`L415`) and `flushPendingWindowUpdate()` (`L512`) call `updatePinnedApps` / `updateWindows` with `runningBundleIDs: nil`, which falls back to single-display `currentWindows` and clobbers multi-monitor running dots after any settings change or drag!
  3. **`P1` Incomplete Per-Window Timeout Handling & `knownWindowKeys` Wipe (`PR2-03`):**
     - In `handleNotificationEvent` (`AppTracker.swift:301-303`), when `fetchWindowAttributesBatch()` times out, it calls `AppTracker.recordTimeout(for: event.pid)` **but does not `return`**—immediately entering the `else` branch (`L326-334`) and stalling `AXThread` across 7 sequential AX IPC calls on the same hung window. `inspectApp` (`L781-809`) has the same fallback stall and never measures per-window elapsed time.
     - At the end of `sweepNextChunk` (`L633`), `self.knownWindowKeys = Set(accumulatedWindows.values.flatMap { $0 }.map(\.key))` overwrites `knownWindowKeys` without preserving keys for backed-off PIDs, causing `WorkAreaEnforcer` to re-trigger on all existing windows of a backed-off app once its 5s backoff expires.
  4. **`P1` Incomplete "Reload Custom Themes" Fix (`PR2-04`):**
     - `AppDelegate` (`L67-74`) reloads custom themes and calls `screenManager?.applyTheme(resolvedTheme)` directly, bypassing `SettingsStore`. `settingsStore.currentTheme` and custom theme metrics (`barHeight`, `minButtonWidth`, etc.) in `settingsStore.settings` remain stale.

---

## 2. Scorecard of `POST_REMEDIATION_AUDIT.md` (`PR-01` $\to$ `PR-16`) Execution

| Original ID | Original Title | Status | Verification Summary |
| :--- | :--- | :---: | :--- |
| **PR-01** | Circuit breaker wipes windows of timed-out app | **PARTIAL** | `inspectApp` now returns `([WindowInfo]?, WindowKey?)` and preserves windows in `WindowStore` when `kAXWindowsAttribute` / `kAXFocusedWindowAttribute` returns `.cannotComplete`. **Missed:** per-window `fetchWindowAttributesBatch()` timeouts still fall through to 7 sequential IPC calls (`L301-334`, `L781-809`), and `sweepNextChunk` (`L633`) wipes `knownWindowKeys` for backed-off PIDs (**`PR2-03`**). |
| **PR-02** | 60–120Hz drag flood, duplicate `WorkAreaEnforcer`, `syncSnapshot` frame check | **MOSTLY FIXED** | Removed duplicate `WorkAreaEnforcer` call in `AXAppObserver`, added `prev.frame != current.frame` to `WindowStore.syncSnapshot`, and gated `onWindowsChanged?()` on move/resize. **Missed:** `AXAppObserver` (`L225-229`) still calls `observeWindow(element)` on every 60–120Hz move/resize event (**`PR2-07`**). |
| **PR-03** | Data races on `knownWindowKeys` & `currentSweepGeneration` | **NEW RACE** | Added `sweepGenerationLock` and moved most `knownWindowKeys` mutations to `AXThread`, but `sweepNextChunk` (`L614, 633`) still mutates `knownWindowKeys` on `@MainActor` when `remainingApps.isEmpty` (**`PR2-01`**). |
| **PR-04** | Unconditional IPC fallback when optional batch attributes are `nil` | **FIXED** | `fetchWindowAttributesBatch()` returns `nil` when `role == nil`, and `AppTracker` branches cleanly on `if let batch = batch`. |
| **PR-05** | Broken `StatusMenu` actions ("Reload Custom Themes", "Dock Delay", double restore) | **PARTIAL** | Fixed Dock delay subscription and double `killall Dock` on restore. **Missed:** "Reload Custom Themes" (`AppDelegate.swift:67-74`) bypasses `SettingsStore`, leaving `settingsStore.currentTheme` and custom theme metrics stale (**`PR2-04`**). |
| **PR-06** | `GroupWindowPopup` inverted Y-origin math on live update | **MOSTLY FIXED** | Removed `newFrame.origin.y -= heightDelta` in `updateGroup` and `handleCloseWindow`. **Minor gap:** `updateGroup` does not clamp `newFrame.origin.x` to the screen's right edge when `preferredSize.width` grows (**`PR2-08`**). |
| **PR-07** | Dead `IconCache.rasterize`, missing `theme.iconSize`, unwired `BevelDrawing(theme:)` | **FIXED** | Wired `IconCache.rasterize`, `theme.iconSize`, `BevelDrawing(in:theme: resolved)`, and `ResolvedTheme.startButtonPreferredWidth`. |
| **PR-08** | Redundant `updatePinnedApps`, LaunchServices IPC, unbuffered mid-drag pinned update | **REGRESSION** | Added mid-drag `pendingPinnedUpdate` and guarded `updatePinnedApps` in `ScreenManager.updateWindows()`. **Regression:** removing LaunchServices check while `ScreenManager` uses `store.allWindows` broke running indicators for all **windowless running apps**, and `apply(settings:theme:)` / `flushPendingWindowUpdate()` drop `runningBundleIDs` (**`PR2-02`**). |
| **PR-09** | Unwired `AppEnvironment` DI seams, `MainScheduler`, self-mocking lifecycle tests | **MOSTLY FIXED** | Wired `AppEnvironment.current.windowActions` in `TaskbarView`, set `live.scheduler = AXThreadScheduler()`, and rewrote `DeterministicLifecycleTests`. **Minor gaps:** `AppDelegate` still calls `DockController.shared` directly and `AppEnvironment.init` defaults `scheduler` to `MainScheduler()` (**`PR2-08`**). |
| **PR-10** | `scripts/test-functional.sh` omits 7 new test suites | **FIXED** | `--all` and `--coverage` modes now run all suites via `swift test` and do not block headless runs on AX permission. |
| **PR-11** | `ScreenManager.cachedFullScreenDisplayIDs` stuck after Space switch | **PARTIAL** | Added `activeSpaceDidChangeNotification` observer. **Gaps:** `refreshFullScreenDetection()` calls `CGWindowListCopyWindowInfo` once per monitor instead of once total, and `updateWindows()` does not refresh `cachedFullScreenDisplayIDs` when `AppTracker`'s Space-settle sweeps finish (**`PR2-06`**). |
| **PR-12** | `WorkAreaEnforcer` unconditional 3-pass chain, off-main `NSScreen`, `.info` log spam | **MOSTLY FIXED** | Removed off-main `NSScreen.screens`, downgraded logs to `.debug`, and gated Pass 1/2 on moves (`guard didClamp0 || effectiveResize`). **Gap:** when `isResize == true`, `effectiveResize` is always `true`, so resizing a non-overlapping window still runs all 3 passes (**`PR2-07`**). |
| **PR-13** | `AppTracker.stopTracking()` leak, `observeWindow` lock across IPC, unpruned windows | **NEW RACE** | Fixed `observeWindow` lock scope and added `pruneWindows(keeping:)`. **Regression:** `stopTracking()` now reads and clears `self.observers` directly on `@MainActor` without synchronization (**`PR2-01`**). |
| **PR-14** | `DockController` stale baseline snapshot, `synchronize()`, unconditional restore | **NEW RACE** | Guarded `restoreDock()`, removed `synchronize()`, and removed `originalStateKey` in `performRestoreInternal()`. **Race:** `hideDock()` calls `captureOriginalStateIfFirstRun()` synchronously on the caller thread while `performRestoreInternal()` deletes `originalStateKey` asynchronously on `dockQueue` (**`PR2-05`**). |
| **PR-15** | Multi-monitor `.app` pruning, `.never` mode order overwrite, empty `bundleID` collision | **FIXED** | Fixed per-screen `.app` pruning in `WindowStore`, first-slot preservation in `WindowOrderingLogic`, and `"pid:\(pid)"` normalization in `WindowInfo.init`. |
| **PR-16** | Leftover shims in `StatusMenu`/`ScreenManager`, untrimmed theme IDs, doc drift | **MOSTLY FIXED** | Cleaned up `StatusMenu`, sanitized custom theme IDs in `ThemeFileLoader`/`ThemeRegistry`, and updated `docs/`. **Remaining:** duplicate theme metric code in `ScreenManager.updateTheme`, 2 dead methods in `TaskbarPanel`, and a few stale lines in `docs/` and `README.md` (**`PR2-09`**). |

---

## 3. Master Priority & Complexity Ranking (`PR2-01` $\to$ `PR2-09`)

| ID | Priority | Category | Title | Primary Locations | Complexity |
| :--- | :---: | :--- | :--- | :--- | :---: |
| **PR2-01** | **P0** | Concurrency / Crash | Cross-thread data races on `AppTracker.observers` in `stopTracking()` and `knownWindowKeys` in `sweepNextChunk` | `AppTracker.swift:614, 632-633, 878-892` | **XS** |
| **PR2-02** | **P1** | Correctness / UI | Windowless running apps lose running indicator & "Quit" menu, and settings/drag updates drop multi-monitor `runningBundleIDs` | `ScreenManager.swift:135, 211, 258`, `TaskbarView.swift:48, 110, 160-162, 343, 415, 418-420, 510-512` | **S** |
| **PR2-03** | **P1** | Correctness / AX | Per-window `fetchWindowAttributesBatch()` timeouts still fall back to 7 sequential IPCs, and `sweepNextChunk` wipes `knownWindowKeys` for backed-off PIDs | `AppTracker.swift:297-334, 408-439, 632-633, 781-809` | **XS** |
| **PR2-04** | **P1** | Correctness / Theme | "Reload Custom Themes" in `AppDelegate` bypasses `SettingsStore`, leaving `currentTheme` and custom theme metrics stale | `AppDelegate.swift:67-74`, `SettingsStore.swift:27-48` | **XS** |
| **PR2-05** | **P2** | Concurrency / System | Race condition in `DockController` between synchronous `captureOriginalStateIfFirstRun()` and async `dockQueue` removal of `originalStateKey` | `DockController.swift:152-191, 284` | **XS** |
| **PR2-06** | **P2** | Performance / UI | `ScreenManager.refreshFullScreenDetection()` calls `CGWindowListCopyWindowInfo` per monitor instead of once, and `updateWindows()` never refreshes it after Space-settle sweeps | `ScreenManager.swift:158-206, 255-297` | **XS** |
| **PR2-07** | **P2** | Performance / AX | Redundant `observeWindow(element)` on every 60–120Hz move/resize event and unconditional 3-pass `WorkAreaEnforcer` chain on non-overlapping resizes | `AXAppObserver.swift:225-229`, `WorkAreaEnforcer.swift:69-99, 312, 328` | **XS** |
| **PR2-08** | **P2** | Polish / DI / UI | `AppDelegate` bypasses `AppEnvironment.current.dockService`, `AppEnvironment.init` defaults to `MainScheduler`, and `GroupWindowPopup.updateGroup` omits right-edge X clamping | `AppDelegate.swift:129, 131`, `AppEnvironment.swift:573`, `GroupWindowPopup.swift:139-145` | **XS** |
| **PR2-09** | **P2** | Hygiene / Docs | Duplicate theme metric block in `ScreenManager.updateTheme`, 2 dead methods in `TaskbarPanel`, and remaining stale lines in `docs/` & `README.md` | `ScreenManager.swift:81-102`, `TaskbarPanel.swift:103-118`, `docs/`, `README.md` | **XS** |

---

## 4. Detailed Findings & Concise Remediation Feedback

---

### `PR2-01` [P0 | Complexity: XS] — Cross-Thread Data Races on `AppTracker.observers` in `stopTracking()` and `knownWindowKeys` in `sweepNextChunk`

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:90, 110, 614, 632-633, 878-892`
- **The Problem:**
  1. **`self.observers` mutated on `@MainActor` in `stopTracking()` (`L878-879`):** `self.observers: [pid_t: AXAppObserver]` is confined to `AXThread` (read and mutated without locks on `AXThread` in `trackApp`, `untrackApp`, `finishFullSweep`, and `inspectApp`). To avoid the `[weak self]` deallocation leak from `PR-13`, Pass 2 added:
     ```swift
     let currentObservers = Array(self.observers.values)
     self.observers.removeAll()
     ```
     directly on `@MainActor` inside `stopTracking()`, while `AXThread` may be concurrently reading or mutating `self.observers` (`EXC_BAD_ACCESS` heap corruption hazard).
  2. **`self.knownWindowKeys` mutated on `@MainActor` in `sweepNextChunk` (`L614, 632-633`):** `performFullSweep()` runs on `@MainActor` and calls `sweepNextChunk(remainingApps: runningApps, ...)` synchronously before the first `AXThread.shared.async` hop (`L650`). If `remainingApps.isEmpty` on the initial call, `sweepNextChunk` executes `self.knownWindowKeys = Set(...)` (`L633`) **on `@MainActor`**, racing with `AXThread` readers/writers of `knownWindowKeys`.
- **How to Fix:**
  - In `stopTracking()`, do **not** read or mutate `self.observers` on `@MainActor`. Instead, use a strong `[self]` capture in `AXThread.shared.async { [self] in ... }` so `self.observers`, `self.pendingPIDs`, and `self.knownWindowKeys` are drained and stopped exclusively on `AXThread` before `self` is released.
  - In `performFullSweep()`, dispatch the initial `sweepNextChunk` call via `AXThread.shared.async` (or wrap the `remainingApps.isEmpty` block in `AXThread.shared.async` when not already on `AXThread`).

---

### `PR2-02` [P1 | Complexity: S] — Windowless Running Apps Lose Running Indicator & "Quit" Menu, and Settings/Drag Updates Drop Multi-Monitor `runningBundleIDs`

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:135, 211, 258`
  - `Sources/TaskbarKit/UI/Panels/TaskbarView.swift:48, 110, 160-162, 343, 415, 418-420, 510-512`
- **The Problem:**
  1. **Windowless Running Apps Show as Not Running:** `TaskbarView.isAppRunning(bundleIdentifier:runningBundleIDs:)` (`L418-420`) now checks `runningBundleIDs.contains(bundleIdentifier)`, and `ScreenManager` (`L135, 211, 258`) computes `runningBundleIDs` as `Set(store.allWindows.map { $0.bundleID })`. On macOS, running apps (Finder, Safari, Terminal, Music, etc.) frequently stay running with zero open windows. Any pinned app whose windows are closed now loses its running indicator dot and its right-click "Quit" menu item (`PinnedButton.swift:74`).
  2. **Settings Changes Clobber Multi-Monitor Running Dots (`TaskbarView.apply` at `L415`):** `TaskbarView.apply(settings:theme:)` calls `self.updatePinnedApps(settings.pinnedApps)` with `runningBundleIDs: nil`, which falls back to `Set(currentWindows.map { $0.bundleID })` (`L343` — only windows on **that single monitor**). Any settings change immediately clears the running dot on secondary monitors for apps whose windows are on another monitor!
  3. **Mid-Drag Flush Drops `runningBundleIDs` (`TaskbarView.swift:48, 161, 512`):** `pendingWindowUpdate` stores `(windows, focusedKey, frontmostPID)` without `runningBundleIDs`, so `flushPendingWindowUpdate()` calls `updateWindows` with `runningBundleIDs: nil` and reverts to single-monitor `windows`.
- **How to Fix:**
  - In `ScreenManager`, compute `runningBundleIDs` by unioning `store.allWindows.map(\.bundleID)` with `NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier)` (or maintain a cached `Set<String>` updated on `didLaunchApplicationNotification` / `didTerminateApplicationNotification`), and trigger `updateWindows()` when a pinned app launches or terminates even if it has no windows.
  - On `TaskbarView`, store `private var currentRunningBundleIDs: Set<String> = []`, update it whenever a non-nil `runningBundleIDs` is passed to `updateWindows` or `updatePinnedApps`, include `runningBundleIDs: Set<String>?` in `pendingWindowUpdate`, and fall back to `currentRunningBundleIDs` instead of `Set(currentWindows.map { $0.bundleID })`.

---

### `PR2-03` [P1 | Complexity: XS] — Per-Window `fetchWindowAttributesBatch()` Timeouts Still Fall Back to 7 Sequential IPCs, and `sweepNextChunk` Wipes `knownWindowKeys` for Backed-Off PIDs

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:297-334` (`handleNotificationEvent`)
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:408-439` (`kAXWindowCreatedNotification`)
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:632-633` (`sweepNextChunk`)
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:781-809` (`inspectApp`)
- **The Problem:**
  1. **`handleNotificationEvent` records timeout then immediately runs 7 fallback IPC calls (`L297-334`):**
     ```swift
     let batch = event.element.fetchWindowAttributesBatch()
     let elapsed = AppEnvironment.current.clock.now() - startTime
     if batch == nil && elapsed >= Double(TaskbarConstants.Timing.axTimeout) {
         AppTracker.recordTimeout(for: event.pid)
     }
     ```
     Because there is no `return` inside that `if` block, when `batch == nil` due to a timeout, execution immediately enters `else` at `L326-334` (`event.element.role`, `subrole`, `title`, `frame`, `isMinimized`, `isMain`, `isFullScreen`), blocking `AXThread` for up to 7 more consecutive timeouts on the hung app!
  2. **`inspectApp` (`L781-809`) and `kAXWindowCreatedNotification` (`L408-439`) never check elapsed time on `fetchWindowAttributesBatch()`:** If `kAXWindowsAttribute` succeeds on an app that then hangs on `fetchWindowAttributesBatch()`, `inspectApp` falls into `else` (`L800-809`) and runs 7 more IPC calls per window without tripping the circuit breaker.
  3. **`sweepNextChunk` (`L633`) wipes `knownWindowKeys` for backed-off PIDs:** At the end of a full sweep, `self.knownWindowKeys = Set(accumulatedWindows.values.flatMap { $0 }.map(\.key))` replaces `knownWindowKeys` using only the non-backed-off apps in `accumulatedWindows`. Once a backed-off app's 5s timer expires, `inspectApp` (`L840`) treats all of its existing windows as newly discovered (`!knownWindowKeys.contains(key)`) and re-triggers `WorkAreaEnforcer` on every window.
- **How to Fix:**
  - In `handleNotificationEvent` (`L301-303`), `return` immediately after `AppTracker.recordTimeout(for: event.pid)`.
  - In `inspectApp` (`L781`) and `kAXWindowCreatedNotification` (`L408`), measure `elapsed` around `win.fetchWindowAttributesBatch()`; if `batch == nil && elapsed >= Double(TaskbarConstants.Timing.axTimeout)`, call `AppTracker.recordTimeout(for: pid)` and abort inspecting that PID (`return (nil, nil)` in `inspectApp`).
  - In `sweepNextChunk` (`L633`), preserve `knownWindowKeys` for active PIDs that were skipped (`!accumulatedWindows.keys.contains($0.pid)`).

---

### `PR2-04` [P1 | Complexity: XS] — "Reload Custom Themes" in `AppDelegate` Bypasses `SettingsStore`, Leaving `currentTheme` and Custom Theme Metrics Stale

- **Locations:**
  - `Sources/TaskbarKit/AppDelegate.swift:67-74`
  - `Sources/TaskbarCore/Config/SettingsStore.swift:27-48`
- **The Problem:**
  - In `AppDelegate.swift:67-74`:
    ```swift
    statusMenu.onReloadThemesRequested = { [weak self] in
        ThemeFileLoader.shared.reloadCustomThemes()
        guard let self = self else { return }
        let theme = ThemeRegistry.shared.theme(for: self.settingsStore.settings.activeThemeId)
        let resolvedTheme = self.settingsStore.settings.applyingThemeOverrides(to: theme)
        self.screenManager?.applyTheme(resolvedTheme)
        self.statusMenu?.refresh()
    }
    ```
  - Because `SettingsStore.update` skips work when `nextSettings == oldSettings` (`SettingsStore.swift:32`), `AppDelegate` bypassed `settingsStore` and pushed `resolvedTheme` directly to `screenManager`. As a result:
    1. `settingsStore.currentTheme` (`SettingsStore.swift:8`) is never updated, so any subsequent `ScreenManager.refreshPanels()`, settings mutation, or "Export Current Theme" reverts to the stale pre-reload theme!
    2. If the user edited `barHeight`, `minButtonWidth`, `maxButtonWidth`, `buttonSpacing`, `fontSize`, or `iconSize` in the active custom theme's JSON file on disk, `settings.updateWithCustomThemeMetrics(from:)` is never run.
    3. If the active custom theme file was deleted from disk, `settings.activeThemeId` still holds the deleted ID.
- **How to Fix:**
  - Add `public func reloadActiveTheme()` to `SettingsStore` that resolves `let baseTheme = ThemeRegistry.shared.theme(for: settings.activeThemeId)`, updates `settings.activeThemeId = baseTheme.id` and `settings.updateWithCustomThemeMetrics(from: baseTheme)`, updates `self.currentTheme = settings.applyingThemeOverrides(to: baseTheme)`, saves to `persistence`, and notifies `observers`. Then `onReloadThemesRequested` simply calls `ThemeFileLoader.shared.reloadCustomThemes()` followed by `self.settingsStore.reloadActiveTheme()`.

---

### `PR2-05` [P2 | Complexity: XS] — Race Condition in `DockController` Between Synchronous `captureOriginalStateIfFirstRun()` and Async `dockQueue` Removal of `originalStateKey`

- **Locations:**
  - `Sources/TaskbarKit/System/DockController.swift:152-191, 284`
- **The Problem:**
  - In `restoreDock()` (`L176-191`), `sentinelKey` is cleared synchronously on the caller thread (`L186`), while `Self.performRestoreInternal()` is dispatched asynchronously to `dockQueue` (`L188-190`), where `UserDefaults.standard.removeObject(forKey: originalStateKey)` executes at the very end (`L284`, after `killall Dock` finishes).
  - In `hideDock()` (`L152-172`), `captureOriginalStateIfFirstRun()` runs **synchronously on the caller thread** (`L164`) before dispatching `Self.performHideInternal(delay:)` to `dockQueue`.
  - If `restoreDock()` is followed quickly by `hideDock()` (before `dockQueue` finishes `performRestoreInternal()`), `hideDock()`'s `captureOriginalStateIfFirstRun()` sees `originalStateKey != nil` and returns early, and moments later `performRestoreInternal()` on `dockQueue` deletes `originalStateKey` (`L284`)—leaving the Dock hidden with **no saved baseline snapshot**!
- **How to Fix:**
  - Move `captureOriginalStateIfFirstRun()` and the `sentinelKey` writes inside `dockQueue.async` (into `performHideInternal` and `performRestoreInternal`) so all reads/writes of `originalStateKey`, `sentinelKey`, and `CFPreferences` are strictly serialized on `dockQueue`.

---

### `PR2-06` [P2 | Complexity: XS] — `ScreenManager.refreshFullScreenDetection()` Queries WindowServer Per Monitor & Doesn't Run on Space-Settle Sweeps

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:158-206, 255-297`
- **The Problem:**
  1. `refreshFullScreenDetection()` (`L168-177`) loops `for screen in NSScreen.screens` and calls `isScreenInFullScreen(screen:)`, which calls `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` (`L184`) on every iteration ($N_{\text{screens}}$ WindowServer IPC snapshots instead of 1).
  2. `handleActiveSpaceChanged()` (`L158-161`) calls `refreshFullScreenDetection()` once at $t = 0\text{ms}$ when the Space transition begins (while the macOS Space swipe animation is still in flight), and `updateWindows()` (`L255-297`) never refreshes `cachedFullScreenDisplayIDs` when `AppTracker`'s 50ms and 150ms Space-settle sweeps complete.
- **How to Fix:**
  - Fetch `let onScreenWindows = CGWindowListCopyWindowInfo(...)` once inside `refreshFullScreenDetection()` and pass it into `isScreenInFullScreen(screen:onScreenWindows:)`.
  - Also call `refreshFullScreenDetection()` when `AppTracker`'s Space-settle sweep finishes (or inside `updateWindows()` when triggered by a Space change) instead of calling `updateWindows()` prematurely at $t = 0\text{ms}$.

---

### `PR2-07` [P2 | Complexity: XS] — Redundant `observeWindow(element)` on 60–120Hz Window Drag & Unconditional 3-Pass `WorkAreaEnforcer` Chain on Non-Overlapping Resizes

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AXAppObserver.swift:225-229`
  - `Sources/TaskbarKit/Tracking/WorkAreaEnforcer.swift:69-99, 312, 328`
- **The Problem:**
  1. In `AXAppObserver.handleNotification` (`L225-229`), every `kAXWindowResizedNotification` and `kAXWindowMovedNotification` calls `observeWindow(element)`. Because move and resize notifications are only registered at the window level (`windowNotifications`, `L87-94`), any element emitting them is **already observed**; calling `observeWindow(element)` runs `winElement.windowID` IPC and locks `stateLock` 60–120 times per second during every window drag.
  2. In `WorkAreaEnforcer.swift:312, 328`, Pass 0 and Pass 1 check `guard didClamp0 || effectiveResize`. Whenever a user resizes any window (`effectiveResize == true`), even a small window at the top of the screen that does not touch the taskbar (`didClamp0 == false`), `effectiveResize` forces Pass 1 (`220ms`) and Pass 2 (`500ms`) to run anyway.
  3. In `WorkAreaEnforcer.swift:69-99`, internal test inspection helpers (`activeTimersCount`, `generationCount(for:)`, etc.) read `AXThread`-confined dictionaries directly without hopping to `AXThread` when `scheduler` is not `TestScheduler`.
- **How to Fix:**
  - Remove the `kAXWindowResizedNotification` and `kAXWindowMovedNotification` cases from `AXAppObserver.handleNotification` (`L225-229`).
  - In `WorkAreaEnforcer.swift:312, 328`, gate follow-up passes on `guard didClamp0` (and `guard didClamp1`) so non-overlapping resizes stop after Pass 0.

---

### `PR2-08` [P2 | Complexity: XS] — `AppDelegate` Bypasses `AppEnvironment.current.dockService`, `AppEnvironment.init` Defaults to `MainScheduler`, & `GroupWindowPopup.updateGroup` Omits Right-Edge X Clamping

- **Locations:**
  - `Sources/TaskbarKit/AppDelegate.swift:33, 129, 131`
  - `Sources/TaskbarKit/System/AppEnvironment.swift:573`
  - `Sources/TaskbarKit/UI/Panels/GroupWindowPopup.swift:104-109, 139-145`
- **The Problem:**
  1. `AppDelegate.swift:129, 131` still calls `DockController.shared.hideDock(...)` and `DockController.shared.restoreDock()` directly instead of `AppEnvironment.current.dockService`.
  2. `AppEnvironment.init` (`AppEnvironment.swift:573`) defaults `scheduler: any Scheduler = MainScheduler()` even though `AppEnvironment.live` (`L585`) uses `AXThreadScheduler()`, so any test constructing `AppEnvironment(windowActions: spy)` unintentionally reverts `scheduler` to `MainScheduler()`.
  3. `GroupWindowPopup.updateGroup` (`GroupWindowPopup.swift:139-145`) updates `newFrame.size.width = preferredSize.width` without clamping `newFrame.origin.x` to `screenFrame.maxX - preferredSize.width - 4.0` (unlike `show()` at `L104-109`).
- **How to Fix:**
  - Route `AppDelegate`'s Dock calls through `AppEnvironment.current.dockService`, change `AppEnvironment.init`'s default parameter to `scheduler: any Scheduler = AXThreadScheduler()`, and clamp `newFrame.origin.x` to `screen.frame` inside `GroupWindowPopup.updateGroup`.

---

### `PR2-09` [P2 | Complexity: XS] — Remaining Dead Methods, Duplicate Theme Metric Block & Stale Documentation Lines

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:81-102`
  - `Sources/TaskbarKit/UI/Panels/TaskbarPanel.swift:103-118`
  - `docs/ARCHITECTURE.md:198, 247-252, 274-278, 342, 350-354, 377, 389-397`
  - `docs/TESTING.md:100`
  - `docs/CONVENTIONS.md:49, 53, 64, 71`
  - `docs/CONFIGURATION.md:50-63, 121`
  - `README.md:5, 28, 45, 88, 124, 138`
- **The Problem:**
  1. `ScreenManager.updateTheme(themeId:)` (`L81-102`) still duplicates the 16-line custom theme metric assignment that `SettingsStore.update` (`SettingsStore.swift:34-37`) already performs via `nextSettings.updateWithCustomThemeMetrics(from: baseTheme)`.
  2. `TaskbarPanel.updateButtonWidths(max:min:)` and `updateButtonLayout(max:min:spacing:)` (`TaskbarPanel.swift:103-118`) have zero callers in `Sources/` or `Tests/`.
  3. Remaining doc drift:
     - `docs/ARCHITECTURE.md`: still mentions `NSScreen.screens` fallback in `evaluateAndClamp` (`L247`), app-level move/resize notifications (`L249`), `Pass 1 (150ms) and Pass 2 (400ms)` (`L252`), `TaskbarPanel.updateButtonLayout()` (`L276`), `"win_"`/`"grp_"` prefixes (`L342`), `rowsContainerView` (`L350`), `5pt`/`24pt` drag thresholds (`L377, 389, 392`), and `customOrderByScreen` (`L396`).
     - `docs/TESTING.md:100`: still mentions sentinel file `~/.config/taskbar/.dock_session_dirty` instead of `UserDefaults` key `com.taskbar.dockCurrentlyOverriddenByTaskbar`.
     - `docs/CONVENTIONS.md:49, 53, 64, 71`, `docs/CONFIGURATION.md:50-63, 121`, and `README.md:5, 28, 45, 88, 124, 138` still contain pre-remediation constant/property names and test counts.
- **How to Fix:**
  - Simplify `ScreenManager.updateTheme(themeId:)` to `settingsStore.update { $0.activeThemeId = themeId }`, delete the 2 unused methods on `TaskbarPanel`, and update the remaining stale lines in `docs/` and `README.md`.
