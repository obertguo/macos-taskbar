# Codebase Audit Report (v0.2.3)

**Date:** October 6, 2026  
**Milestone:** Post-v0.2.3 Release & Pre-v0.3.0 Preparation  
**Auditor:** Codebase Audit & Refactor Subsystem  
**Scope:** `Sources/`, `Tests/`, `docs/`, `plans/`, `config/`, `scripts/`  
**Test Suite Status:** 104 / 104 Passing (100%)  
**Memory & Performance:** 21.18 MB RSS (Bound: $\le 45.0\text{ MB}$), Idle CPU: $\sim 0.0\%$  

---

## 1. Executive Summary

Following the release of **v0.2.3** (Initial Window Maximize Auto-Nudging & Debounce Hardening), this codebase audit was executed in accordance with [.agents/skills/codebase-audit-refactor](../../.agents/skills/codebase-audit-refactor/SKILL.md).

The codebase exhibits strong architectural discipline, zero compiler warnings under Swift 6 strict concurrency, 100% test pass rate across 18 test suites, and strict isolation between pure Swift business logic and AppKit/Accessibility subsystems.

Key areas identified for refactoring and cleanup prior to embarking on **Phase 3 (v0.3.0: Window Re-ordering & Grouping)**:
1. **Dead Code Retirement:** `StatusMenu.onThemeChanged` is a legacy enum-based callback superseded by `onThemeIdChanged(String)`.
2. **Button Boilerplate Duplication:** Four distinct button classes (`TaskButton`, `PinnedButton`, `StartButton`, `OverflowButton`) duplicate identical `NSTrackingArea` and hover/press state management (~100 LOC redundancy).
3. **Directory Organization:** `Sources/TaskbarKit/UI/` contains 10 flat files mixing buttons, panels, managers, and drawing helpers.
4. **Architectural Decoupling for Phase 3:** Layout frame computations in `TaskbarView.layoutComponents()` should be extracted into a pure Swift `TaskbarLayoutEngine` within `TaskbarCore`, enabling headless unit testing for drag-and-drop slot indexing and window grouping.

---

## 2. Stage 1: Codebase Survey & Structural Inventory

