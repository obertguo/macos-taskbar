# Taskbar — Post-Remediation Codebase Audit & Execution Review

**Date:** 2026-10-17  
**Commit Audited:** `7c73e0b` (`refactor: phase 8`) — 9 commits (`b864504..7c73e0b`, 80 files changed, +7,371 / -2,394 lines)  
**Test Suite Status:** **301 / 301 unit tests passing** across 19 suites (`swift test`)  
**Scope:** Full verification of [`MASTER_REMEDIATION_PLAN.md`](./MASTER_REMEDIATION_PLAN.md) and [`MASTER_CODEBASE_AUDIT.md`](./MASTER_CODEBASE_AUDIT.md) execution quality, plus a fresh codebase-wide audit for newly introduced regressions, partial implementations ("hollow wiring"), performance bottlenecks, concurrency hazards, and test gaps.

---

## 1. Executive Summary

Gemini 3.8 completed all 9 phases (`Phase 0` through `Phase 8`) in sequential commits and expanded the unit test suite from **190 tests to 301 passing Swift Testing `@Test` cases** (migrating `TaskbarCoreTests` 100% off `XCTest`). Major structural goals were achieved:
- **What succeeded cleanly:**
  - `WindowStore` is now `@MainActor`-isolated with zero `NSLock` overhead, incremental $O(1)$ per-PID snapshot diffing (`syncSnapshot(forPID:)`), and a strongly-typed `OrderKey` (`.window(WindowKey)` / `.app(String)`).
  - `WindowOrderingLogic` uses a single-pass Decorate-Sort-Undecorate (`IndexedItem`) pipeline and preserves user drag order across `.always` $\leftrightarrow$ `.never` $\leftrightarrow$ `.whenCrowded` mode switches.
  - `TaskbarDragCoordinator` cleanly extracts all drag-and-drop state from `TaskbarView`, and `TaskbarView` buffers incoming window updates while a task-button drag is in progress (`hasPendingWindowUpdateDuringDrag`).
  - `AXElement.fetchWindowAttributesBatch()` is implemented using `AXUIElementCopyMultipleAttributeValues`, and `WindowActions` uses a thread-safe $O(1)$ `windowElementsByKey` cache with fallback to `findWindow`.
  - `WorkAreaEnforcer` is confined to `AXThread` (zero `NSLock`s) and shares pure geometry math (`WorkAreaMath`) with `TaskbarCoreTests`.

- **Where execution fell short or introduced regressions:**
  1. **Critical (`P0`) Regressions in `AppTracker`:**
     - **Circuit breaker deletes all windows of a timed-out app (`PR-01`):** When an app times out (`.cannotComplete`), `inspectApp` records the backoff and returns `[]`. Both `reconcileDirtyPIDs()` and `sweepNextChunk()` pass that `[]` directly into `store.syncSnapshot(forPID: pid, currentWindows: [])`—**wiping all of that app's windows off the taskbar** for the next 5 seconds and unfocusing the active window if the frontmost app is backed off.
     - **60–120Hz Window Drag Flood & Duplicate `WorkAreaEnforcer` Triggers (`PR-02`):** Every `kAXWindowMovedNotification` / `kAXWindowResizedNotification` runs a synchronous batch AX query on `AXThread` with zero debounce, calls `WorkAreaEnforcer.shared.handleWindowMovedOrResized` **twice** per pixel (once in `AXAppObserver` and once in `AppTracker`), and dispatches to `@MainActor` to run `onWindowsChanged?()` (full taskbar relayout) on every mouse-drag frame. Conversely, `WindowStore.syncSnapshot` omits `prev.frame != current.frame`, so cross-monitor moves detected during Tier 2/3 sweeps never update screen assignment.
     - **Cross-Thread Data Races on `knownWindowKeys` & `currentSweepGeneration` (`PR-03`):** `AppTracker.knownWindowKeys` (`nonisolated(unsafe) Set<WindowKey>`) is mutated on `@MainActor` (`untrackApp`, `finishFullSweep`) and concurrently read/mutated on `AXThread` (`inspectApp`) without synchronization—a direct Swift `Set` memory corruption / `EXC_BAD_ACCESS` hazard.
  2. **"Hollow" / Half-Wired Refactorings (`P1`):**
     - **Unconditional IPC Fallback on `nil` Optional Attributes (`PR-04`):** `let subrole = batch?.subrole ?? win.subrole` and `let title = batch?.title ?? win.title ?? appName` evaluate the right-hand side whenever `subrole` or `title` is legitimately `nil` in the batch result, firing individual AX IPC calls on every window anyway.
     - **Broken `StatusMenu` Actions (`PR-05`):** "Reload Custom Themes" reloads disk files without updating `SettingsStore`/`ScreenManager`/`StatusMenu`; changing "Dock Autohide Delay" does nothing because `AppDelegate` only checks `old.hideSystemDock != new.hideSystemDock`; and clicking "Restore System Dock" spawns `killall Dock` **twice**.
     - **Inverted Popup Resize Math (`PR-06`):** `GroupWindowPopup` adjusts `newFrame.origin.y -= heightDelta` in AppKit bottom-left coordinates, causing the popup to float upward away from the taskbar when a window closes.
     - **Dead `IconCache.rasterize` & Unwired `ResolvedTheme` Callers (`PR-07`):** `IconCache.rasterize` was written for unit tests and is never called by `IconCache.icon(for:pid:size:)`. `TaskButton` still calls `IconCache.shared.icon(for:pid:)` without `theme.iconSize`, and `BevelDrawing(in:theme: resolved)` has 0 callers in the codebase.
     - **Unwired `AppEnvironment` & Fake Lifecycle Tests (`PR-09`):** `AppEnvironment.current.windowActions` and `dockService` have **zero callers in `Sources/`** (`TaskbarView` still calls `WindowActions.*` directly at 14 sites), `AppEnvironment.live.scheduler` uses `MainScheduler()` instead of `AXThreadScheduler()`, and `DeterministicLifecycleTests` calls `spyActions.minimizeWindow(...)` directly on its own spy instead of exercising `TaskbarView`.

---

## 2. Scorecard of `MASTER_REMEDIATION_PLAN.md` Execution by Phase

