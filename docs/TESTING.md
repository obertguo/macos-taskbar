# Taskbar Testing Guide

This guide documents the automated testing infrastructure, test execution modes, test fixture architecture, and performance verification standards for **Taskbar**.

---

## 1. Testing Philosophy & 3-Tier Hierarchy

Taskbar employs a 3-tier testing strategy ensuring 100% test coverage across core algorithms, system integrations, and load longevity:

| Tier | Scope | Framework | Execution Target | Typical Duration |
|---|---|---|---|---|
| **Tier 1: Unit Tests** | Core math, clamping, JSON codecs, theme presets, file loader, pinned app domain models, settings. | `Swift Testing` | `Tests/TaskbarCoreTests` | $< 0.05\text{s}$ |
| **Tier 2: Integration Tests** | Deterministic lifecycle, live window lifecycle, AX router & circuit breaker, work area enforcer, dock service, view recycling, pinned apps, accessibility buttons. | `Swift Testing` | `Tests/TaskbarIntegrationTests` | $0.2\text{s} - 25\text{s}$ |
| **Tier 3: Stress & Benchmark Runner** | 100-window burst capacity, overflow chevron activation, RSS memory bounds (<45MB), CPU bounds. | Bash / `scripts/test-functional.sh` | CLI / CI Suite | $10\text{s} - 40\text{s}$ |

---

## 2. Test Execution Quickstart

The primary interface for test execution is the fail-fast orchestration script [`scripts/test-functional.sh`](../scripts/test-functional.sh).

### Available Modes:

```bash
# 1. Run quick real-window lifecycle tests (TC-FUNC-*, ~15s)
./scripts/test-functional.sh --quick

# 2. Run boundary & corner cases suite (TC-EDGE-*, ~2s)
./scripts/test-functional.sh --edge-cases

# 3. Run high-density window stress tests & memory/CPU benchmarks (TC-STRESS-*, TC-PERF-*)
./scripts/test-functional.sh --stress

# 4. Run drag-and-drop slot reordering suite (TC-DRAG-*)
./scripts/test-functional.sh --reordering

# 5. Run application window grouping & popup suite (TC-GROUP-*)
./scripts/test-functional.sh --grouping

# 6. Run the entire test suite (Unit + Functional + Edge + Stress + Pinned + Themes + Reordering + Grouping, default)
./scripts/test-functional.sh --all

# 7. Direct SwiftPM test execution across all targets
swift test
```

---

## 3. Test Suites & Taxonomy

All test cases are formally specified in [`docs/TEST_SPECIFICATIONS.md`](TEST_SPECIFICATIONS.md).

### 3.1 Core Unit Tests (`Tests/TaskbarCoreTests/` — 16 Suites, 121 Tests)
All core tests are written in pure `Swift Testing` (`@Suite`, `@Test`, `#expect`):
- `TaskbarLayoutEngineTests`: Pure geometry plan calculations, empty/pinned/standard layouts, compression, overflow reservation, slot hit testing, and horizontal axis slot/indicator calculations (`TC-UNIT-014`, 8 test cases).
- `TaskbarLayoutEngineDragTests`: Drag insertion slot math, boundary clamping, and indicator line coordinates for task and pinned items (`TC-UNIT-012`, 6 test cases).
- `WindowGroupingLogicTests`: Grouping rules across `always`, `whenCrowded`, and `never`, single-window apps, empty window lists, and group derived states (`TC-UNIT-005` – `TC-UNIT-008`, 6 test cases).
- `WindowOrderingLogicTests`: Reordering slot shifts, manual order persistence across incoming windows, closed window order pruning, and empty inputs (`TC-UNIT-009` – `TC-UNIT-011`, 4 test cases).
- `WorkAreaMathTests`: Clamping math, vertical maximization checks, multi-monitor coordinates, subpixel overlap tolerances, and multi-edge screen clamping (`TC-UNIT-013`, 14 test cases).
- `ClickPolicyTests`: Taskbar click dispatch rules across unfocused, focused, minimized, hidden, and frontmost windows (5 test cases).
- `ButtonLayoutTests`: Spacious, compressing, icon-only, overflow width calculations, and custom title visibility thresholds (6 test cases).
- `WindowFilterTests`: Normal app inclusion, modal sheet rejection, 0x0 minimized preservation, system overlay exclusion (5 test cases).
- `ThemePresetsTests`: Modern Hybrid, Retro Classic, Windows XP Luna, and Dark Minimal presets, JSON round-trips, and contrast checks (7 test cases).
- `ThemeTests`: Theme definition properties, JSON serialization round-trips, ThemeMaterials material/blendingMode decoding, and theme registry built-ins and collision rejection matrix (8 test cases).
- `ThemeFileLoaderTests`: Directory discovery, custom JSON deserialization with material/blendingMode, missing defaults tolerance, non-JSON filtering, built-in ID collision rejection, corrupted JSON resilience, export routines, and registry synchronization (11 test cases).
- `PinnedAppTests`: PinnedApp model serialization, missing fields fallback, duplicate pin rejection, unpinning, reordering boundary checks, and UserDefaults storage (9 test cases).
- `SettingsTests`: Default values, serialization, UserDefaults persistence, backward compatibility with v0.1 payloads, strings, presets, window grouping mode, and TaskbarEdge domain serialization (`TC-UNIT-015`, 10 test cases).
- `WindowStoreTests`: Window ordering, display assignment, sync snapshot reconciliation, full-screen transitions (4 test cases).
- `ScreenAssignmentTests`: Primary/secondary monitor boundary partitioning (3 test cases).
- `TaskbarCoreTests`: Build configuration sanity checks (1 test case).

