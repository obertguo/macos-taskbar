# Codebase Audit Checklist & Code Smells Reference

Use this checklist during every post-milestone or periodic codebase audit to methodically inspect the repository for architectural drift, code smells, duplication, and convention violations.

---

## 1. Architectural Modularity & Boundaries

- [ ] **Target Independence:**
  - `TaskbarCore` contains zero imports of `AppKit`, `ApplicationServices`, or Cocoa UI types.
  - `TaskbarKit` contains zero reverse dependencies on `TaskbarApp`.
  - `TaskbarApp` contains only `main.swift` and essential app bootstrap lifecycle code.
- [ ] **Single Responsibility Principle:**
  - Each class/struct has one well-defined purpose.
  - Large controllers (e.g. `ScreenManager`, `TaskbarView`, `WorkAreaEnforcer`) do not mix UI drawing, AX messaging, state persistence, and math logic.
- [ ] **Data Flow Directionality:**
  - State flows down unidirectionally from stores (`WindowStore`, `PinnedStore`, `ThemeRegistry`) to UI components.
  - User events flow up via explicit callbacks or closures (`onThemeIdChanged`, `onPinChanged`).

---

## 2. Code Smells & Deduplication

- [ ] **Duplicated Logic:**
  - Are frame calculations, display intersections, or coordinate conversions duplicated across `ScreenAssignment`, `WorkAreaMath`, or `TaskbarView`?
  - Are notification name lists (`kAXWindowResizedNotification`, etc.) repeated across multiple files instead of referenced from `TaskbarConstants.Accessibility`?
- [ ] **Dead & Orphaned Code:**
  - Search for unused helper methods, obsolete enum cases, and commented-out code blocks.
  - Verify that deprecated callbacks (e.g. `onThemeChanged(ThemeStyle)`) have been fully retired and replaced by unified identifiers.
- [ ] **Magic Numbers & Hardcoded Strings:**
  - Check for raw numbers (e.g. `30.0`, `0.15`, `0.4`, `16`) that should be defined in `TaskbarConstants.swift`.
  - Check for raw user-facing strings, menu titles, or tooltips that should reside in `TaskbarStrings.swift`.
- [ ] **Visibility & Scope Bloat:**
  - Are properties and helper functions exposed as `public` when `internal` or `private` would suffice?
  - Are state mutations encapsulated with `private(set)`?

---

## 3. Concurrency & Threading Invariants

- [ ] **Actor Isolation:**
  - All views (`NSView`, `NSPanel`), button controllers, and menu handlers are annotated with `@MainActor`.
- [ ] **AX Thread Containment:**
  - No `AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`, or `AXObserverCreate` calls occur on the main thread.
  - All AX queries specify timeouts: `AXUIElementSetMessagingTimeout(element, 0.3)`.
- [ ] **Thread-Safe State Access:**
  - Classes marked `@unchecked Sendable` (`WorkAreaEnforcer`, `AXAppObserver`, `TestFixtureApp`) protect internal state with `NSLock` or serial queues.
- [ ] **Cancellation & Task Lifecycle:**
  - All background polling `Task` instances (e.g. `permissionPollTask` in `AppTracker`) are cancelled during deinit and teardown.

---

## 4. Folder & File Organization Ideas

Evaluate potential file and directory reorganizations to improve project navigability:

| Current Directory | Potential Structural Refactoring | Rationale |
|---|---|---|
| `Sources/TaskbarKit/UI/` | *Completed in v0.3.X*: Subdivided into `Buttons/`, `Panels/`, `Menu/`, and `Management/` | Clutter reduced; button components cleanly decoupled from panels and menus. |
| `Sources/TaskbarKit/Tracking/` | Group AX observers (`AXAppObserver`, `AXThread`) vs work area logic (`WorkAreaEnforcer`, `AppTracker`) | Separates OS-level accessibility engine mechanics from window work area layout clamping. |
| `Tests/TaskbarIntegrationTests/` | Subdivide into `Suites/` and `Helpers/` | Keeps test fixture helpers clearly distinct from runnable test suites. |

---

## 5. Privacy & Path Hygiene

- [ ] Run automated grep across repository:
  ```bash
  grep -rn "/Users/" Sources/ Tests/ config/ scripts/ docs/ plans/ README.md || true
  ```
- [ ] Invariant: Ensure zero instances of personal user paths or developer account names appear anywhere in the codebase or git commit history.

---

## 6. Agent Skills Staleness & Alignment

- [ ] **Skills Inventory Audit:**
  - Verify all `.agents/skills/*/SKILL.md` files against latest architectural conventions and targets.
  - Ensure reference runbooks in `.agents/skills/*/references/` contain zero obsolete or deprecated patterns (e.g. legacy unretained self unmanaged pointers or retired callbacks).
  - Verify that test counts, metric thresholds, and commands match active codebase baselines (e.g. 112+ tests).
- [ ] **Proactive Sync:**
  - Synchronize any detected skill drift immediately during post-milestone audits.