| Phase | Target Goal | Execution Grade | Summary of What Was Done vs. What Was Missed |
| :--- | :--- | :---: | :--- |
| **Phase 0** | Quick Wins, Hotfixes & Dead Code Purge | **B** | Fixed `AXThread` spin-wait (`CFRunLoopStop`), `OverflowButton` width/title caching, `GroupWindowRowsView` 120Hz `needsDisplay` guard, `StartButton` menu eviction, `StatusMenu` `@MainActor`, and dead file deletion. **Missed:** `GroupWindowPopup` live-resize Y-origin math (`PR-06`) moves in the wrong direction; `StatusMenu` (`M-18`/`M-27`) still retains 10 mirrored state properties and 11 dead `update*` methods; `ThemeFileLoader` (`M-28`) validates `trimmedId` but registers the untrimmed `theme.id`. |
| **Phase 1** | Unify Settings & Theme State (`SettingsStore`) | **B** | Created `SettingsStore` and wired `AppDelegate.setupSettingsSubscriptions()`. **Missed:** Three `StatusMenu` regressions (`PR-05`): "Reload Custom Themes" never refreshes active theme or menu; changing "Dock Autohide Delay" is ignored by `AppDelegate`; and "Restore System Dock" triggers `restoreDock()` twice. |
| **Phase 2** | `@MainActor` `WindowStore` & `OrderKey` | **A-** | Removed `NSLock` from `WindowStore`, added `syncSnapshot(forPID:)`, introduced `OrderKey`, and refactored `WindowOrderingLogic` to Decorate-Sort-Undecorate (`IndexedItem`). **Missed:** `WindowStore.syncSnapshot` (`PR-02`) omits `prev.frame != current.frame`; multi-monitor `.app(bundleID)` pruning (`PR-15`) checks global window count instead of per-screen count; empty `bundleID == ""` collides under `.app("")`. |
| **Phase 3** | `TaskbarView` Decomposition & Zero-Alloc Rendering | **B-** | Extracted `TaskbarDragCoordinator`, added mid-drag task-button buffering, and created `ResolvedTheme`. **Missed:** `IconCache.rasterize` (`PR-07`) is dead code in production; `TaskButton` omits `theme.iconSize` and `theme.palette`; `BevelDrawing(in:theme: resolved)` has 0 callers; `updatePinnedApps` (`PR-08`) is unbuffered during drag and queries LaunchServices twice per non-running pinned app on every window update. |
| **Phase 4** | Event-Driven AX Engine, Batching & Circuit Breaker | **D+** | Built the 3-tier router, `fetchWindowAttributesBatch()`, $O(1)$ `windowElementsByKey` cache, and per-PID circuit breaker. **Critical Regressions:** Circuit breaker (`PR-01`) wipes out all windows of a timed-out app; `kAXWindowMoved`/`Resized` (`PR-02`) floods `@MainActor` at 60–120Hz and calls `WorkAreaEnforcer` twice per event; `knownWindowKeys` (`PR-03`) has unsynchronized cross-thread mutation; `batch?.subrole ?? win.subrole` (`PR-04`) triggers fallback IPC whenever optional attributes are `nil`. |
| **Phase 5** | Single-Deadline `WorkAreaEnforcer` on `AXThread` | **B** | Confined `WorkAreaEnforcer` to `AXThread` and extracted `WorkAreaMath`. **Missed:** Instead of 1 timer per move, it unconditionally chains 3 timer passes (`100ms -> 220ms -> 500ms`) even for windows nowhere near the taskbar (`PR-12`), schedules timers on `MainScheduler` in production (`PR-09`), falls back to `NSScreen.screens` off the main thread, and logs at `.info` on every event. |
| **Phase 6** | Harden `DockController` | **B+** | Replaced `Process("/usr/bin/defaults")` with `CFPreferences` and added dirty-session crash recovery. **Missed:** `captureOriginalStateIfFirstRun` (`PR-14`) never refreshes the baseline snapshot after a clean restore, calls `defaults.synchronize()` on the main thread, and runs `killall Dock` even if `_isDockHidden` is already `false`. |
| **Phase 7** | `AppEnvironment` DI Seams | **C** | Created `AppEnvironment` with protocols and mock/spy implementations. **Missed:** `AppEnvironment.current.windowActions` and `dockService` (`PR-09`) are completely unwired in `Sources/` (0 callers in production). |
| **Phase 8** | Test Migration & Coverage Expansion | **B-** | Migrated all `TaskbarCoreTests` to Swift Testing (0 `XCTestCase` remaining) and added 7 new test suites (301 tests total). **Missed:** `DeterministicLifecycleTests` (`PR-09`) tests its own mock directly instead of `TaskbarView`; `scripts/test-functional.sh` (`PR-10`) omits all 7 new test suites in `--all` and `--coverage` modes; `docs/` (`PR-16`) still contains stale pre-remediation architecture descriptions. |

---

## 3. Master Priority Ranking (P0 $\to$ P2)

| ID | Priority | Category | Title | Primary Locations | Complexity |
| :--- | :---: | :--- | :--- | :--- | :---: |
| **PR-01** | **P0** | Correctness / AX | Circuit breaker returns `[]` on timeout and wipes all windows of a hung app from `WindowStore` | `AppTracker.swift:480, 589, 659-691` | **S** |
| **PR-02** | **P0** | Performance / AX | 60–120Hz `kAXWindowMoved` UI relayout flood, duplicate `WorkAreaEnforcer` triggers, and missing `frame` check in `WindowStore.syncSnapshot` | `AppTracker.swift:273-353`, `AXAppObserver.swift:206-212`, `WindowStore.swift:162-169` | **S** |
| **PR-03** | **P0** | Concurrency / Crash | Unsynchronized cross-thread data races on `AppTracker.knownWindowKeys` (`Set<WindowKey>`) and `currentSweepGeneration` | `AppTracker.swift:96, 101, 192, 532, 579, 620, 726-727` | **XS** |
| **PR-04** | **P1** | Performance / AX | Unconditional individual AX IPC fallback when optional batch attributes (`subrole`, `title`) are `nil` | `AppTracker.swift:297-308, 367-378, 690-711`, `AXElement+Attributes.swift:151-204` | **XS** |
| **PR-05** | **P1** | Correctness / UI | Broken `StatusMenu` actions: "Reload Custom Themes" no-op, "Dock Autohide Delay" ignored, and double `killall Dock` on restore | `AppDelegate.swift:64-87`, `StatusMenu.swift:405-407, 480-494` | **XS** |
| **PR-06** | **P1** | Correctness / UI | `GroupWindowPopup` live update moves popup Y-origin in inverted direction (`newFrame.origin.y -= heightDelta`) | `GroupWindowPopup.swift:111, 141-146, 170-175` | **XS** |
| **PR-07** | **P1** | Performance / Dead Code | `IconCache.rasterize` is dead production code, `TaskButton` omits `theme.iconSize` & `theme.palette`, and `BevelDrawing(theme: ResolvedTheme)` has 0 callers | `IconCache.swift:52-66, 115-151`, `TaskButton.swift:166-177, 246`, `BevelDrawing.swift:88-113`, `ResolvedTheme.swift:142` | **S** |
| **PR-08** | **P1** | Performance / UI | Double `layoutComponents()` on every update, LaunchServices queries per non-running pinned app, and unbuffered mid-drag `updatePinnedApps` | `ScreenManager.swift:262, 288-296`, `TaskbarView.swift:8-12, 162-168, 335-411`, `TaskbarPanel.swift:89-92` | **S** |
| **PR-09** | **P1** | Architecture / Tests | `AppEnvironment` DI seams are unwired in production, `live.scheduler` uses `MainScheduler`, and `DeterministicLifecycleTests` is self-mocking | `AppEnvironment.swift:131-162, 571-583`, `TaskbarView.swift`, `WorkAreaEnforcer.swift:283, 382`, `DeterministicLifecycleTests.swift` | **S** |
| **PR-10** | **P1** | Testing / CI | `scripts/test-functional.sh` omits all 7 new test suites in `--all` and `--coverage` modes and requires AX permission before unit tests | `scripts/test-functional.sh:138, 159-163, 192-222` | **XS** |
| **PR-11** | **P2** | Correctness / UI | `ScreenManager.cachedFullScreenDisplayIDs` never refreshes on Space change, leaving taskbar permanently hidden after fullscreen + display change | `ScreenManager.swift:9, 171-181, 276` | **XS** |
| **PR-12** | **P2** | Performance / AX | `WorkAreaEnforcer` unconditionally chains 3 timer passes on every window move, falls back to `NSScreen.screens` on `AXThread`, and logs at `.info` | `WorkAreaEnforcer.swift:142, 226-228, 285-325, 348-355` | **S** |
| **PR-13** | **P2** | Reliability / Memory | `AppTracker.stopTracking()` leaks `AXAppObserver`s on deallocation (`[weak self]`), `observeWindow` holds lock across IPC, and `observedWindows` is never pruned | `AppTracker.swift:763-781`, `AXAppObserver.swift:145-158, 290-292` | **S** |
| **PR-14** | **P2** | Reliability / System | `DockController` never refreshes baseline Dock snapshot after restore, calls `synchronize()` on main thread, and runs `killall Dock` when already restored | `DockController.swift:82-103, 178-191, 249-286` | **XS** |
| **PR-15** | **P2** | Correctness / Logic | Multi-monitor `.app(bundleID)` pruning checks global window count, `.never` mode overwrites `.app` order index, and empty `bundleID == ""` collides | `WindowStore.swift:57-75, 194-250`, `WindowOrderingLogic.swift:87-97`, `WindowGroupingLogic.swift:56-65`, `TaskbarView.swift:215` | **XS** |
| **PR-16** | **P2** | Maintainability / Docs | Leftover dead shims in `StatusMenu`/`ScreenManager`, untrimmed custom theme IDs in `ThemeFileLoader`, and stale claims in `docs/` | `StatusMenu.swift:11-35, 107-161`, `ThemeFileLoader.swift:55-70`, `docs/ARCHITECTURE.md`, `docs/TESTING.md`, `docs/TEST_SPECIFICATIONS.md` | **S** |

