# Codebase Best Practices & Conventions (v0.1.0)

This document establishes the official architectural standards, coding conventions, concurrency rules, and engineering best practices for the `Taskbar` codebase.

---

## 1. Architectural Boundaries & Modularity

### Strict Separation of Concerns
The repository is divided into two distinct targets:
- **`TaskbarCore`:** Pure Swift domain models, algorithms, geometry math, layout solvers, filter predicates, and configuration.
  - **Rule:** Zero dependencies on AppKit, Accessibility (`AXUIElement*`), or macOS UI frameworks.
  - **Rule:** Must be 100% testable via standard `XCTest` in headless environments without window servers.
- **`TaskbarApp`:** AppKit application shell, system integration, `NSPanel` rendering, AX thread management, and POSIX signal handling.
  - **Rule:** Business logic, geometry math, and layout calculations must never be embedded directly inside `NSView` drawing routines or view controllers; delegate them to `TaskbarCore`.

### Single Source of Truth
- **Constants:** Never hardcode "magic numbers" (pixel dimensions, tolerances, timeouts, debounce intervals, system domain names, or binary paths).
  - All constants must be declared and documented in [`TaskbarConstants.swift`](file:///Sources/TaskbarCore/Config/TaskbarConstants.swift) under their respective category (`Layout`, `WorkArea`, `Debounce`, `Themes`, `Dock`, `Accessibility`, `Launcher`).
- **User-Facing Strings:** Never hardcode user-facing copy or labels inline.
  - All UI strings, menu item titles, glyphs, and preset names must reside in [`TaskbarStrings.swift`](file:///Sources/TaskbarCore/Config/TaskbarStrings.swift).

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

- **Direct AppKit Drawing:** Favor value types (`struct`) and direct `drawRect` drawing over deeply nested view hierarchies.
- **Targeted Invalidation:** Avoid calling `setNeedsDisplay(true)` on entire panels or container views. Invalidate only the specific `TaskButton` instances whose title, width, or focus state changed.
- **Icon Caching:** Application icons must be loaded once per `bundleIdentifier`, resized to the configured icon dimension, and cached in memory. Never fetch icons synchronously from disk inside drawing routines.
- **Vertical Baseline Centering:** When drawing custom text alongside icons, dynamically calculate baseline offsets using font metrics (`capHeight` / `lineHeight`) to ensure visual balance across all configurable bar heights (26–44pt) and font sizes (10–14pt).

---

## 4. State Management & Persistence

- **Unidirectional Data Flow:**
  $$\text{AX Events} \longrightarrow \text{AppTracker} \longrightarrow \text{WindowStore} \longrightarrow \text{ScreenManager} \longrightarrow \text{TaskbarView}$$
- **Resilient Deserialization:**
  When adding new properties to [`Settings.swift`](file:///Sources/TaskbarCore/Config/Settings.swift):
  - Always implement `decodeIfPresent` in `init(from decoder:)` with fallback to default constants.
  - Ensure saved settings from prior versions deserialize cleanly without failing or discarding user preferences.
  - Add unit tests in `SettingsTests.swift` validating backward-compatible decoding.

---

## 5. System Safety & Reversibility

Any feature that modifies macOS system preferences (such as hiding or repositioning the native Dock) must adhere to strict safety protocols:

1. **Backup First:** Capture and persist original system preferences in `UserDefaults` (`com.taskbar.original_dock_state`) on first run before making any modifications.
2. **Multi-Layered Signal Traps:** Implement restoration hooks across:
   - Normal application exit (`applicationWillTerminate`)
   - POSIX process signals (`SIGINT`, `SIGTERM`, `SIGHUP`)
   - C standard library `atexit` handlers
   - Menu bar status item ("Restore System Dock Now")
3. **Emergency Fallback:** Maintain a standalone shell script ([`scripts/restore-dock.sh`](file:///scripts/restore-dock.sh)) that users can execute independently from terminal if the app is forcefully killed (`kill -9`).
4. **Idempotence:** Guard preference writes so redundant system commands (e.g. `killall Dock`) are skipped if settings have not changed.

---

## 6. Testing & Quality Standards

- **Unit Testing Coverage:**
  - Every new logic component, layout solver, click policy rule, or geometry function in `TaskbarCore` must have comprehensive unit tests in `Tests/TaskbarCoreTests/`.
  - Tests must execute cleanly with zero failures via `swift test`.
- **Geometry & Coordinate Conversions:**
  - Remember that macOS AppKit uses bottom-left origin ($y=0$ at bottom), whereas Accessibility APIs (`AXUIElement`) use top-left origin ($y=0$ at top).
  - Always use [`ScreenAssignment`](file:///Sources/TaskbarCore/Logic/ScreenAssignment.swift) and [`WorkAreaMath`](file:///Sources/TaskbarCore/Logic/WorkAreaMath.swift) conversion utilities rather than manual coordinate arithmetic.
- **Edge-Case Validation:**
  - Explicitly test edge cases: 0x0 minimized windows (Chromium/Electron), multi-monitor boundaries, offscreen coordinates, and window title truncation thresholds.
