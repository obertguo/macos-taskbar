# Taskbar Testing Guide (v0.1.1)

This guide documents the automated testing infrastructure, test execution modes, test fixture architecture, and performance verification standards for **Taskbar** v0.1.1.

---

## 1. Testing Philosophy & 3-Tier Hierarchy

Taskbar employs a 3-tier testing strategy ensuring 100% test coverage across core algorithms, system integrations, and load longevity:

| Tier | Scope | Framework | Execution Target | Typical Duration |
|---|---|---|---|---|
| **Tier 1: Unit Tests** | Core math, clamping, JSON codecs, theme registry, settings. | `XCTest` / `SwiftPM` | `Tests/TaskbarCoreTests` | $< 0.05\text{s}$ |
| **Tier 2: Integration Tests** | Real-window lifecycle, 0x0 frame rules, modal sheets, rapid debouncing, view recycling. | `Swift Testing` | `Tests/TaskbarIntegrationTests` | $0.2\text{s} - 5\text{s}$ |
| **Tier 3: Stress & Benchmark Runner** | 100-window burst capacity, overflow chevron activation, RSS memory bounds (<45MB), idle CPU. | Bash / `scripts/test-functional.sh` | CLI / CI Suite | $5\text{s} - 15\text{s}$ |

---

## 2. Test Execution Quickstart

The primary interface for test execution is the fail-fast orchestration script [`scripts/test-functional.sh`](../../scripts/test-functional.sh).

### Available Modes:

```bash
# 1. Run quick real-window lifecycle tests (TC-FUNC-*, ~15s)
./scripts/test-functional.sh --quick

# 2. Run boundary & corner cases suite (TC-EDGE-*, ~5s, no AX permission required)
./scripts/test-functional.sh --edge-cases

# 3. Run high-density window stress tests & memory/CPU benchmarks (TC-STRESS-*, TC-PERF-*)
./scripts/test-functional.sh --stress

# 4. Run the entire test suite (Unit + Functional + Edge + Stress, default)
./scripts/test-functional.sh --all

# 5. Direct SwiftPM test execution
swift test
```

---

## 3. Test Suites & Taxonomy

All test cases are formally specified in [`docs/v0.1.1/TEST_SPECIFICATIONS.md`](TEST_SPECIFICATIONS.md).

### 3.1 Unit Tests (`Tests/TaskbarCoreTests/`)
- `WorkAreaMathTests`: Clamping math, vertical maximization checks, multi-monitor coordinates, subpixel overlap tolerances (10 test cases).
- `WindowFilterTests`: Normal app inclusion, modal sheet rejection, 0x0 minimized preservation, system overlay exclusion (5 test cases).
- `ThemeTests`: Modern Hybrid and Retro Classic presets, JSON encoding/decoding round-trip, `ThemeRegistry` singleton registration and user theme import (5 test cases).
- `SettingsTests`: Default values, serialization, UserDefaults persistence, backward compatibility (5 test cases).
- `WindowStoreTests`: Window ordering, display assignment, sync snapshot reconciliation, full-screen transitions (4 test cases).
- `ScreenAssignmentTests`: Primary/secondary monitor boundary partitioning (3 test cases).

### 3.2 Integration Tests (`Tests/TaskbarIntegrationTests/`)
- **Window Lifecycle Suite (`WindowLifecycleIntegrationTests.swift`):**
  - `TC-FUNC-001`: Window creation and store discovery within $\le 3\text{s}$.
  - `TC-FUNC-002`: Window minimization state tracking via AX notification.
  - `TC-FUNC-003`: Window restoration and deminiaturization state tracking.
  - `TC-FUNC-005`: Dynamic title mutations updated without subview teardown.
  - `TC-FUNC-006`: Window close and store cleanup.
  - `TC-FUNC-007`: Application termination and observer teardown.
- **Edge Cases Suite (`EdgeCasesIntegrationTests.swift`):**
  - `TC-EDGE-001`: Minimized 0x0 frames (Chromium) preserved; non-minimized 0x0 frames rejected.
  - `TC-EDGE-002`: `AXSheet`, `AXDialog`, and `AXSystemDialog` modal subroles rejected.
  - `TC-EDGE-003`: 25 rapid title changes coalesced into $\le 2$ reconciliation ticks.
  - `TC-EDGE-004`: Dual-display boundary and window coordinate assignment.
- **Stress & Capacity Suite (`StressIntegrationTests.swift`):**
  - `TC-STRESS-001`: 100-window burst capacity and sequential lookup.
  - `TC-STRESS-002`: Overflow chevron (`»`) appears and overflow list populated when buttons exceed bar width.
  - `TC-PERF-001`: Pointer-equal view recycling (`recycledButton === initialButton`) during dynamic updates.

---

## 4. Test Fixture Architecture (`TestFixtureApp`)

Real macOS applications (`TextEdit`) are managed through [`TestFixtureApp.swift`](../../Tests/TaskbarIntegrationTests/Helpers/TestFixtureApp.swift):

```swift
// Example test pattern with deterministic cleanup
@Test("TC-FUNC-002: Window minimization state tracking")
func testWindowMinimization() async throws {
    guard AccessibilityPermission.isGranted() else { return }
    
    let store = WindowStore()
    let tracker = AppTracker(store: store)
    defer { tracker.stopTracking() }
    
    // Launch fixture with self-cleaning defer
    let fixture = try await TestFixtureApp.launchTextEdit(documentTitle: "MyTestDoc")
    defer { fixture.terminate() }
    
    // Mutate state
    try fixture.minimizeWindow(index: 1)
    
    // Await state propagation
    let minimized = await waitUntil(timeoutSeconds: 3.0) {
        store.allWindows.first(where: { $0.appName == "TextEdit" })?.isMinimized == true
    }
    #expect(minimized == true)
}
```

### Self-Cleaning Guarantees:
1. `defer { fixture.terminate() }` executes upon function exit even if assertions fail.
2. `deinit` in `TestFixtureApp` executes `tell application "TextEdit" to quit saving no`.
3. Pre-flight and `trap cleanup_fixtures EXIT` in `scripts/test-functional.sh` purge dangling fixture instances before and after script execution.

---

## 5. Performance & Resource Bounds

The test harness enforces strict resident memory and CPU thresholds sourced from `config/build.env`:

- **Peak Resident Memory (RSS):** Must remain $< 45.0\text{ MB}$ under 100-window load (Taskbar runs at $\sim 23\text{ MB}$).
- **Heap Recovery:** Post-test RSS must recover within $3.0\text{ MB}$ of baseline, verifying absence of ARC memory leaks.
- **CPU Utilization:** Average idle CPU must remain $< 0.1\%$; peak test burst CPU must not exceed `TEST_MAX_CPU_PERCENT` ($2.0\%$).

---

## 6. Pre-flight Requirements & Accessibility Permissions

1. **Operating System:** macOS 14.0 Sonoma or later.
2. **Accessibility Permissions:**
   - Real-window tests (`--quick`, `--all`) require Accessibility permission.
   - If not granted, `scripts/test-functional.sh` automatically prompts the user via macOS System Settings and waits up to `TEST_AX_AUTH_TIMEOUT_SECONDS` (15s) for authorization.
   - If authorization is withheld, the runner fails fast with clear terminal instructions.
