# Taskbar Testing Guide (v0.2.0)

This guide documents the automated testing infrastructure, test execution modes, test fixture architecture, and performance verification standards for **Taskbar** v0.2.0.

---

## 1. Testing Philosophy & 3-Tier Hierarchy

Taskbar employs a 3-tier testing strategy ensuring 100% test coverage across core algorithms, system integrations, and load longevity:

| Tier | Scope | Framework | Execution Target | Typical Duration |
|---|---|---|---|---|
| **Tier 1: Unit Tests** | Core math, clamping, JSON codecs, theme presets, file loader, pinned app domain models, settings. | `XCTest` / `SwiftPM` | `Tests/TaskbarCoreTests` | $< 0.06\text{s}$ |
| **Tier 2: Integration Tests** | Real-window lifecycle, 0x0 frame rules, modal sheets, rapid debouncing, view recycling, pinned apps bar, theme expansion, status menu. | `Swift Testing` | `Tests/TaskbarIntegrationTests` | $0.2\text{s} - 25\text{s}$ |
| **Tier 3: Stress & Benchmark Runner** | 100-window burst capacity, overflow chevron activation, RSS memory bounds (<45MB), CPU bounds. | Bash / `scripts/test-functional.sh` | CLI / CI Suite | $10\text{s} - 40\text{s}$ |

---

## 2. Test Execution Quickstart

The primary interface for test execution is the fail-fast orchestration script [`scripts/test-functional.sh`](../../scripts/test-functional.sh).

### Available Modes:

```bash
# 1. Run quick real-window lifecycle tests (TC-FUNC-*, ~15s)
./scripts/test-functional.sh --quick

# 2. Run boundary & corner cases suite (TC-EDGE-*, ~2s)
./scripts/test-functional.sh --edge-cases

# 3. Run high-density window stress tests & memory/CPU benchmarks (TC-STRESS-*, TC-PERF-*)
./scripts/test-functional.sh --stress

# 4. Run the entire test suite (Unit + Functional + Edge + Stress + Pinned + Themes, default)
./scripts/test-functional.sh --all

# 5. Direct SwiftPM test execution across all targets
swift test
```

---

## 3. Test Suites & Taxonomy

All test cases are formally specified in [`docs/v0.2.0/TEST_SPECIFICATIONS.md`](TEST_SPECIFICATIONS.md).

### 3.1 Core Unit Tests (`Tests/TaskbarCoreTests/` — 69 Tests)
- `WorkAreaMathTests`: Clamping math, vertical maximization checks, multi-monitor coordinates, subpixel overlap tolerances (10 test cases).
- `ClickPolicyTests`: Taskbar click dispatch rules across unfocused, focused, minimized, hidden, and frontmost windows (5 test cases).
- `ButtonLayoutTests`: Spacious, compressing, icon-only, overflow width calculations, and custom title visibility thresholds (6 test cases).
- `WindowFilterTests`: Normal app inclusion, modal sheet rejection, 0x0 minimized preservation, system overlay exclusion (5 test cases).
- `ThemePresetsTests`: Modern Hybrid, Retro Classic, Windows XP Luna, and Dark Minimal presets, JSON round-trips, and contrast checks (7 test cases).
- `ThemeTests`: Theme definition properties, JSON serialization round-trips, and theme registry built-ins (5 test cases).
- `ThemeFileLoaderTests`: Directory discovery, custom JSON deserialization, missing defaults tolerance, non-JSON filtering, built-in ID collision rejection, corrupted JSON resilience, export routines, and registry synchronization (8 test cases).
- `PinnedAppTests`: PinnedApp model serialization, missing fields fallback, duplicate pin rejection, unpinning, reordering boundary checks, and UserDefaults storage (9 test cases).
- `SettingsTests`: Default values, serialization, UserDefaults persistence, backward compatibility with v0.1 payloads, strings, and presets (6 test cases).
- `WindowStoreTests`: Window ordering, display assignment, sync snapshot reconciliation, full-screen transitions (4 test cases).
- `ScreenAssignmentTests`: Primary/secondary monitor boundary partitioning (3 test cases).
- `TaskbarCoreTests`: Build configuration sanity checks (1 test case).