### 2.1 Target Breakdown & Volume
```
┌────────────────────────────────────────────────────────────────────────┐
│ Target                 Files   Lines (approx)  Responsibilities        │
├────────────────────────────────────────────────────────────────────────┤
│ Sources/TaskbarCore       18            2,450  Pure models, math,      │
│                                                stores, themes, config  │
│ Sources/TaskbarKit        19            2,750  AppKit UI, AX tracking, │
│                                                work area enforcer      │
│ Sources/TaskbarApp         1               35  Minimal main entry      │
│ Tests/TaskbarCoreTests    12            1,450  Pure Swift unit suites  │
│ Tests/IntegrationTests     8            2,350  AX & UI lifecycle suites│
├────────────────────────────────────────────────────────────────────────┤
│ Total                     58            9,035                          │
└────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Directory Structure Analysis
- **`Sources/TaskbarCore/`**: Well-organized into `Config/`, `Logging/`, `Logic/`, and `Model/`.
- **`Sources/TaskbarKit/`**:
  - `Actions/`: `WindowActions.swift` (Clean).
  - `System/`: `AccessibilityPermission.swift`, `DockController.swift`, `Launcher.swift` (Clean).
  - `Tracking/`: `AXAppObserver.swift`, `AXElement+Attributes.swift`, `AXThread.swift`, `AppTracker.swift`, `WorkAreaEnforcer.swift` (Clean separation of AX thread dispatch and work area enforcement).
  - `UI/`: 10 files residing in a flat structure (`BevelDrawing`, `IconCache`, `OverflowButton`, `PinnedButton`, `ScreenManager`, `StartButton`, `TaskButton`, `TaskbarPanel`, `TaskbarView`, `VisualEffectMapping`).
  - Target root: `StatusMenu.swift`, `AppDelegate.swift`.

---

## 3. Stage 2: Architectural Boundaries & Modularity

### 3.1 `TaskbarCore` Purity Verification
Grep analysis confirmed **zero** forbidden imports in `Sources/TaskbarCore/`:
- `import AppKit`: 0 occurrences.
- `import ApplicationServices`: 0 occurrences.
- `AXUIElement`: 0 occurrences.

`TaskbarCore` remains 100% pure Swift, fully testable on Linux or headless macOS environments without AppKit dependencies.

### 3.2 Dependency Flow & DAG Integrity
The target dependency graph forms a clean Directed Acyclic Graph (DAG):
$$\text{TaskbarCore} \longleftarrow \text{TaskbarKit} \longleftarrow \text{TaskbarApp}$$

- `TaskbarCore` has zero outward dependencies on other targets.
- `TaskbarKit` imports `TaskbarCore`.
- `TaskbarApp` imports `TaskbarKit` and `TaskbarCore`, containing only `main.swift` bootstrap code.
- No circular dependencies exist.

---

## 4. Stage 3: Code Hygiene, Dead Code & Deduplication

### 4.1 Dead Code Identification: `StatusMenu.onThemeChanged`
- **Location:** [StatusMenu.swift](../../Sources/TaskbarKit/StatusMenu.swift#L19)
- **Current Declaration:** `public var onThemeChanged: ((ThemeStyle) -> Void)?`
- **Analysis:**
  - In earlier versions (v0.1.x), themes were identified solely by the `ThemeStyle` enum (`.modernHybrid`, `.retroClassic`).
  - With the v0.2.0 theme expansion system, all themes are identified by a string ID (`ThemeDefinition.id`), managed via `ThemeRegistry` and dispatched through `onThemeIdChanged: ((String) -> Void)?`.
  - `AppDelegate.swift` exclusively binds `onThemeIdChanged`.
  - `onThemeChanged` is never consumed by the application. The only remaining reference was a negative regression assertion in `StatusMenuThemeTests.swift`.
- **Recommendation:** Retire `onThemeChanged` completely. Remove the callback, internal dispatch points, and update tests.

### 4.2 Button Boilerplate Duplication
- **Affected Files:**
  - `TaskButton.swift` (268 LOC)
  - `PinnedButton.swift` (246 LOC)
  - `StartButton.swift` (194 LOC)
  - `OverflowButton.swift` (144 LOC)
- **Duplicated Patterns:**
  1. **Tracking Area Management:** Identical `NSTrackingArea` instantiation (`[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]`), invalidation, and attachment in `updateTrackingAreas()`.
  2. **Mouse Hover/Press Lifecycle:** Identical `mouseEntered`, `mouseExited`, `mouseDown`, and `mouseUp` handlers managing `isHovered` and `isPressed` with `needsDisplay = true`.
  3. **WantsLayer & Geometry Setup:** Identical initialization patterns.
- **Recommendation:** Extract `BaseTaskbarButton: NSView` in `Sources/TaskbarKit/UI/Buttons/BaseTaskbarButton.swift` encapsulating tracking areas, hover state, and press tracking.

### 4.3 `TaskbarKit/UI/` Directory Clutter
Grouping the flat 10-file UI directory into logical subpackages enhances discoverability:
```
Sources/TaskbarKit/UI/
├── Buttons/
│   ├── BaseTaskbarButton.swift   (New shared base class)
│   ├── TaskButton.swift
│   ├── PinnedButton.swift
│   ├── StartButton.swift
│   └── OverflowButton.swift
├── Panels/
│   ├── TaskbarPanel.swift
│   ├── TaskbarView.swift
│   └── BevelDrawing.swift
├── Menu/
│   └── StatusMenu.swift          (Moved from TaskbarKit root)
└── Management/
    ├── ScreenManager.swift
    ├── IconCache.swift
    └── VisualEffectMapping.swift
