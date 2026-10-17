# Codebase Best Practices & Conventions

This document establishes the official architectural standards, coding conventions, concurrency rules, and engineering best practices for the `Taskbar` codebase.

---

## 1. Architectural Boundaries & Modularity

### Strict Separation of Concerns (3-Target Architecture)
The repository is structured into three modular Swift targets:
- **`TaskbarCore` (Pure Swift Library):**
  - Domain models (`PinnedApp`, `WindowInfo`, `WindowKey`), geometry math (`WorkAreaMath`), layout algorithms, filter rules (`WindowFilter`), settings persistence (`Settings`), logging (`TaskbarLogger`), and pure data-driven theme architecture (`ThemeDefinition`, `ThemeRegistry`, `ThemeFileLoader`, and built-in presets under `Config/Theme/Presets/`).
  - **Rule:** Zero dependencies on AppKit or Accessibility (`AXUIElement*`).
  - **Rule:** 100% testable via headless unit tests (`TaskbarCoreTests`).
- **`TaskbarKit` (macOS Engine Library):**
  - AppKit UI components (`TaskbarView`, `TaskbarPanel`, `TaskButton`, `PinnedButton`, `StartButton`, `OverflowButton`, `BevelDrawing`), icon caching & sanitization (`IconCache`), multi-display orchestration (`ScreenManager`), AX observer mechanics (`AXAppObserver`), background `AXThread`, `WorkAreaEnforcer`, and `DockController`.
  - **Rule:** Reusable as a library to enable Swift Testing integration suites (`TaskbarIntegrationTests`) without binary circularity.
- **`TaskbarApp` (Executable Shell):**
  - Minimal entrypoint (`main.swift`), NSApplication delegate, and POSIX signal trap initialization.
  - **Rule:** No business logic or state manipulation inside `main.swift`.

### Privacy Invariants & Path Hygiene
- **Zero Personal Identifiers:** Code, configuration files, test scripts, documentation, and commit messages must never reference personal home directories or usernames (e.g. `/Users/<username>/`).
- **Path Resolution:** Always resolve canonical directories dynamically via `FileManager.default.homeDirectoryForCurrentUser` or use relative/tilde paths (`~/.config/taskbar/themes/`).

### Single Source of Truth
- **Build & Threshold Constants:**
  - Governed by [`config/build.env`](../config/build.env) and exposed via [`BuildConfiguration.swift`](../Sources/TaskbarCore/Config/BuildConfiguration.swift).
  - Test harness thresholds (`TEST_MAX_RSS_MB`, `TEST_MAX_CPU_PERCENT`, `TEST_FIXTURE_APP`) must never be hardcoded in scripts.
- **Layout & Debounce Constants:**
  - All constants must be declared and documented in [`TaskbarConstants.swift`](../Sources/TaskbarCore/Config/TaskbarConstants.swift) under their respective category (`Layout`, `WorkArea`, `Debounce`, `Themes`, `Dock`, `Accessibility`, `Launcher`).
- **User-Facing Strings:**
  - All UI strings, menu item titles, glyphs, and preset names reside in [`TaskbarStrings.swift`](../Sources/TaskbarCore/Config/TaskbarStrings.swift).

---

## 2. Concurrency & Threading Invariants

### Main Thread (`@MainActor`) Isolation
- All AppKit UI operations, window management, view redrawing, and menu interactions must execute on the `@MainActor` main thread.
- **Hard Invariant:** Never call `AXUIElement*` functions on the main thread. A single unresponsive application can hang the main run loop, causing beachballs.

### Dedicated AX Thread (`AXThread`)
- All Accessibility IPC and notifications run on a dedicated background `Thread` with a persistent `CFRunLoop`.
- Always set messaging timeouts on AX elements:
  ```swift
  AXUIElementSetMessagingTimeout(element, 0.3)
  ```
- **Event Coalescing:** When receiving high-frequency AX notifications (moves, resizes, title updates), batch incoming updates across a **16ms window** (one display refresh frame) before dispatching immutable state snapshots to the main thread `WindowStore`.