### 3.2 Integration Suites (`Tests/TaskbarIntegrationTests/` — 30 Tests)
- **Window Lifecycle Suite (`WindowLifecycleIntegrationTests.swift` — 7 Tests):**
  - `TC-FUNC-001`: Window creation and store discovery within $\le 3\text{s}$.
  - `TC-FUNC-002`: Window minimization state tracking via AX notification.
  - `TC-FUNC-003`: Window restoration and deminiaturization state tracking.
  - `TC-FUNC-004`: Window focus targeting specific window without raising other windows of the same application.
  - `TC-FUNC-005`: Dynamic window title mutation reflection.
  - `TC-FUNC-006`: Window close event teardown and button cleanup.
  - `TC-FUNC-007`: Application termination and observer cleanup.
- **Edge Cases Suite (`EdgeCasesIntegrationTests.swift` — 5 Tests):**
  - `TC-EDGE-001`: Zero-size (0x0) frame filtering for minimized Chromium/Electron windows.
  - `TC-EDGE-002`: Modal sheet and system dialog subrole rejection (`AXSheet`, `AXDialog`).
  - `TC-EDGE-003`: Rapid title churn and 50ms debounce coalescing under 25-event bursts.
  - `TC-EDGE-004`: Multi-screen boundary coordinate partitioning.
  - `TC-EDGE-005`: Full-screen window resize debounce and animation settle clamping.
- **Stress & Capacity Suite (`StressIntegrationTests.swift` — 3 Tests):**
  - `TC-STRESS-001`: 100-window high-density window store burst.
  - `TC-STRESS-002`: TaskbarView overflow chevron activation when buttons reach `minButtonWidth`.
  - `TC-PERF-001`: In-place button view recycling preserving view instances and tracking areas.
- **Pinned Applications Suite (`PinnedAppsIntegrationTests.swift` — 8 Tests):**
  - `PinnedButton` properties, tracking, and dynamic context menu items.
  - `TaskbarView` pinned buttons layout, positioning, and square aspect ratio.
  - `TaskbarView` view recycling preserving existing `PinnedButton` instances.
  - `TaskButton` dynamic "Pin to Taskbar" / "Unpin from Taskbar" context menu toggle.
  - Running indicator dot state transitions when target application opens/closes windows.
  - `ScreenManager` multi-display synchronization of pin and unpin actions across all panels.
  - `IconCache` bundle ID and fallback resolution.
  - `IconCache` multi-resolution icon preparation sanitizing legacy 1x corrupt assets.
- **Theme Expansion Suite (`ThemeExpansionIntegrationTests.swift` — 3 Tests):**
  - Dynamic switching to Windows XP Luna and Dark Minimal presets across all display panels.
  - `ThemeFileLoader` discovery of valid custom JSON and graceful handling of corrupted JSON files.
  - `ScreenManager` dynamic application of custom JSON themes and preservation of custom layout metrics (`barHeight`, `minButtonWidth`, `buttonSpacing`, `fontSize`, `iconSize`).
- **Status Menu Theme Suite (`StatusMenuThemeTests.swift` — 4 Tests):**
  - Submenu structure validating built-in presets and disk action items.
  - Dynamic menu item updates when custom themes are registered.
  - Callback invocation when triggering "Reload Themes from Disk".
  - Custom theme selection notifying `onThemeIdChanged` and maintaining checkmark state without legacy Modern Hybrid fallback.

---

## 4. Test Fixtures & Clean Teardown

- **Fixture App:** System `TextEdit` application (`bundleID: "com.apple.TextEdit"`).
- **Automation Protocol:** Governed by `TestFixtureApp` in `Tests/TaskbarIntegrationTests/Helpers/TestFixtureApp.swift`.
- **Serialization:** `WindowLifecycleIntegrationTests` runs with `.serialized` trait to prevent concurrent test runs from colliding when manipulating the singleton system fixture.
- **Guaranteed Cleanup:** All tests employ `defer { fixture.terminate() }` blocks. The test runner script also traps process exit (`trap cleanup_fixtures EXIT`) to guarantee zero orphan processes.