---

## 4. Ranking by Code Complexity (XS $\to$ S)

All remaining issues are localized and surgical—none require a large (`M` or `L`) architectural rewrite because the core structures (`SettingsStore`, `WindowStore`, `OrderKey`, `ResolvedTheme`, `TaskbarDragCoordinator`, `AXThread`, `AppEnvironment`) are already in place:

- **XS (< 30 lines, single-file or two-file fix):**
  - **PR-03:** Confine `knownWindowKeys` to `AXThread` (or protect with `cacheLock`) and make `currentSweepGeneration` atomic/locked.
  - **PR-04:** Unwrap `if let batch = win.fetchWindowAttributesBatch()` before falling back to individual `AXElement` properties, and return `nil` from `fetchWindowAttributesBatch()` when `role == nil`.
  - **PR-05:** Fix `AppDelegate` settings diff for `dockHideDelay`, remove redundant `onRestoreDockRequested?()` call in `StatusMenu.handleRestoreDock`, and refresh `SettingsStore`/`ScreenManager`/`StatusMenu` on "Reload Custom Themes".
  - **PR-06:** Keep `newFrame.origin.y` fixed at its bottom anchor in `GroupWindowPopup.updateGroup` and `handleCloseWindow`.
  - **PR-10:** Update `scripts/test-functional.sh` to run `swift test --skip FunctionalTests` in a single invocation instead of a hardcoded 10-suite list.
  - **PR-11:** Remove `cachedFullScreenDisplayIDs` union or recompute it on `activeSpaceDidChangeNotification`.
  - **PR-14:** Clear `originalStateKey` on clean restore in `DockController`, guard `restoreDock()` with `_isDockHidden`, and remove `defaults.synchronize()` from main thread.
  - **PR-15:** Prune `.app(bundleID)` per-screen in `WindowStore`, use `if map[.app(item.bundleID)] == nil` in `WindowOrderingLogic.rebuildOrderMap`, and fallback to `"pid_\(pid)"` when `bundleID.isEmpty`.
- **S (30–120 lines, 1–4 files):**
  - **PR-01:** Return a distinct enum/optional (`AppInspectionResult.timedOut` or `[WindowInfo]?`) from `inspectApp` so `reconcileDirtyPIDs` and `sweepNextChunk` preserve existing windows and focus when an app is backed off.
  - **PR-02:** Remove duplicate `WorkAreaEnforcer` call from `AXAppObserver`, only update `WindowStore` on `kAXWindowMoved`/`Resized` when screen assignment changes (or after debounce), and add `prev.frame != current.frame` to `WindowStore.syncSnapshot`.
  - **PR-07:** Wire `IconCache.rasterize` into `IconCache.icon(for:pid:size:)`, pass `theme.iconSize` and `theme: resolved` in `TaskButton` and other buttons, and fix `ResolvedTheme.startButtonPreferredWidth`.
  - **PR-08:** Remove redundant `updatePinnedApps` call from `ScreenManager.updateWindows()`, track running bundle IDs via `NSWorkspace` notifications, and buffer `updatePinnedApps` during drag.
  - **PR-09:** Route `TaskbarView` through `AppEnvironment.current.windowActions`, set `AppEnvironment.live.scheduler = AXThreadScheduler()`, and update `DeterministicLifecycleTests` to exercise real components.
  - **PR-12:** Only schedule follow-up verification passes in `WorkAreaEnforcer` when a window was actually nudged (or is near the taskbar), remove off-main `NSScreen.screens`, and downgrade `.info` log to `.debug`.
  - **PR-13:** Make `AppTracker.stopTracking()` capture `observers` strongly before dispatching to `AXThread`, move `winElement.windowID` outside `stateLock`, and prune closed window IDs.
  - **PR-16:** Delete dead `StatusMenu`/`ScreenManager` shims, store `trimmedId` in `ThemeFileLoader`/`ThemeRegistry`, and sync `docs/`.

---

## 5. Detailed Findings & Concise Remediation Feedback

---