```

---

## 5. Stage 4: Conventions, Concurrency & Safety Verification

### 5.1 Swift 6 Strict Concurrency
- All UI classes (`TaskbarView`, `TaskbarPanel`, `StatusMenu`, buttons) are properly annotated with `@MainActor`.
- Classes marked `@unchecked Sendable` (`WorkAreaEnforcer`, `AXAppObserver`, `TestFixtureApp`) correctly synchronize state with `NSLock`.
- Background tasks (`permissionPollTask` in `AppTracker`) are cancelled during deinit and teardown.

### 5.2 Accessibility Thread Containment
- Invariant confirmed: Zero `AXUIElement*` calls on the main thread.
- All AX queries and modifications route through `AXThread.shared.performAsync` or `performSync` with explicit timeouts ($0.3\text{s}$).

### 5.3 Privacy & Path Hygiene
- Grep scan for `/Users/` paths confirmed zero personal developer paths, usernames, or absolute host references across the entire repository.

---

## 6. Stage 5: Documentation & Plan Synchronization

### 6.1 Documentation Reconciliation Complete
- Redundant versioned directories (`docs/v0.0.0/`, `docs/v0.1.0/`, `docs/v0.1.1/`, `docs/v0.2.0/`) were consolidated into canonical, evergreen documents at the root of `docs/`:
  - `docs/ARCHITECTURE.md`
  - `docs/BUILD_AND_RELEASE.md`
  - `docs/CONFIGURATION.md`
  - `docs/CONVENTIONS.md`
  - `docs/TESTING.md`
  - `docs/TEST_SPECIFICATIONS.md`
- `README.md`, `CHANGELOG.md`, and skill references are fully synchronized.

### 6.2 Milestone Plans
- `plans/v0.2.0` renamed to `plans/v0.2.X/` to encapsulate patch releases v0.2.1, v0.2.2, and v0.2.3.
- `plans/roadmap.md` marks Phase 2 (v0.2.0 – v0.2.3) as 100% complete.
- `plans/v0.3.X/` created for Phase 3 planning.

---

## 7. Stage 6: Actionable Refactoring Recommendations

| Risk Tier | Task | Description | Target Files |
|---|---|---|---|
| **Low Risk** | Retire `onThemeChanged` | Remove dead legacy enum callback from `StatusMenu`, update tests | `StatusMenu.swift`, `StatusMenuThemeTests.swift` |
| **Low Risk** | Reorganize `TaskbarKit/UI/` | Subdivide flat UI directory into `Buttons/`, `Panels/`, `Menu/`, `Management/` | `Sources/TaskbarKit/UI/` |
| **Medium Risk** | Extract `BaseTaskbarButton` | Consolidate `NSTrackingArea`, `isHovered`, and `isPressed` state handling into a shared base class | `BaseTaskbarButton.swift`, `TaskButton.swift`, `PinnedButton.swift`, `StartButton.swift`, `OverflowButton.swift` |
| **High Risk (v0.3.0 Enabler)** | Extract `TaskbarLayoutEngine` | Move layout math out of `TaskbarView` into pure Swift `TaskbarCore` struct with full headless test suite | `TaskbarCore/Logic/TaskbarLayoutEngine.swift`, `TaskbarView.swift`, `TaskbarLayoutEngineTests.swift` |

---

## 8. Verification & Performance Baseline

The test harness was executed with all 104 tests passing:

```
======================================================
   Test Execution Summary
======================================================
Mode:          all
Duration:      62s
Suites:        18 (10 Unit, 8 Integration)
Tests:         104 (71 Unit, 33 Integration)
Pass Rate:     100% (0 Failures)
Taskbar RSS:   19.90 MB (Baseline) -> 21.18 MB (Post-test)
Memory Bound:  Within 45.0 MB bound (Delta: +1.28 MB)
Taskbar CPU:   2.2% during peak test load (Idle: ~0.0%)
======================================================
```

A detailed, phased execution plan for these refactorings is drafted in [refactoring_implementation_plan.md](./refactoring_implementation_plan.md).