### 3.2 Integration Suites (`Tests/TaskbarIntegrationTests/` — 16 Suites, 96 Tests)
- **Deterministic Lifecycle Suite (`DeterministicLifecycleTests.swift` — 7 Tests):**
  - Ultra-fast (<20ms total) headless simulation of full window lifecycle via `FakeWindowSource` and `SpyWindowActions` (`TC-FUNC-001` through `TC-FUNC-007`).
- **Live Window Lifecycle Suite (`WindowLifecycleIntegrationTests.swift` — 7 Tests, Gated via `TASKBAR_RUN_LIVE_AX_TESTS=1`):**
  - `TC-FUNC-001`: Real TextEdit window creation and store discovery.
  - `TC-FUNC-002`: Window minimization state tracking via AX notification.
  - `TC-FUNC-003`: Window restoration and deminiaturization state tracking.
  - `TC-FUNC-004`: Window focus targeting specific window without raising other windows.
  - `TC-FUNC-005`: Dynamic window title mutation reflection.
  - `TC-FUNC-006`: Window close event teardown and button cleanup.
  - `TC-FUNC-007`: Application termination and observer cleanup.
- **AX Event Router & Circuit Breaker Suite (`AXEventRouterAndCircuitBreakerTests.swift` — 7 Tests):**
  - Batched attribute fetching via `AXUIElementCopyMultipleAttributeValues`.
  - WindowID `nil` on dead handles (zero `CFHash` corruption).
  - Destroyed element recovery via `CFEqual` lookup.
  - Per-PID circuit breaker backoff & fast-path bypass.
  - Tier 1 single-window delta updates & Tier 2 dirty PID reconciles.
  - $O(1)$ window element cache lookup.
- **WorkAreaEnforcer Suite (`WorkAreaEnforcerTests.swift` — 7 Tests):**
  - Single-timer 3-pass stepping (150ms / 400ms / 650ms).
  - Monotonic clock interval checks without GCD contention.
  - User mouse-down clamping deferral and release execution.
  - Full-screen window exclusion and non-maximized drag clamping.
  - Cleanup on window destroy and PID termination.
- **DockController Suite (`DockControllerTests.swift` — 9 Tests):**
  - In-process `CFPreferences` autohide reading.
  - Serial background queue writes with monotonic debouncing.
  - Dirty session sentinel file persistence (`~/.config/taskbar/.dock_session_dirty`).
  - Crash recovery restoration on initial launch.
- **AppEnvironment Suite (`AppEnvironmentTests.swift` — 14 Tests):**
  - `SystemUptimeClock` and thread-safe `TestClock` time advancement.
  - `MainScheduler`, `AXThreadScheduler`, and `TestScheduler` task scheduling & cancellation.
  - `LiveWindowActions` and `SpyWindowActions` invocation recording.
  - `LiveDockService` and `MockDockService` call counting.
  - `AppEnvironment` thread-safe swapping and current configuration.
- **Accessibility Buttons Suite (`AccessibilityButtonsTests.swift` — 5 Tests):**
  - `BaseTaskbarButton` element, `.button` role, tooltip label, and `accessibilityPerformPress()` execution.
  - `TaskButton` dynamic `group.displayTitle` label, single and grouped states.
  - `PinnedButton` `pinnedApp.displayName` label and pin update synchronization.
  - `StartButton` "Start" label and press handler.
  - `OverflowButton` "Overflow Items" label and press handler.
- **Edge Cases Suite (`EdgeCasesIntegrationTests.swift` — 6 Tests):**
  - `TC-EDGE-001`: Zero-size (0x0) frame filtering for minimized Chromium/Electron windows.
  - `TC-EDGE-002`: Modal sheet and system dialog subrole rejection (`AXSheet`, `AXDialog`).
  - `TC-EDGE-003`: Rapid title churn and 50ms debounce coalescing under 25-event bursts.
  - `TC-EDGE-004`: Multi-screen boundary coordinate partitioning.
  - `TC-EDGE-005`: Full-screen window resize debounce and animation settle clamping.
  - `TC-EDGE-006`: Immediate initial maximize nudging with custom bar height without defocus.
- **Stress & Capacity Suite (`StressIntegrationTests.swift` — 3 Tests):**
  - `TC-STRESS-001`: 100-window high-density window store burst.
  - `TC-STRESS-002`: TaskbarView overflow chevron activation when buttons reach `minButtonWidth`.
  - `TC-PERF-001`: In-place button view recycling preserving view instances and tracking areas.
