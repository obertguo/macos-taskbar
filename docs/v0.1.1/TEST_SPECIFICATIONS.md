# Taskbar Test Specifications & Traceability Catalog (v0.1.1)

This document provides the canonical specification catalog and requirements traceability matrix for the **Taskbar** testing suite. All automated regression, functional, edge-case, and performance tests adhere to these specifications.

---

## 1. Test Taxonomy & Classification

| Taxonomy Prefix | Category | Description | Primary Runner / Harness |
|---|---|---|---|
| `TC-FUNC-xxx` | Functional | End-to-end window lifecycle (launch, minimize, restore, focus, title update, close, quit). | `Tests/TaskbarIntegrationTests` + `scripts/test-functional.sh --quick` |
| `TC-EDGE-xxx` | Edge Cases | Boundary conditions (0x0 frames, modal sheets, rapid title churn, full-screen spaces). | `Tests/TaskbarIntegrationTests` + `scripts/test-functional.sh --edge-cases` |
| `TC-STRESS-xxx`| Stress & Load | High window density (50–100 windows), button overflow, chevron dropdown verification. | `scripts/test-functional.sh --stress` |
| `TC-PERF-xxx` | Performance | Memory bounds (peak RSS < 45 MB, leak recovery), idle CPU consumption (< 0.1%). | `scripts/test-functional.sh --stress` (Instrumentation) |
| `TC-UNIT-xxx` | Unit | Pure math, clamping algorithms, model codecs, settings persistence, theme registry. | `Tests/TaskbarCoreTests` (`swift test`) |

---

## 2. Test Specifications Catalog

### 2.1 Functional Window Lifecycle (`TC-FUNC-*`)

#### [TC-FUNC-001] Window Creation & Taskbar Button Detection
- **Category:** Functional / Lifecycle
- **Preconditions:** Taskbar running; Accessibility permissions granted; zero preexisting fixture windows.
- **Stimulus / Action:**
  1. Launch real GUI application fixture (`TextEdit`) via `NSWorkspace` or AppleScript with 1 document window.
  2. Await window appearance notification (`kAXWindowCreatedNotification` / `didLaunchApplicationNotification`).
- **Expected Outcome:**
  1. `AppTracker` discovers the process and subscribes an `AXAppObserver`.
  2. `WindowStore` adds the new window model.
  3. Taskbar view reflects the window within $\le 100\text{ms}$.
  4. Task button displays matching title and application icon.
- **Automated Verification:** `TC-FUNC-001` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Window button present in `WindowStore.orderedWindows` and taskbar within 100ms.

---

#### [TC-FUNC-002] Window Minimization State Tracking
- **Category:** Functional / Window State
- **Preconditions:** Fixture app running with 1 visible window tracked on Taskbar.
- **Stimulus / Action:**
  1. Programmatically minimize window via AX (`kAXWindowMiniaturizedNotification`) or AppleScript (`set miniaturized of window 1 to true`).
  2. Await debounce threshold (50ms).
- **Expected Outcome:**
  1. Window element reports `isMinimized == true`.
  2. `WindowStore` marks `WindowInfo.isMinimized = true`.
  3. Corresponding `TaskButton` renders minimized visual state (subtle opacity / dimmed styling).
- **Automated Verification:** `TC-FUNC-002` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** `isMinimized` attribute true in `WindowStore` and button visual state updated within 100ms.

---

#### [TC-FUNC-003] Window Restoration / Deminiaturization State Tracking
- **Category:** Functional / Window State
- **Preconditions:** Fixture app window is currently minimized.
- **Stimulus / Action:**
  1. Trigger window restore via AX (`kAXWindowDeminiaturizedNotification`) or AppleScript (`set miniaturized of window 1 to false`).
  2. Await debounce threshold (50ms).
- **Expected Outcome:**
  1. Window element reports `isMinimized == false`.
  2. `WindowStore` marks `WindowInfo.isMinimized = false`.
  3. `TaskButton` updates to normal (or active) visual state.
- **Automated Verification:** `TC-FUNC-003` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Window button reflects un-minimized state within 100ms.

---

#### [TC-FUNC-004] Active Window Focus Tracking
- **Category:** Functional / Focus State
- **Preconditions:** Two distinct fixture windows active (e.g. Doc A and Doc B).
- **Stimulus / Action:**
  1. Focus Doc A via `AXUIElementSetAttributeValue(..., kAXMainAttribute)`.
  2. Verify Taskbar button for Doc A is marked active (`isFocused == true`) and Doc B is inactive.
  3. Focus Doc B via AppleScript `set index of window "Doc B" to 1`.
- **Expected Outcome:**
  1. `kAXFocusedWindowChangedNotification` fires.
  2. Taskbar button for Doc B transitions to active/highlighted state.
  3. Taskbar button for Doc A transitions to normal/inactive state.
- **Automated Verification:** `TC-FUNC-004` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Exactly one window marked `isFocused` at any moment; focus switches within 100ms.

---