### `PR-01` [P0 | Complexity: S] — Circuit Breaker Wipes Out All Windows of a Timed-Out App

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:479-490` (`reconcileDirtyPIDs`)
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:585-591, 614-631` (`sweepNextChunk`, `finishFullSweep`)
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:659-691` (`inspectApp`)
- **The Problem:**
  1. In `inspectApp(app:isFrontmost:)` (`L669-678`), when `AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute, ...)` fails with `.cannotComplete` or exceeds `100ms`, it calls `AppTracker.recordTimeout(for: pid)` and returns `([], focusedKey)` (an empty window array).
  2. Both `reconcileDirtyPIDs()` (`L480`) and `sweepNextChunk()` (`L589`) store `updatedWindows[pid] = []` and dispatch to `@MainActor` where `store.syncSnapshot(forPID: pid, currentWindows: [])` (`L488`, `L618`) **deletes every window of that app from `WindowStore`** right as the circuit breaker backs off the PID for 5 seconds!
  3. In `sweepNextChunk` (`L585-587`), if the frontmost app is currently backed off, it is skipped, leaving `currentFocused = nil`. When `finishFullSweep` runs (`L629`), it calls `store.setFocusedWindow(key: nil)`, unfocusing the active window on the taskbar.
  4. Furthermore, at `L690`, `win.fetchWindowAttributesBatch()` is called per window without checking `.cannotComplete` or elapsed time; if it times out and returns `nil`, `L691` immediately falls back to `win.role`, stalling `AXThread` a second time on the same hung process.
- **How to Fix:**
  - Have `inspectApp` return `(windows: [WindowInfo]?, focused: WindowKey?)` where `windows == nil` indicates a timeout/circuit-breaker abort.
  - In `reconcileDirtyPIDs()` and `sweepNextChunk()`, only add `pid` to `updatedWindows` when `windows != nil`.
  - In `finishFullSweep()`, if the frontmost app was skipped due to backoff, preserve `store.focusedWindow` instead of overwriting it with `nil`.
  - In `inspectApp`'s per-window loop (`L690`), check elapsed time around `fetchWindowAttributesBatch()` and abort the remaining windows for that PID if it exceeds `timeoutThresholdSeconds`.

---

### `PR-02` [P0 | Complexity: S] — 60–120Hz Window Drag Flood, Duplicate `WorkAreaEnforcer` Calls, and Missing `frame` Check in `WindowStore.syncSnapshot`

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:273-353` (`handleNotificationEvent`)
  - `Sources/TaskbarKit/Tracking/AXAppObserver.swift:206-212` (`handleNotification`)
  - `Sources/TaskbarCore/Logic/WindowStore.swift:162-169` (`syncSnapshot(forPID:currentWindows:)`)
- **The Problem:**
  1. **60–120Hz `@MainActor` Relayout Flood:** In `AppTracker.handleNotificationEvent` (`L273-353`), every `kAXWindowMovedNotification` and `kAXWindowResizedNotification` executes a synchronous batch AX query on `AXThread` and unconditionally dispatches `DispatchQueue.main.async` (`L335-351`) to call `store.addOrUpdateWindow(info)` and `self.onWindowsChanged?()` (`L350`) on every single pixel of mouse drag—even when the window never changed screens and no taskbar-visible property (`title`, `isMinimized`, `isFullScreen`) changed!
  2. **Duplicate `WorkAreaEnforcer` Call:** Both `AXAppObserver.handleNotification` (`AXAppObserver.swift:207, 211`) **and** `AppTracker.handleNotificationEvent` (`AppTracker.swift:311, 313`) call `WorkAreaEnforcer.shared.handleWindowMovedOrResized` for the exact same `kAXWindowMoved` / `kAXWindowResized` notification—bumping `generationCounters[winID]` twice and recreating the deadline timer twice per mouse event.
  3. **Missing `frame` Check in `WindowStore.syncSnapshot` (`WindowStore.swift:162-169`):** `syncSnapshot` compares `title`, `isMinimized`, `isAppHidden`, `isMain`, and `isFullScreen`, but **never compares `prev.frame != current.frame`**. If a window moves across monitors during a Tier 2 or Tier 3 sweep, `syncSnapshot` neither updates `windowsByKey[key]` nor returns `didChange = true`, leaving the window stuck on the old monitor's taskbar!