- **Window Reordering & Drag Suite (`WindowReorderingIntegrationTests.swift` — 4 Tests):**
  - `TC-DRAG-001`: Dragging task button beyond threshold reorders slots and updates layout.
  - `TC-DRAG-002`: Vertical mouse escape and Escape key cancel drag session cleanly.
  - `TC-DRAG-003`: Multi-display drag isolation maintains independent custom ordering per monitor.
  - `TC-DRAG-004`: Dragging pinned button reorders Settings.pinnedApps and syncs across all displays in lockstep.
- **Window Grouping & Popup Suite (`WindowGroupingIntegrationTests.swift` — 6 Tests):**
  - `TC-GROUP-001`: Multi-window application aggregates into single button with badge counter.
  - `TC-GROUP-002`: Group button click presents window list popup with matching titles.
  - `TC-GROUP-003`: Selecting window in popup triggers selection, focuses target window, and dismisses panel.
  - `TC-GROUP-004`: Dynamic grouping mode switching via ScreenManager reconfigures taskbar layout across all displays.
  - `TC-GROUP-005`: Popup mouse interaction, close button trigger, and dynamic resize.
  - `TC-GROUP-006`: Popup dismissal on loss of key focus or outside interaction.
- **Pinned Applications Suite (`PinnedAppsIntegrationTests.swift` — 9 Tests):**
  - `BaseTaskbarButton` mouse tracking, hover state mutation, and configurable click dispatch.
  - `PinnedButton` properties, tracking, and dynamic context menu items.
  - `TaskbarView` pinned buttons layout, positioning, and square aspect ratio.
  - `TaskbarView` view recycling preserving existing `PinnedButton` instances.
  - `TaskButton` dynamic "Pin to Taskbar" / "Unpin from Taskbar" context menu toggle.
  - Running indicator dot state transitions when target application opens/closes windows.
  - `ScreenManager` multi-display synchronization of pin and unpin actions across all panels.
  - `IconCache` bundle ID and fallback resolution.
  - `IconCache` multi-resolution icon preparation sanitizing legacy 1x corrupt assets.
- **Theme Expansion Suite (`ThemeExpansionIntegrationTests.swift` — 5 Tests):**
  - Dynamic switching to Windows XP Luna and Dark Minimal presets across all display panels.
  - `ThemeFileLoader` discovery of valid custom JSON and graceful handling of corrupted JSON files.
  - `ScreenManager` dynamic application of custom JSON themes and preservation of custom layout metrics (`barHeight`, `minButtonWidth`, `buttonSpacing`, `fontSize`, `iconSize`).
  - `VisualEffectMapping` resolution of AppKit materials and blending modes with normalization, hyphen tolerance, and safe fallbacks.
  - `ScreenManager` and `TaskbarView` dynamic adoption of custom `material` and `blendingMode` across all display panels.
- **Status Menu Theme Suite (`StatusMenuThemeTests.swift` — 4 Tests):**
  - Submenu structure validating built-in presets and disk action items.
  - Dynamic menu item updates when custom themes are registered.
  - Callback invocation when triggering "Reload Themes from Disk".
  - Custom theme selection notifying `onThemeIdChanged` and maintaining checkmark state without legacy Modern Hybrid fallback.
- **Status Menu Window Grouping Suite (`StatusMenuGroupingTests.swift` — 4 Tests):**
  - Submenu structure containing Always, When Crowded, and Never items with initial checkmark.
  - Menu checkmark state reflects initial mode configuration.
  - Selecting a grouping mode triggers `onWindowGroupingModeChanged` and updates menu checkmarks.
  - Programmatic `updateWindowGroupingMode` synchronizes property and menu item states.
- **TaskButton Context Menu Suite (`TaskButtonContextMenuTests.swift` — 3 Tests):**
  - Single unminimized window right click triggers `onMinimizeOrRestore`, not `onClick`.
  - Context menu title switches dynamically between "Minimize" and "Restore".
  - Grouped window button right click invokes minimize/restore without triggering group popup.

---

## 4. Test Fixtures & Clean Teardown

- **Fixture App:** System `TextEdit` application (`bundleID: "com.apple.TextEdit"`).
- **Automation Protocol:** Governed by `TestFixtureApp` in `Tests/TaskbarIntegrationTests/Helpers/TestFixtureApp.swift`.
- **Dynamic Window Polling:** `waitForWindowElement(index:timeoutSeconds:)` dynamically polls up to 3.0 seconds for the window element to register in the macOS Accessibility hierarchy, eliminating timing flakiness under system load or screensaver wake.
- **Process Teardown Draining:** `TestFixtureApp.terminateApp` drains `NSWorkspace.shared.runningApplications` for up to 1.0 second, guaranteeing terminating instances are fully unhooked before launching new test fixtures.
- **Suite Serialization:** Both `WindowLifecycleIntegrationTests` and `EdgeCasesIntegrationTests` run with the `.serialized` trait to prevent concurrent test cases from colliding when manipulating the singleton system fixture.
- **Guaranteed Cleanup:** All tests employ `defer { fixture.terminate() }` blocks. The test runner script also traps process exit (`trap cleanup_fixtures EXIT`) to guarantee zero orphan processes.
