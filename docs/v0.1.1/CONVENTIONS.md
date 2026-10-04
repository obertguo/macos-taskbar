# Codebase Best Practices & Conventions (v0.1.1)

This document establishes the official architectural standards, coding conventions, concurrency rules, and engineering best practices for the `Taskbar` codebase.

---

## 1. Architectural Boundaries & Modularity

### Strict Separation of Concerns (3-Target Architecture)
The repository is structured into three modular Swift targets:
- **`TaskbarCore` (Pure Swift Library):**
  - Domain models, geometry math, layout algorithms, filter rules, settings persistence, logging, and pure data-driven theme registry (`ThemeDefinition`).
  - **Rule:** Zero dependencies on AppKit or Accessibility (`AXUIElement*`).
  - **Rule:** 100% testable via headless unit tests (`TaskbarCoreTests`).
- **`TaskbarKit` (macOS Engine Library):**
  - AppKit UI components, in-place button recycling (`TaskbarView`), `NSPanel` lifecycle, AX observer mechanics (`AXAppObserver`), background `AXThread`, `WorkAreaEnforcer`, and `DockController`.
  - **Rule:** Reusable as a library to enable Swift Testing integration suites (`TaskbarIntegrationTests`) without binary circularity.
- **`TaskbarApp` (Executable Shell):**
  - Minimal entrypoint (`main.swift`), NSApplication delegate, and POSIX signal trap initialization.
  - **Rule:** No business logic or state manipulation inside `main.swift`.

### Single Source of Truth
- **Build & Threshold Constants:**
  - Governed by [`config/build.env`](../../config/build.env) and exposed via [`BuildConfiguration.swift`](../../Sources/TaskbarCore/Config/BuildConfiguration.swift).
  - Test harness thresholds (`TEST_MAX_RSS_MB`, `TEST_MAX_CPU_PERCENT`, `TEST_FIXTURE_APP`) must never be hardcoded in scripts.
- **Layout & Debounce Constants:**
  - All constants must be declared and documented in [`TaskbarConstants.swift`](../../Sources/TaskbarCore/Config/TaskbarConstants.swift) under their respective category (`Layout`, `WorkArea`, `Debounce`, `Themes`, `Dock`, `Accessibility`, `Launcher`).
- **User-Facing Strings:**
  - All UI strings, menu item titles, glyphs, and preset names reside in [`TaskbarStrings.swift`](../../Sources/TaskbarCore/Config/TaskbarStrings.swift).

---

## 2. Concurrency & Threading Invariants

### Main Thread (`@MainActor`) Isolation
- All AppKit UI operations, window management, view redrawing, and menu interactions must run on the `@MainActor` main thread.
- **Hard Invariant:** Never call `AXUIElement*` functions on the main thread. A single unresponsive application can hang the main run loop, causing beachballs.

### Dedicated AX Thread (`AXThread`)
- All Accessibility IPC and notifications run on a dedicated background `Thread` with a persistent `CFRunLoop`.
- Always set messaging timeouts on AX elements:
  ```swift
  AXUIElementSetMessagingTimeout(element, 0.3)
  ```
- **Event Coalescing:** When receiving high-frequency AX notifications (moves, resizes, title updates), batch incoming updates across a **16ms window** (one display refresh frame) before dispatching immutable state snapshots to the main thread `WindowStore`.

---

## 3. UI Drawing & Performance

- **In-Place View Recycling:**
  - `TaskbarView` maintains an internal button lookup table (`buttonMap: [WindowKey: TaskButton]`).
  - When window lists update, existing button subview instances are recycled in place, preserving cursor tracking areas and eliminating GC/heap allocation churn.
- **Direct AppKit Drawing:** Favor value types (`struct`) and direct `drawRect` drawing over deeply nested view hierarchies.
- **Icon Caching:** Application icons must be loaded once per `bundleIdentifier`, resized to the configured icon dimension, and cached in memory. Never fetch icons synchronously from disk inside drawing routines.
- **Data-Driven Theming:**
  - Avoid hardcoded theme colors or border drawing inside buttons. All visual tokens are resolved through [`ThemeRegistry`](../../Sources/TaskbarCore/Config/ThemeRegistry.swift) using `ThemePalette`, `ThemeMetrics`, and `ThemeMaterials`.

---

## 4. Observer Lifecycle & Clean Teardown

- **Notification Hygiene:**
  - Before destroying an `AXObserverRef` or removing a run loop source, explicitly remove all registered notifications using `AXObserverRemoveNotification`.
  - Failure to unregister notifications causes dangling callbacks into deallocated observer contexts.
- **Orderly Teardown:**
  - Subsystems must implement explicit `stopTracking()` / `teardown()` methods (`AppTracker`, `ScreenManager`, `WorkAreaEnforcer`).

---

## 5. System Safety & Reversibility

Any feature that modifies macOS system preferences (such as hiding or repositioning the native Dock) must adhere to strict safety protocols:

1. **Backup First:** Capture and persist original system preferences in `UserDefaults` (`com.taskbar.original_dock_state`) on first run before making any modifications.
2. **Multi-Layered Signal Traps:** Implement restoration hooks across:
   - Normal application exit (`applicationWillTerminate`)
   - POSIX process signals (`SIGINT`, `SIGTERM`, `SIGHUP`)
   - C standard library `atexit` handlers
   - Menu bar status item ("Restore System Dock Now")
3. **Emergency Fallback:** Maintain a standalone shell script ([`scripts/restore-dock.sh`](../../scripts/restore-dock.sh)) that users can execute independently from terminal if the app is forcefully killed (`kill -9`).
4. **Idempotence:** Guard preference writes so redundant system commands (e.g. `killall Dock`) are skipped if settings have not changed.

---

## 6. Testing & Quality Standards

- **Three-Tier Testing Pyramid:**
  - **Tier 1 (Unit):** Pure mathematical, layout, and filter logic (`Tests/TaskbarCoreTests`). Zero external dependencies.
  - **Tier 2 (Integration):** Swift Testing suites (`Tests/TaskbarIntegrationTests`) using real macOS test fixtures (`TestFixtureApp`).
  - **Tier 3 (Automated CLI & Benchmark):** CLI runner ([`scripts/test-functional.sh`](../../scripts/test-functional.sh)) validating real-world scenarios, resident memory (<45 MB RSS), and CPU utilization.
- **Privacy Standard (Mandatory):**
  - Never log, commit, or reference personal usernames or home directory paths in code, logs, docs, or git history. Use `~` or standard relative paths.