- **How to Fix:**
  - Remove the `WorkAreaEnforcer.shared.handleWindowMovedOrResized` call from `AXAppObserver.swift:206-212` so `AppTracker.handleNotificationEvent` is the single caller (and pass the already-fetched `frame` so `WorkAreaEnforcer` doesn't have to re-query it).
  - In `AppTracker.handleNotificationEvent`, for `kAXWindowMoved` / `kAXWindowResized`, only call `self.onWindowsChanged?()` on `@MainActor` if the window's screen assignment or `isFullScreen` state actually changed (while still updating `store` silently or debouncing frame updates).
  - In `WindowStore.syncSnapshot(forPID:currentWindows:)` (`WindowStore.swift:162-169`), include `prev.frame != current.frame` in the mutation check.

---

### `PR-03` [P0 | Complexity: XS] — Unsynchronized Cross-Thread Data Races on `AppTracker.knownWindowKeys` and `currentSweepGeneration`

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:96, 101, 192, 532, 579, 620, 726-727`
- **The Problem:**
  - `knownWindowKeys: Set<WindowKey>` (`L96`, marked `nonisolated(unsafe)`) is mutated on `@MainActor` in `untrackApp` (`L192`) and `finishFullSweep` (`L620`), while simultaneously being read and mutated (`knownWindowKeys.contains(key)` / `knownWindowKeys.insert(key)`) on `AXThread` in `inspectApp` (`L726-727`) with **no lock**. Concurrent mutation and lookup on a Swift `Set` causes heap corruption and `EXC_BAD_ACCESS`.
  - Additionally, `knownWindowKeys` is never pruned when individual windows close via Tier 1 (`kAXUIElementDestroyedNotification`) or Tier 2 (`reconcileDirtyPIDs`), causing stale keys to accumulate until a full sweep.
  - `currentSweepGeneration: UInt64` (`L101`, marked `nonisolated(unsafe)`) is incremented on `@MainActor` (`L532`) and read on `AXThread` (`L579`) without synchronization.
- **How to Fix:**
  - Confine `knownWindowKeys` strictly to `AXThread` (perform the `untrackApp` and `finishFullSweep` pruning via `AXThread.shared.async`, and also remove keys on `kAXUIElementDestroyedNotification` and in `reconcileDirtyPIDs`), or guard all accesses with `Self.cacheLock`.
  - Guard `currentSweepGeneration` with `stateLock` (or manage it exclusively on `AXThread` inside `startFullSweepOnAXThread`).

---

### `PR-04` [P1 | Complexity: XS] — Unconditional Individual AX IPC Fallback When Batch Attributes Are `nil`

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:297-308, 367-378, 690-711`
  - `Sources/TaskbarKit/Tracking/AXElement+Attributes.swift:151-204`
- **The Problem:**
  - In all three inspection paths (`handleNotificationEvent`, `registerNewWindow`, and `inspectApp`), `AppTracker` writes:
    ```swift
    let batch = win.fetchWindowAttributesBatch()
    let role = batch?.role ?? win.role
    let subrole = batch?.subrole ?? win.subrole
    ...
    let title = batch?.title ?? win.title ?? (app.localizedName ?? "App")
    ```
  - Whenever `fetchWindowAttributesBatch()` succeeds (`batch != nil`), any attribute that is legitimately `nil` on that window (such as `subrole` on many standard windows or `title` on untitled windows) causes `batch?.subrole` to evaluate to `nil`, which **triggers the right-hand side `win.subrole` / `win.title`**, firing individual `AXUIElementCopyAttributeValue` IPC calls anyway!
  - Furthermore, in `AXElement.fetchWindowAttributesBatch()` (`AXElement+Attributes.swift:151-204`), if `AXUIElementCopyMultipleAttributeValues` returns `.success` for a destroyed/invalid window where all 8 array elements are `kAXValueTypeAXError`, `fetchWindowAttributesBatch()` returns a non-nil `RawWindowAttributes` with `role: nil`, causing `batch?.role ?? win.role` to fire 5 more sequential IPC calls on the dead element.
- **How to Fix:**
  - In `AXElement.fetchWindowAttributesBatch()`, if `role == nil` after unpacking the batch array, return `nil` (or leave `role == nil` as an explicit dead-window signal).
  - In `AppTracker`, branch on `if let batch = win.fetchWindowAttributesBatch()` and read `batch.role`, `batch.subrole`, `batch.title ?? appName`, etc. directly **without** falling back to `win.subrole` / `win.title`; only use individual property reads in the `else` branch when `batch == nil`.

---

### `PR-05` [P1 | Complexity: XS] — Broken `StatusMenu` Actions: "Reload Custom Themes", "Dock Autohide Delay", and Double `killall Dock` on Restore

- **Locations:**
  - `Sources/TaskbarKit/AppDelegate.swift:64-87`
  - `Sources/TaskbarKit/UI/Menu/StatusMenu.swift:405-407, 480-494`
  - `Sources/TaskbarCore/Config/SettingsStore.swift:27-48`
- **The Problem:**
  1. **"Reload Custom Themes" does not refresh UI or menu (`AppDelegate.swift:75-77`, `StatusMenu.swift:405-407`):** Clicking "Reload Custom Themes" calls `ThemeFileLoader.shared.reloadCustomThemes()`, which updates `ThemeRegistry.shared`, but **never** re-resolves `SettingsStore.currentTheme`, never reapplies the theme to `ScreenManager`, and never rebuilds the `StatusMenu` theme submenu.
  2. **"Dock Autohide Delay" does nothing (`AppDelegate.swift:65`, `StatusMenu.swift:480-487`):** `StatusMenu.handleDockDelaySelect` updates `settingsStore.update(\.dockHideDelay, to: delay)`, and `AppDelegate`'s subscriber (`L65`) checks `if old.hideSystemDock != new.hideSystemDock`—completely ignoring `old.dockHideDelay != new.dockHideDelay`! Worse, `StatusMenu.handleDockDelaySelect` also invokes `onDockHideDelayChanged?(delay)`, which was never wired in `AppDelegate`.
  3. **"Restore System Dock" runs `killall Dock` twice (`StatusMenu.swift:489-494`, `AppDelegate.swift:69, 84-87`):** `StatusMenu.handleRestoreDock` calls `settingsStore.update { $0.hideSystemDock = false }` (which synchronously triggers `AppDelegate`'s subscriber -> `DockController.shared.restoreDock()` #1) and then immediately calls `onRestoreDockRequested?()` (which triggers `AppDelegate`'s callback -> `DockController.shared.restoreDock()` #2), spawning `killall Dock` twice in a row.
- **How to Fix:**
  - In `AppDelegate.setupSettingsSubscriptions()` (`L65`), check `if old.hideSystemDock != new.hideSystemDock || old.dockHideDelay != new.dockHideDelay`.
  - In `StatusMenu.handleRestoreDock` (`L489-494`), remove `onRestoreDockRequested?()` (or only use `settingsStore.update`), and remove `onRestoreDockRequested` wiring from `AppDelegate` if redundant.
  - In `AppDelegate`'s `onCustomThemesReloaded` handler (`L75-77`), refresh `settingsStore` / `screenManager?.applyTheme(settingsStore.currentTheme)` and rebuild the `StatusMenu` theme list.

---

### `PR-06` [P1 | Complexity: XS] — `GroupWindowPopup` Live Update Moves Popup Y-Origin in Inverted Direction

- **Locations:**
  - `Sources/TaskbarKit/UI/Panels/GroupWindowPopup.swift:111, 141-146, 170-175`
- **The Problem:**
  - When `GroupWindowPopup` opens (`show(for:relativeTo:)` at `L111`), its bottom edge is anchored just above the taskbar in AppKit bottom-left screen coordinates: `y = buttonRect.maxY + verticalOffset`.
  - When the window list changes while open (`updateGroup` at `L144-145` and `handleCloseWindow` at `L173-174`), it computes:
    ```swift
    let heightDelta = preferredSize.height - newFrame.height
    newFrame.size = preferredSize
    newFrame.origin.y -= heightDelta
    ```
  - In AppKit coordinates (where `origin.y` is the **bottom** edge), keeping the popup anchored above the taskbar requires `newFrame.origin.y` to stay **constant**! Subtracting `heightDelta` moves the bottom edge upward when a window closes (`heightDelta < 0` $\implies$ `origin.y` increases, floating away from the taskbar) and pushes the popup downward over the taskbar when a window opens (`heightDelta > 0` $\implies$ `origin.y` decreases).
- **How to Fix:**
  - Remove `newFrame.origin.y -= heightDelta` from both `updateGroup(_:)` (`L145`) and `handleCloseWindow(_:)` (`L174`) so the bottom edge remains anchored at `buttonRect.maxY + verticalOffset`.

---

### `PR-07` [P1 | Complexity: S] — `IconCache.rasterize` Is Dead Production Code, `TaskButton` Omits `theme.iconSize` & `theme.palette`, and `BevelDrawing(theme: ResolvedTheme)` Has Zero Callers

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/IconCache.swift:52-66, 115-151`
  - `Sources/TaskbarKit/UI/Buttons/TaskButton.swift:166-177, 246`
  - `Sources/TaskbarKit/UI/Panels/TaskbarView.swift:577`
  - `Sources/TaskbarKit/UI/Panels/BevelDrawing.swift:88-113`
  - `Sources/TaskbarKit/UI/Theme/ResolvedTheme.swift:142`
- **The Problem:**
  1. **`IconCache.rasterize` is never called in production (`IconCache.swift:52-66, 115-151`):** Phase 3 added `IconCache.rasterize(_:targetSize:)` (`L115-151`) and tested it in `ResolvedThemeAndIconCacheTests`, but `IconCache.icon(for:pid:size:)` (`L52-66`) still sets `rawIcon.size = size` directly and never calls `rasterize(_:targetSize:)`!
  2. **`TaskButton` and `TaskbarView.showOverflowMenu` omit `theme.iconSize` (`TaskButton.swift:176, 246`, `TaskbarView.swift:577`):** `PinnedButton` and `StartButton` pass `size: NSSize(width: theme.iconSize, height: theme.iconSize)`, but `TaskButton.drawRetro` (`L176`), `TaskButton.drawHybrid` (`L246`), and `TaskbarView.showOverflowMenu` (`L577`) still call `IconCache.shared.icon(for: bundleID, pid: pid)` with the default 16×16 size.
  3. **`BevelDrawing(in:theme: resolved)` has zero callers (`BevelDrawing.swift:104-113`, `TaskButton.swift:167, 169`):** Phase 3 added zero-allocation `BevelDrawing.drawRaisedBevel(in:theme: ResolvedTheme)` and `drawSunkenBevel(in:theme: ResolvedTheme)`, but **nothing in the codebase calls them**. Worse, `TaskButton.drawRetro` (`L167, 169`) calls `BevelDrawing.drawSunkenBevel(in: bounds)` without `palette` or `theme` (hardcoding Classic 95 gray on dark beveled themes), while `PinnedButton`, `StartButton`, `OverflowButton`, and `GroupWindowRowsView` call `BevelDrawing.draw...(in:palette:)` (which allocates 3 `NSColor` objects per draw).
  4. **`ResolvedTheme.startButtonPreferredWidth` font mismatch (`ResolvedTheme.swift:142`):** Uses `.regular` weight whenever `!theme.is3DBeveled`, ignoring `theme.fontBold` and mismatching `startButtonTextAttributes` (`L133`).
- **How to Fix:**
  - Call `rasterize(rawIcon, targetSize: size)` inside `IconCache.icon(for:pid:size:)` before storing in `cache[key]`.
  - Pass `size: NSSize(width: theme.iconSize, height: theme.iconSize)` in `TaskButton.drawRetro`, `TaskButton.drawHybrid`, and `TaskbarView.showOverflowMenu`.
  - Switch `TaskButton`, `PinnedButton`, `StartButton`, `OverflowButton`, and `GroupWindowRowsView` to call `BevelDrawing.drawRaisedBevel(in: bounds, theme: resolved)` / `drawSunkenBevel(in: bounds, theme: resolved)`.
  - Fix `ResolvedTheme.startButtonPreferredWidth` (`L142`) to use `(theme.is3DBeveled || theme.fontBold) ? .bold : .regular`.

---

### `PR-08` [P1 | Complexity: S] — Double `layoutComponents()` on Every Update, LaunchServices Queries per Pinned App, and Unbuffered Mid-Drag `updatePinnedApps`

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:262, 288-296`
  - `Sources/TaskbarKit/UI/Panels/TaskbarView.swift:8-12, 162-168, 335-411`
  - `Sources/TaskbarKit/UI/Panels/TaskbarPanel.swift:89-92`
- **The Problem:**
  1. **Double `layoutComponents()` per window event (`ScreenManager.swift:262, 288-296`):** `ScreenManager.updateWindows()` calls `panel.taskbarView.updatePinnedApps(pinnedApps, runningBundleIDs: runningBundleIDs)` (which runs `layoutComponents()` #1) and immediately calls `panel.taskbarView.updateWindows(filteredWindows)` (which runs `layoutComponents()` #2).
  2. **Repeated LaunchServices IPC in `isAppRunning` (`ScreenManager.swift:262`, `TaskbarView.swift:344, 381, 405-411`):** `ScreenManager` builds `runningBundleIDs` from `store.allWindows.map { $0.bundleID }` (only apps with open windows). For every pinned app without an open window, `TaskbarView.updatePinnedApps` calls `isAppRunning(_:)` **twice** (`L344` and `L381`), and `isAppRunning` falls back to `NSRunningApplication.runningApplications(withBundleIdentifier:)` (`L409`)—querying LaunchServices twice per non-running pinned app on every window update!
  3. **Mid-drag `updatePinnedApps` resets pinned drag state (`TaskbarView.swift:335-403`):** `TaskbarView.updateWindows` buffers updates when `dragCoordinator.isDragging` (`L174`), but `updatePinnedApps` has **no drag guard**. Because `ScreenManager.updateWindows()` calls `updatePinnedApps` on every window event, any background window event during an active pinned-button drag destroys/mutates `pinnedButtons` mid-drag!
  4. **Redundant `theme.didSet` (`TaskbarView.swift:8-12`, `TaskbarPanel.swift:89-92`):** `TaskbarView.theme.didSet` has no `guard oldValue != theme`, and `TaskbarPanel.apply` sets `taskbarView.theme = theme` both directly and inside `update Appearance()`.
- **How to Fix:**
  - Maintain `runningBundleIDs` from `NSWorkspace` launch/terminate notifications (or pass it alongside `updateWindows`), and remove `NSRunningApplication.runningApplications(withBundleIdentifier:)` from `TaskbarView.isAppRunning`.
  - Guard `TaskbarView.updatePinnedApps` when `dragCoordinator.isDragging` (or coalesce `runningBundleIDs` into `updateWindows` so only a single `layoutComponents()` pass runs).
  - Add `guard oldValue != theme else { return }` to `TaskbarView.theme.didSet`.

---

### `PR-09` [P1 | Complexity: S] — `AppEnvironment` DI Seams Are Unwired in Production, `live.scheduler` Uses `MainScheduler`, and `DeterministicLifecycleTests` Is Self-Mocking

- **Locations:**
  - `Sources/TaskbarKit/System/AppEnvironment.swift:131-162, 571-583`
  - `Sources/TaskbarKit/UI/Panels/TaskbarView.swift:429, 439, 476, 513, 520, 525, 530, 535, 540, 548, 557, 619, 623`
  - `Sources/TaskbarKit/Tracking/WorkAreaEnforcer.swift:283, 382`
  - `Tests/TaskbarKitTests/DeterministicLifecycleTests.swift:62, 92, 119, 162, 189`
- **The Problem:**
  1. **Zero production callers of `AppEnvironment.current.windowActions` / `dockService`:** `AppEnvironment` defines `windowActions: WindowActionsProtocol` and `dockService: DockControllerProtocol`, but `TaskbarView` still calls static `WindowActions.*` methods directly at 14 call sites, and `AppDelegate` calls `DockController.shared` directly at 5 call sites.
  2. **`AppEnvironment.live.scheduler` uses `MainScheduler()` (`AppEnvironment.swift:136, 571-583`):** Even though `AXThreadScheduler` was implemented at `AppEnvironment.swift:145-162`, `AppEnvironment.live` (`L578`) initializes `scheduler: MainScheduler()`. Because `WorkAreaEnforcer` schedules its timers via `AppEnvironment.current.scheduler` (`WorkAreaEnforcer.swift:283, 382`), every `WorkAreaEnforcer` timer in production is created as a `DispatchSourceTimer` on `DispatchQueue.main` whose handler then dispatches back to `AXThread.shared.async`!
  3. **Self-mocking `DeterministicLifecycleTests` (`DeterministicLifecycleTests.swift:62, 92, 119, 162, 189`):** Because `TaskbarView` wasn't wired to `AppEnvironment.current.windowActions`, `DeterministicLifecycleTests` literally calls `spyActions.minimizeWindow(window.key)` directly in the test body and asserts `#expect(spyActions.invocations.contains(.minimizeWindow(window.key)))`—testing the mock against itself!
- **How to Fix:**
  - Change `AppEnvironment.live` (`AppEnvironment.swift:578`) to use `scheduler: AXThreadScheduler()`.
  - Route `TaskbarView`'s 14 `WindowActions.*` calls through `AppEnvironment.current.windowActions`.
  - Update `DeterministicLifecycleTests` to trigger actual `TaskbarView` / `TaskButton` click and context-menu handlers and verify that `spyActions` records the resulting invocations.

---

### `PR-10` [P1 | Complexity: XS] — `scripts/test-functional.sh` Omits All 7 New Test Suites in `--all` and `--coverage` Modes

- **Locations:**
  - `scripts/test-functional.sh:138, 159-163, 192-222`
- **The Problem:**
  - In `--all` mode (`L138`) and `--coverage` mode (`L192-222`), `scripts/test-functional.sh` hardcodes a 10-element `UNIT_FILTERS` array from before the remediation plan. It completely skips all 7 newly added test suites (`DeterministicLifecycleTests`, `AXEventRouterAndCircuitBreakerTests`, `WorkAreaEnforcerTests`, `DockControllerTests`, `AppEnvironmentTests`, `TaskButtonContextMenuTests`, `AccessibilityButtonsTests` — 77 tests).
  - Additionally, `--all` mode calls `check_accessibility` (`L159`) before running unit tests, and `--coverage` mode invokes `swift test --enable-code-coverage --filter` 10 separate times in a loop instead of once.
- **How to Fix:**
  - Replace the hardcoded `UNIT_FILTERS` loop in `scripts/test-functional.sh` with a single `swift test --skip FunctionalTests` (and `swift test --enable-code-coverage --skip FunctionalTests` in `--coverage` mode), and move `check_accessibility` inside `run_functional_tests()` so unit tests remain headless.

---

### `PR-11` [P2 | Complexity: XS] — Native Fullscreen Detection Stuck After Monitor Change & Never Updated on Space Switch

- **Locations:**
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:9, 171-181, 276`
- **The Problem:**
  - `ScreenManager` caches `cachedFullScreenDisplayIDs: Set<CGDirectDisplayID>` (`L9`) inside `handleScreenParametersChanged()` (`L181`) and unions it with `store.screensWithFullScreenWindows` inside `updateWindows()` (`L276`).
  - However, `cachedFullScreenDisplayIDs` is **never** refreshed on `NSWorkspace.activeSpaceDidChangeNotification` (`L175`). If a monitor is viewing a fullscreen Space at the moment a screen parameter change occurs, `cachedFullScreenDisplayIDs` permanently records that display ID and hides that monitor's taskbar even after the user switches back to a regular desktop Space!
- **How to Fix:**
  - Either remove `cachedFullScreenDisplayIDs` and rely on `store.screensWithFullScreenWindows` (which `AppTracker` updates on Space change), or recompute `cachedFullScreenDisplayIDs` inside the `activeSpaceDidChangeNotification` handler (`L175`) as well.

---

### `PR-12` [P2 | Complexity: S] — `WorkAreaEnforcer` Unconditional 3-Pass Timer Chain, Off-Main `NSScreen.screens` Fallback & Eager `.info` Logging

- **Locations:**
  - `Sources/TaskbarKit/Tracking/WorkAreaEnforcer.swift:142, 226-228, 285-325, 348-355`
- **The Problem:**
  1. **Unconditional 3-pass timer chain (`L285-325`):** Instead of a single deadline timer per window move/resize, `scheduleEnforcementPass` unconditionally chains Pass 0 (`100ms`) $\to$ Pass 1 (`220ms`) $\to$ Pass 2 (`500ms`) for **every** window move/resize—even when Pass 0 sees the window is at the top of the screen nowhere near the taskbar (`clamped == currentFrame`)!
  2. **Off-main `NSScreen.screens` fallback (`L348-355`):** `currentScreens()` falls back to reading `NSScreen.screens` directly on `AXThread` whenever `_screens.isEmpty`.
  3. **Eager `.info` logging (`L226-228`):** `handleWindowMovedOrResized` logs at `.info` level on every window move event before debouncing.
  4. **`XCTestCase` check (`L142`):** Uses `NSClassFromString("XCTestCase") == nil` even though the project now uses Swift Testing.
- **How to Fix:**
  - In `executePass` (`L297-325`), only schedule follow-up verification passes (`passIndex + 1`) if Pass 0 actually clamped/nudged the window (or if the window was mid-animation/resized).
  - Seed `_screens` on `@MainActor` during `configure(...)` and remove the off-main `NSScreen.screens` fallback.
  - Change the `handleWindowMovedOrResized` entry log (`L227`) from `.info` to `.debug`.

---

### `PR-13` [P2 | Complexity: S] — `AppTracker.stopTracking()` Observer Leak on Deallocation, Lock Held Across IPC in `observeWindow`, & Unpruned `observedWindows`

- **Locations:**
  - `Sources/TaskbarKit/Tracking/AppTracker.swift:763-781`
  - `Sources/TaskbarKit/Tracking/AXAppObserver.swift:145-158, 290-292`
- **The Problem:**
  1. **`stopTracking()` leaks `AXAppObserver`s when `AppTracker` deallocates (`AppTracker.swift:769`):** `stopTracking()` dispatches cleanup to `AXThread.shared.async { [weak self] in guard let self = self else { return } ... }`. When a caller writes `defer { tracker.stopTracking() }` and `tracker` goes out of scope immediately (as in tests or shutdown), `self` is deallocated before `AXThread` executes the block, skipping `obs.stop()` and leaking active `CFRunLoopSource`s on `AXThread`.
  2. **Lock held across AX IPC (`AXAppObserver.swift:145-158`):** `observeWindow(_:)` acquires `stateLock.lock()` and then calls `winElement.windowID` (`_AXUIElementGetWindow` IPC) while holding the lock.
  3. **`observedWindows` never pruned on Tier 2 reconcile (`AXAppObserver.swift:290-292`):** When a window closes without emitting a clean `kAXUIElementDestroyedNotification` (or when `CFEqual` doesn't match the transient element), its `CGWindowID` remains in `observedWindows` until the app terminates.
- **How to Fix:**
  - In `AppTracker.stopTracking()`, or in `deinit`, capture the `observers` dictionary values strongly into the `AXThread.shared.async` closure so `obs.stop()` always executes even if `AppTracker` deallocates.
  - In `AXAppObserver.observeWindow(_:)`, resolve `guard let winID = winElement.windowID` **before** acquiring `stateLock`.
  - Add a `pruneWindows(keeping validIDs: Set<CGWindowID>)` call on `AXAppObserver` during `inspectApp`.

---

### `PR-14` [P2 | Complexity: XS] — `DockController` Never Refreshes Baseline Snapshot After Restore, Calls `synchronize()` on Main Thread, and Unconditionally Restores

- **Locations:**
  - `Sources/TaskbarKit/System/DockController.swift:82-103, 178-191, 249-286`
- **The Problem:**
  1. **Stale baseline snapshot (`L249-268`):** `captureOriginalStateIfFirstRun(currentAutohide:currentDelay:)` returns early whenever `defaults.dictionary(forKey: originalStateKey) != nil`, and `performRestoreInternal` (`L283`) only sets `sessionActiveKey = false` without removing `originalStateKey`. If the user restores the Dock, changes their macOS System Settings (e.g., enables native Dock autohide), and later toggles Taskbar's "Hide System Dock" back on and off, `DockController` overwrites their current macOS setting with the ancient first-run snapshot!
  2. **`defaults.synchronize()` on main thread (`L267, 272`):** Called synchronously inside `stateLock` on `@MainActor`.
  3. **Unconditional `restoreDock()` (`L99-103`):** `restoreDock(completion:)` does not check `guard _isDockHidden` before enqueueing `performRestoreInternal`, so calling `restoreDock()` when the Dock is already visible still writes preferences and runs `killall Dock`.
- **How to Fix:**
  - In `performRestoreInternal`, remove `originalStateKey` after a successful restore so the next `hideDock()` captures a fresh baseline of the user's current macOS Dock settings.
  - Guard `restoreDock(completion:)` with `stateLock.withLock { _isDockHidden || defaults.bool(forKey: sessionActiveKey) }`.
  - Remove the deprecated `defaults.synchronize()` calls.

---

### `PR-15` [P2 | Complexity: XS] — Multi-Monitor Per-Screen `.app(bundleID)` Pruning, `.never` Mode Order Overwrite, & Empty `bundleID == ""` Collisions

- **Locations:**
  - `Sources/TaskbarCore/Logic/WindowStore.swift:57-75, 194-250`
  - `Sources/TaskbarCore/Logic/WindowOrderingLogic.swift:87-97`
  - `Sources/TaskbarCore/Logic/WindowGroupingLogic.swift:56-65`
  - `Sources/TaskbarKit/UI/Panels/TaskbarView.swift:215`
- **The Problem:**
  1. **Per-screen `.app(bundleID)` pruning checks global window count (`WindowStore.swift:66, 207, 242`):** When pruning `customOrderByScreen[screenID]`, `WindowStore` checks `activeBundleIDs.contains(bundleID)` (which is global across all screens) instead of checking whether `bundleID` still has windows on that specific `screenID`.
  2. **`.never` mode overwrites `.app(bundleID)` with last window index (`WindowOrderingLogic.swift:89-96`):** In `rebuildOrderMap`, for `.window` items, `map[.app(item.bundleID)] = index` unconditionally overwrites the app's position with its **last** window's index instead of preserving its **first** window's index (`if map[.app(item.bundleID)] == nil`).
  3. **Bundle-less processes (`bundleID == ""`) collide (`WindowGroupingLogic.swift:57`, `TaskbarView.swift:215`):** Processes without a bundle identifier get `bundleID = ""`, causing unrelated executables to group together under `"group_"`, share `.app("")` in `OrderKey`, and collide in `TaskbarView.updateTaskButtons` recycling (`existingByApp[""]`).
- **How to Fix:**
  - Compute `activeBundleIDsOnScreen` per `screenID` when pruning `customOrderByScreen[screenID]`.
  - In `WindowOrderingLogic.rebuildOrderMap` (`L95`), only set `map[.app(item.bundleID)] = index` if `map[.app(item.bundleID)] == nil`.
  - In `AppTracker.makeWindowInfo` (or `WindowInfo.init`), fall back to `"pid:\(pid)"` when `app.bundleIdentifier` is `nil` or empty.

---

### `PR-16` [P2 | Complexity: S] — Leftover Dead Shims, Untrimmed Custom Theme IDs & Documentation Drift

- **Locations:**
  - `Sources/TaskbarKit/UI/Menu/StatusMenu.swift:11-35, 107-161`
  - `Sources/TaskbarKit/UI/Management/ScreenManager.swift:90-115`
  - `Sources/TaskbarKit/UI/Theme/ThemeFileLoader.swift:55-70`
  - `Sources/TaskbarCore/Config/ThemeRegistry.swift:120-129`
  - `docs/ARCHITECTURE.md:189, 198, 228-260, 352, 387-406`
  - `docs/TESTING.md:92, 100`
  - `docs/TEST_SPECIFICATIONS.md:216-218`
- **The Problem:**
  1. **`StatusMenu` & `ScreenManager` leftover shims:** `StatusMenu` still declares 10 mirrored state properties (`currentMultiMonitorMode`, `currentGroupMode`, etc.), 9 unwired `on*Changed` callbacks, and 11 dead `update*` methods with 0 callers (`M-18`/`M-27`). `ScreenManager` still has 6 forwarding `apply*` wrappers (`L90-115`).
  2. **Untrimmed `theme.id` registered (`ThemeFileLoader.swift:55-70`, `ThemeRegistry.swift:120-129`):** Both validate `let trimmedId = theme.id.trimmingCharacters(in: .whitespacesAndNewlines)` against `reservedIds`, but then register the original untrimmed `theme` (`ThemeRegistry.shared.registerCustomThemes(validThemes)`), so `" classic95 "` bypasses the check or stores whitespace keys.
  3. **Documentation drift (`docs/`):**
     - `docs/ARCHITECTURE.md` still references `buttonMap: [String: TaskButton]` (`L189`), `needsReconcileAgain` (`L198`), the old 3-pass `350ms / 150-400-650ms` `WorkAreaEnforcer` architecture (`L228-260`), and `[String: Int]` custom order dictionaries (`L352`).
     - `docs/TESTING.md` (`L92, 100`) and `docs/TEST_SPECIFICATIONS.md` (`L216-218`) still reference deleted `TC-UNIT-014`/`016` tests and claim functional tests are the only suite for `AppTracker` / `WorkAreaEnforcer`.
- **How to Fix:**
  - Remove the unused properties/callbacks/update methods from `StatusMenu` and `ScreenManager`.
  - Construct a sanitized `ThemeConfig` with `id: trimmedId, name: trimmedName` before registering in `ThemeFileLoader` and `ThemeRegistry.importTheme`.
  - Update `docs/ARCHITECTURE.md`, `docs/TESTING.md`, and `docs/TEST_SPECIFICATIONS.md` to reflect the post-remediation architecture and the 301-test suite.

---

## 6. Recommended Follow-Up Remediation Plan (2 Surgical Passes)

If you want to bring the codebase to a **100% clean, zero-regression state**, the 16 findings above can be resolved in two focused passes:

1. **Pass 1 — Critical AX & State Stabilization (`PR-01` through `PR-06`, `PR-10`):**
   - Fix `AppTracker.inspectApp` timeout return semantics so circuit-breaker backoffs never wipe existing windows or focus (`PR-01`).
   - Deduplicate the `WorkAreaEnforcer` call in `AXAppObserver`, stop firing `onWindowsChanged` on same-screen `kAXWindowMoved`/`Resized` events, and add `prev.frame != current.frame` to `WindowStore.syncSnapshot` (`PR-02`).
   - Synchronize `knownWindowKeys` and `currentSweepGeneration` on `AXThread` (`PR-03`).
   - Fix `if let batch = win.fetchWindowAttributesBatch()` so `nil` optional attributes (`subrole`, `title`) don't trigger individual AX IPC fallbacks (`PR-04`).
   - Fix the 3 `StatusMenu` / `AppDelegate` wiring bugs (`PR-05`), the inverted `GroupWindowPopup` Y-origin math (`PR-06`), and `scripts/test-functional.sh` (`PR-10`).
2. **Pass 2 — Rendering Polish, DI Wiring & Hygiene (`PR-07` through `PR-09`, `PR-11` through `PR-16`):**
   - Wire `IconCache.rasterize` into `IconCache.icon`, pass `theme.iconSize` and `theme: resolved` across all buttons (`PR-07`), and eliminate redundant `updatePinnedApps` / LaunchServices queries (`PR-08`).
   - Connect `TaskbarView` to `AppEnvironment.current.windowActions`, switch `AppEnvironment.live.scheduler` to `AXThreadScheduler()`, and update `DeterministicLifecycleTests` (`PR-09`).
   - Clean up `ScreenManager` fullscreen space tracking (`PR-11`), `WorkAreaEnforcer` follow-up pass gating (`PR-12`), `AppTracker.stopTracking()` (`PR-13`), `DockController` snapshot refresh (`PR-14`), per-screen `.app` pruning (`PR-15`), and dead shims / docs (`PR-16`).