#### [TC-FUNC-005] Dynamic Window Title Mutation
- **Category:** Functional / Title Updates
- **Preconditions:** Fixture window open with initial title `"InitialTitle"`.
- **Stimulus / Action:**
  1. Mutate window document title to `"UpdatedTitle"` via AppleScript or AX.
  2. Await debounce threshold (50ms).
- **Expected Outcome:**
  1. `kAXTitleChangedNotification` is received by `AXAppObserver`.
  2. `WindowInfo.title` updates to `"UpdatedTitle"`.
  3. `TaskButton` text label updates in-place via view recycling without subview recreation.
- **Automated Verification:** `TC-FUNC-005` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Button title string equals `"UpdatedTitle"` within 100ms; button view instance identity preserved.

---

#### [TC-FUNC-006] Window Close & Taskbar Button Teardown
- **Category:** Functional / Lifecycle Teardown
- **Preconditions:** Multiple fixture windows open across one or more applications.
- **Stimulus / Action:**
  1. Close 1 specific window via `kAXPressAction` on close button or AppleScript `close window 1`.
  2. Await notification (`kAXUIElementDestroyedNotification`).
- **Expected Outcome:**
  1. Window removed from `WindowStore`.
  2. Associated `TaskButton` removed from `TaskbarView`.
  3. Remaining task buttons smoothly reflow / expand to claim available width.
- **Automated Verification:** `TC-FUNC-006` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Window count decreases by exactly 1; no orphaned buttons.

---

#### [TC-FUNC-007] Application Termination & Observer Teardown
- **Category:** Functional / Process Termination
- **Preconditions:** Fixture app running with 2 open windows.
- **Stimulus / Action:**
  1. Terminate fixture application (`NSRunningApplication.terminate()`).
  2. Await `NSWorkspace.didTerminateApplicationNotification`.
- **Expected Outcome:**
  1. `AppTracker.untrackApp(pid)` executes.
  2. Associated `AXAppObserver` is completely invalidated and removed.
  3. All windows belonging to that PID are purged from `WindowStore`.
  4. Taskbar reflects removal immediately.
- **Automated Verification:** `TC-FUNC-007` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** PID removed from `observers`; zero residual windows in store for PID within 150ms.

---

### 2.2 Edge & Boundary Cases (`TC-EDGE-*`)

#### [TC-EDGE-001] Zero-Size (0x0) Minimized Chromium Frames
- **Category:** Edge Case / Frame Dimensions
- **Preconditions:** `WindowFilter` evaluation harness.
- **Stimulus / Action:**
  - Pass a candidate window with `frame = CGRect(x: 0, y: 0, width: 0, height: 0)` and `isMinimized = true`.
  - Pass a candidate window with `frame = CGRect(x: 0, y: 0, width: 0, height: 0)` and `isMinimized = false`.
- **Expected Outcome:**
  - Minimized 0x0 window returns `true` (accepted), preventing Chromium/Electron dropped windows.
  - Non-minimized 0x0 window returns `false` (rejected), preventing invisible tracking windows.
- **Automated Verification:** `TC-EDGE-001` in `EdgeCasesIntegrationTests.swift` and `WindowFilterTests.swift`.
- **Pass/Fail Criteria:** Minimized zero-size window preserved; non-minimized rejected.

---

#### [TC-EDGE-002] Modal Sheets & System Dialogs Filtering
- **Category:** Edge Case / AX Subroles
- **Preconditions:** Fixture app displays an open/save sheet or alert dialog.
- **Stimulus / Action:**
  - Evaluate `WindowFilter.shouldInclude` with subroles `kAXSheetSubrole`, `kAXDialogSubrole`, `kAXSystemDialogSubrole`.
  - Open a save sheet in `TextEdit` (`keystroke "s" using command down`).
- **Expected Outcome:**
  - `WindowFilter` returns `false` for modal sheets and dialogs.
  - Only the primary document window is shown on Taskbar; modal sheets do not spawn secondary buttons.
- **Automated Verification:** `TC-EDGE-002` in `EdgeCasesIntegrationTests.swift`.
- **Pass/Fail Criteria:** Sheet subroles never generate task buttons.

---

#### [TC-EDGE-003] Rapid Title Churn & Event Debounce Coalescing
- **Category:** Edge Case / Event Throttling
- **Preconditions:** 1 fixture window active.
- **Stimulus / Action:**
  - Fire 30 window title mutations in rapid succession within 200ms.
- **Expected Outcome:**
  - `AppTracker` debouncer coalesces notifications into a single reconciliation tick (`frameRenderDebounce = 0.05s`).
  - CPU usage remains flat (< 2% spike).
  - Final displayed title matches the 30th mutation.
- **Automated Verification:** `TC-EDGE-003` in `EdgeCasesIntegrationTests.swift`.
- **Pass/Fail Criteria:** Total UI refreshes $\le 3$; final title strictly accurate.

---

#### [TC-EDGE-004] Native Full-Screen Spaces Transitions
- **Category:** Edge Case / Spaces & Displays
- **Preconditions:** Window on primary display.
- **Stimulus / Action:**
  - Window enters native full-screen mode (`CGWindowLayer == 0` covering entire display bounds).
  - Simulate active space transition.