### Multi-Display Window Focus Targeting
- **Hard Invariant:** Never activate applications using `.activateAllWindows`. Bulk activation raises background windows across secondary monitors, breaking multi-monitor isolation.
- Always use targeted AX window activation: invoke `kAXRaiseAction` and set `kAXMainAttribute` directly on the target window element, followed by targeted single-window process activation via `SetFrontProcessWithOptions` and `_SLPSSetFrontProcessWithOptions` (`PrivateAPI.activateSingleWindow`).

### Self-Notification Filtering & Clamping Invariants
- **Self-Inflicted Notification Filtering:** Any subsystem that programmatically mutates window geometry via Accessibility APIs (such as `WorkAreaEnforcer`) must record its own applied sizes and timestamps to filter out subsequent self-inflicted `kAXWindowResizedNotification` callbacks. Failing to filter self-inflicted events invalidates downstream settle timers and triggers recursive debounce loops.
- **Mouse Drag Deferral:** Never apply programmatic size adjustments while the user is actively dragging or resizing a window (`CGEventSource.buttonState(.combinedSessionState, button: .left)`). Clamping must be deferred until mouse-up to prevent fighting WindowServer and exhausting recursion limits.

---

## 3. UI Drawing & Performance

- **In-Place View Recycling:**
  - `TaskbarView` maintains internal lookup tables for both window buttons (`groupButtonMap: [String: TaskButton]`) and quick launch buttons (`pinnedButtonMap: [String: PinnedButton]`).
  - When window lists or pinned apps update, existing button subview instances are recycled in place, preserving cursor tracking areas and eliminating GC/heap allocation churn.
- **Direct AppKit Drawing:** Favor value types (`struct`) and direct `drawRect` drawing over deeply nested view hierarchies.
- **Multi-Resolution Icon Sanitization:**
  - Application icons are loaded once per bundle identifier/path, sanitized to eliminate corrupt legacy low-res bitmaps ($< 64\text{px}$) when high-resolution representations exist, and cached in memory.
  - Never fetch icons synchronously from disk inside drawing routines.
- **Data-Driven Theming & Callback Invariant:**
  - Avoid hardcoded theme colors or border drawing inside buttons. All visual tokens are resolved through [`ThemeRegistry`](../Sources/TaskbarCore/Config/Theme/ThemeRegistry.swift) using `ThemePalette`, `ThemeMetrics`, and `ThemeMaterials`.
  - **Theme Callback Invariant:** All theme lifecycle events must flow exclusively through `onThemeIdChanged(String)`. The legacy enum-based callback (`onThemeChanged(ThemeStyle)`) has been retired to eliminate enum-to-theme mapping clobbering.

---

## 4. Observer Lifecycle & Clean Teardown

- **Notification Hygiene:**
  - Before destroying an `AXObserverRef` or removing a run loop source, explicitly remove all registered notifications using `AXObserverRemoveNotification`.
  - Failure to unregister notifications causes dangling callbacks into deallocated observer contexts.
- **Orderly Teardown:**
  - Subsystems must implement explicit `stopTracking()` / `teardown()` methods (`AppTracker`, `ScreenManager`, `WorkAreaEnforcer`).
- **Test Fixture Cleanliness:**
  - Integration tests creating background processes or test windows must always clean them up using `defer { fixture.terminate() }` to guarantee no orphan processes remain running.

---

## 5. System Safety & Reversibility

Any feature that modifies macOS system preferences (such as hiding or repositioning the native Dock) must adhere to strict safety protocols:

1. **Backup First:** Capture and persist original system preferences in `UserDefaults` (`com.taskbar.original_dock_state`) on first run before making any modifications.
2. **Multi-Layered Signal Traps:** Implement restoration hooks across:
   - Normal application exit (`applicationWillTerminate`)
   - POSIX process signals (`SIGINT`, `SIGTERM`, `SIGHUP`)
   - C standard library `atexit` handlers
   - Menu bar status item ("Restore System Dock Now")
   - Standalone shell script ([`scripts/restore-dock.sh`](../scripts/restore-dock.sh))