- **Expected Outcome:**
  - `ScreenManager.isScreenInFullScreen()` detects full-screen occupancy.
  - Taskbar panel hides to avoid obscuring full-screen workspace.
  - Exiting full-screen restores taskbar panel.
- **Automated Verification:** `TC-EDGE-004` in `EdgeCasesIntegrationTests.swift`.
- **Pass/Fail Criteria:** Taskbar panel alpha/order state correctly correlates with full-screen presence.

---

### 2.3 Stress & Capacity Benchmarks (`TC-STRESS-*`)

#### [TC-STRESS-001] High Window Density (50+ Windows) & Chevron Overflow
- **Category:** Stress / Layout & Capacity
- **Preconditions:** Clean environment with Taskbar running.
- **Stimulus / Action:**
  1. Programmatically spawn 50–60 lightweight windows.
  2. Compute total required button width versus screen usable width.
- **Expected Outcome:**
  1. Once button widths reach `minButtonWidth`, subsequent buttons are routed to overflow.
  2. `OverflowButton` (`»`) becomes visible on the right side of the taskbar.
  3. Clicking `OverflowButton` opens an `NSMenu` containing all overflowed windows.
  4. Selecting an item from the menu focuses the target window.
- **Automated Verification:** `scripts/test-functional.sh --stress`
- **Pass/Fail Criteria:** Chevron button visible; zero GUI layout freezes or unhandled crashes.

---

### 2.4 Performance & Resource Bounds (`TC-PERF-*`)

#### [TC-PERF-001] Resident Memory Bounds (RSS < 45 MB) & Leak Verification
- **Category:** Performance / Memory
- **Preconditions:** Taskbar running at baseline idle state.
- **Stimulus / Action:**
  1. Sample baseline RSS ($M_{\text{baseline}}$).
  2. Execute 50-window burst stress test (`TC-STRESS-001`).
  3. Sample peak RSS ($M_{\text{peak}}$).
  4. Terminate all test windows and wait 5 seconds for ARC cleanup.
  5. Sample final RSS ($M_{\text{final}}$).
- **Expected Outcome:**
  1. $M_{\text{peak}} < 45.0\text{ MB}$.
  2. Heap recovery: $M_{\text{final}} \le M_{\text{baseline}} + 3.0\text{ MB}$.
- **Automated Verification:** `scripts/test-functional.sh --stress` (RSS assertion)
- **Pass/Fail Criteria:** $M_{\text{peak}} < 45\text{ MB}$ and post-teardown delta $\le 3\text{ MB}$.

---

#### [TC-PERF-002] Idle CPU Bounds (< 0.1% CPU)
- **Category:** Performance / CPU
- **Preconditions:** Taskbar running with 5 idle desktop windows.
- **Stimulus / Action:**
  - Sample process CPU utilization over a 10-second idle window using `ps -o %cpu`.
- **Expected Outcome:**
  - Average CPU utilization is $< 0.1\%$.
  - Zero spin loops or runaway polling on background threads.
- **Automated Verification:** `scripts/test-functional.sh --stress` (CPU assertion)
- **Pass/Fail Criteria:** Averaged idle CPU strictly $< 0.1\%$.

---

## 3. Requirements Traceability Matrix

| Requirement ID | Requirement Description | Target Release | Verifying Test Cases |
|---|---|---|---|
| **REQ-FND-001** | Window Lifecycle Discovery & Button Creation | v0.1.1 | `TC-FUNC-001`, `TC-FUNC-006`, `TC-FUNC-007` |
| **REQ-FND-002** | Minimization & Deminiaturization State Sync | v0.1.1 | `TC-FUNC-002`, `TC-FUNC-003` |
| **REQ-FND-003** | Active Focus & Title Mutation Synchronization | v0.1.1 | `TC-FUNC-004`, `TC-FUNC-005`, `TC-EDGE-003` |
| **REQ-FND-004** | Robust Filtering (Chromium 0x0, Modal Sheets) | v0.1.1 | `TC-EDGE-001`, `TC-EDGE-002` |
| **REQ-FND-005** | Space & Full-Screen Transitions | v0.1.1 | `TC-EDGE-004` |
| **REQ-FND-006** | Dense Window Overflow & Chevron Menu | v0.1.1 | `TC-STRESS-001` |
| **REQ-FND-007** | Strict Memory (< 45 MB RSS) and CPU (< 0.1%) Bounds | v0.1.1 | `TC-PERF-001`, `TC-PERF-002` |
| **REQ-FND-008** | Pure Data-Driven Theme Registry & JSON Import/Export | v0.1.1 | `TC-UNIT-THEME-001`, `TC-UNIT-THEME-002` |
| **REQ-FND-009** | Window Clamping & Multi-Monitor Work Area Enforcer | v0.1.1 | `TC-UNIT-MATH-001` through `TC-UNIT-MATH-010` |
| **REQ-FND-010** | Observer Deregistration & Safe Signal Teardown | v0.1.1 | `TC-FUNC-007`, `TC-PERF-001` |
