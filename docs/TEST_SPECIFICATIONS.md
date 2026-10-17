# Taskbar Test Specifications & Traceability Catalog

This document provides the canonical specification catalog and requirements traceability matrix for the **Taskbar** testing suite. All automated regression, functional, edge-case, and performance tests adhere to these specifications.

---

## 1. Test Taxonomy & Classification

| Taxonomy Prefix | Category | Description | Primary Runner / Harness |
|---|---|---|---|
| `TC-FUNC-xxx` | Functional | End-to-end window lifecycle (launch, minimize, restore, focus, title update, close, quit). | `Tests/TaskbarIntegrationTests` + `scripts/test-functional.sh --quick` |
| `TC-EDGE-xxx` | Edge Cases | Boundary conditions (0x0 frames, modal sheets, rapid title churn, dual-monitor boundaries). | `Tests/TaskbarIntegrationTests` + `scripts/test-functional.sh --edge-cases` |
| `TC-STRESS-xxx`| Stress & Load | High window density (50–100 windows), button overflow, chevron dropdown verification. | `scripts/test-functional.sh --stress` |
| `TC-PERF-xxx` | Performance | Memory bounds (peak RSS < 45 MB), button view recycling, idle CPU consumption (< 0.1%). | `scripts/test-functional.sh --stress` (Instrumentation) |
| `TC-PIN-xxx` | Quick Launch | Pinned applications model, layout positioning, running indicators, context menus, icon sanitization. | `Tests/TaskbarIntegrationTests/PinnedAppsIntegrationTests.swift` |
| `TC-DRAG-xxx` | Reordering | Drag-and-drop slot reordering, threshold detection, insertion bar, multi-display order isolation. | `Tests/TaskbarIntegrationTests/WindowReorderingIntegrationTests.swift` |
| `TC-GROUP-xxx`| Grouping | Application window grouping, count badge, lightweight popup, keyboard navigation, close triggers. | `Tests/TaskbarIntegrationTests/WindowGroupingIntegrationTests.swift` |
| `TC-THEME-xxx` | Theming | Preset definitions, contrast checks, file loader discovery, corrupt JSON safety, dynamic menu updates. | `Tests/TaskbarIntegrationTests/ThemeExpansionIntegrationTests.swift` |
| `TC-UNIT-xxx` | Unit | Pure math, clamping algorithms, model codecs, settings persistence, theme registry. | `Tests/TaskbarCoreTests` (`swift test`) |

---

## 2. Test Specifications Catalog

### 2.1 Functional Window Lifecycle (`TC-FUNC-*`)

#### [TC-FUNC-001] Window Creation & Taskbar Button Detection
- **Category:** Functional / Lifecycle
- **Preconditions:** Taskbar running; Accessibility permissions granted; zero preexisting fixture windows.
- **Stimulus / Action:**
  1. Launch real GUI application fixture (`TextEdit`) via `NSWorkspace` or AppleScript with 1 document window.
  2. Await window appearance notification (`kAXWindowCreatedNotification`).
- **Expected Outcome:**
  1. `AppTracker` discovers the process and subscribes an `AXAppObserver`.
  2. `WindowStore` adds the new window model.
  3. Taskbar view reflects the window within $\le 100\text{ms}$.
  4. Task button displays matching title and application icon.
- **Automated Verification:** `TC-FUNC-001` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Window button present in `WindowStore.orderedWindows` and taskbar within 100ms.

#### [TC-FUNC-002] Window Minimization State Tracking
- **Category:** Functional / Window State
- **Preconditions:** Fixture app running with 1 visible window tracked on Taskbar.
- **Stimulus / Action:**
  1. Programmatically minimize window via AppleScript (`set miniaturized of window 1 to true`).
  2. Await debounce threshold (50ms).
- **Expected Outcome:**
  1. Window element reports `isMinimized == true`.
  2. `WindowFilter.shouldInclude` allows `AXDialog` subroles when minimized.
  3. `WindowStore` marks `WindowInfo.isMinimized = true`.
- **Automated Verification:** `TC-FUNC-002` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** `isMinimized` attribute true in `WindowStore` within 100ms.

#### [TC-FUNC-003] Window Restoration / Deminiaturization State Tracking
- **Category:** Functional / Window State
- **Preconditions:** Fixture app window is currently minimized.
- **Stimulus / Action:**
  1. Trigger window restore via AppleScript (`set miniaturized of window 1 to false`).
  2. Await debounce threshold (50ms).
- **Expected Outcome:**
  1. Window element reports `isMinimized == false`.
  2. `WindowStore` marks `WindowInfo.isMinimized = false`.
- **Automated Verification:** `TC-FUNC-003` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Window button reflects un-minimized state within 100ms.

#### [TC-FUNC-004] Single Window Focus Targeting & Z-Order Isolation
- **Category:** Functional / Focus State & Z-Order Isolation
- **Preconditions:** Application fixture running with two distinct document windows (Doc 1 and Doc 2); an intervening third-party application window (Finder) is opened in front of both documents (`[Finder, Doc 2, Doc 1]`).
- **Stimulus / Action:**
  1. Trigger window focus specifically for Doc 1 via `WindowActions.performAction(.focus, for: win1.key)`.
  2. Query `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` to determine live WindowServer on-screen z-order.
- **Expected Outcome:**
  1. Doc 1 executes `kAXRaiseAction`, receives `kAXMainAttribute`, and is activated via `SetFrontProcessWithOptions(&psn, 1)` and `_SLPSSetFrontProcessWithOptions(&psn, wid, 0x200)`.
  2. Target application becomes `frontmostApplication`.
  3. Doc 1 is frontmost in z-order ($z_0$), the intervening Finder window remains in the middle ($z_1$), and Doc 2 remains in the background ($z_2$), proving that focusing Doc 1 did not pull sibling windows of the same application forward.
- **Automated Verification:** `TC-FUNC-004` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Targeted Doc 1 is frontmost, and the intervening Finder window index is strictly less than sibling Doc 2 index in `CGWindowListCopyWindowInfo`.

#### [TC-FUNC-005] Dynamic Window Title Mutation
- **Category:** Functional / Dynamic Properties
- **Preconditions:** Fixture window open and tracked.
- **Stimulus / Action:**
  1. Mutate window document file or document title via AppleScript.
  2. Await debounce threshold (50ms).
- **Expected Outcome:**
  1. `kAXTitleChangedNotification` fires.
  2. `WindowStore` updates title string for target window.
  3. `TaskButton` updates displayed string.
- **Automated Verification:** `TC-FUNC-005` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Updated title string reflected in store within 100ms.

#### [TC-FUNC-006] Window Close & Store Teardown
- **Category:** Functional / Teardown
- **Preconditions:** Fixture window open and tracked.
- **Stimulus / Action:**
  1. Close document window via AppleScript (`close window 1 saving no`).
- **Expected Outcome:**
  1. `kAXUIElementDestroyedNotification` fires.
  2. `WindowStore` purges target window from ordered list.
  3. `TaskbarView` removes button from subview hierarchy.
- **Automated Verification:** `TC-FUNC-006` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Window purged completely within 100ms.

#### [TC-FUNC-007] Application Termination & Observer Cleanup
- **Category:** Functional / Teardown
- **Preconditions:** Fixture running with open windows.
- **Stimulus / Action:**
  1. Terminate fixture application process (`fixture.terminate()`).
- **Expected Outcome:**
  1. `NSWorkspace.didTerminateApplicationNotification` fires.
  2. `AppTracker` unbinds `AXAppObserver`, unregistering all AX notifications.
  3. All windows for terminated PID purged from `WindowStore`.
- **Automated Verification:** `TC-FUNC-007` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Zero remaining windows for process in `WindowStore` within 100ms.

---

### 2.2 Edge Cases (`TC-EDGE-*`)

- **[TC-EDGE-001] Zero-Size Frame Filtering:** Minimized Chromium/Electron windows reporting `0x0` dimensions are preserved in `WindowStore` if `isMinimized == true`.
- **[TC-EDGE-002] Modal Sheet & System Dialog Rejection:** Elements with subrole `AXSheet` or non-minimized `AXDialog` are excluded from `WindowFilter.shouldInclude`.
- **[TC-EDGE-003] Rapid Title Churn Coalescing:** Burst of 25 title mutations within 10ms is coalesced by `Debouncer` into a single UI update.
- **[TC-EDGE-004] Dual-Monitor Coordinate Partitioning:** Windows are strictly assigned to displays based on center-point intersection against screen bounds.
- **[TC-EDGE-005] Full-Screen Window Resize Debounce & Animation Settle:**
  - **Category:** Edge Cases / Window Clamping & Debounce
  - **Preconditions:** Window fixture open and tracked; taskbar running with height reserved.
  - **Stimulus / Action:**
    1. Expand window bounds to fill entire screen vertically (overlapping taskbar).
    2. Simulate rapid resize notification followed by move/reconcile events.
    3. Allow Pass 1 (150ms), Pass 2 (400ms), and Pass 3 (650ms) settle passes to execute.
  - **Expected Outcome:**
    1. Self-inflicted resize notifications from Taskbar's own `setSize` are filtered to prevent debounce invalidation and feedback loops.
    2. Active mouse drags defer clamping until mouse-up.
    3. Window settles cleanly clamped at or above the taskbar top edge without requiring application defocus or app switching.
  - **Automated Verification:** `TC-EDGE-005` in `EdgeCasesIntegrationTests.swift`
  - **Pass/Fail Criteria:** `clampedFrame.maxY <= screenBounds.maxY - barHeight + overlapThreshold`.

- **[TC-EDGE-006] Immediate Initial Maximize Clamping Under Custom Bar Height Without Defocus:**
  - **Category:** Edge Cases / Window Clamping & In-Flight Debounce Protection
  - **Preconditions:** Window fixture open and tracked; taskbar configured with custom bar height (e.g. 40pt).
  - **Stimulus / Action:**
    1. Maximize window bounds to cover full screen height.
    2. Dispatch initial maximize notification sequence: resize notification followed immediately by rapid move/reconcile events.
    3. Evaluate settled window frame without defocusing the application or switching apps.
  - **Expected Outcome:**
    1. In-flight resize debounce bursts are not cancelled or deferred by passive move/reconcile events.
    2. Window bottom clamps immediately above custom taskbar top edge (`screenBounds.maxY - customBarHeight`).
  - **Automated Verification:** `TC-EDGE-006` in `EdgeCasesIntegrationTests.swift`
  - **Pass/Fail Criteria:** `finalFrame.maxY <= screenBounds.maxY - customBarHeight + overlapThreshold`.

---

### 2.3 Stress & Performance (`TC-STRESS-*` & `TC-PERF-*`)

- **[TC-STRESS-001] High-Density Window Store Burst:** Ingesting 100 distinct windows in $< 100\text{ms}$ completes with $< 50\text{ms}$ processing latency.
- **[TC-STRESS-002] TaskbarView Overflow Activation:** Shrinking available width below `minButtonWidth * N` triggers `OverflowButton` (`»`) display.
- **[TC-PERF-001] In-Place View Recycling:** Successive `updateWindows` calls preserve identical `TaskButton` instances without reallocation.

---

### 2.4 Pinned Applications & Quick Launch (`TC-PIN-*`)

- **[TC-PIN-001] PinnedButton Rendering & Aspect Ratio:** Pinned buttons render as compact squares ($w = h = \text{height} - 2 \times \text{padding}$) adjacent to the Start button.
- **[TC-PIN-002] Running Indicator Transitions:** Bottom running indicator dot toggles dynamically between visible/hidden as application windows appear or disappear.
- **[TC-PIN-003] Pinned Button View Recycling:** Pinned button subviews are recycled in place across layout updates without recreation.
- **[TC-PIN-004] Context Menu Pin/Unpin Toggle:** Right-clicking running `TaskButton` toggles "Pin to Taskbar" / "Unpin from Taskbar"; right-clicking `PinnedButton` displays "Unpin from Taskbar".
- **[TC-PIN-005] Multi-Display Synchronization:** Adding or removing a pinned application instantly updates `TaskbarView` across all connected displays via `ScreenManager`.
- **[TC-PIN-006] Multi-Resolution Icon Sanitization:** Legacy 1x bitmaps ($< 64\text{px}$) inside app bundles are filtered out when high-resolution representations exist, preventing noise on 1x displays.
- **[TC-PIN-007] BaseTaskbarButton Tracking & Click Dispatch:** Centralized tracking area creation, hover and pressed state mutations, and configurable mouse-up vs mouse-down click dispatch policies across button components.

---

### 2.5 Theme Architecture & Custom Loader (`TC-THEME-*`)

- **[TC-THEME-001] Built-in Presets Completeness:** `modern-hybrid`, `retro-classic`, `windows-xp-luna`, and `dark-minimal` deserialize cleanly and pass contrast minimums.
- **[TC-THEME-002] Multi-Display Theme Propagation:** Calling `ScreenManager.updateTheme(themeId:)` immediately updates palettes across all active display panels.
- **[TC-THEME-003] Custom JSON Discovery & Resilience:** `ThemeFileLoader` discovers valid JSON themes from `~/.config/taskbar/themes/` while gracefully ignoring corrupted files, non-JSON files, and built-in ID collisions.
- **[TC-THEME-004] Dynamic Status Menu Synchronization:** Discovered custom themes populate the Status Menu Theme submenu with active state checkmarks and reload triggers.
- **[TC-THEME-005] Custom Theme Activation & Metric Adoption:**
  - **Category:** Theming / Status Menu & Metrics
  - **Preconditions:** Custom JSON theme registered in `ThemeRegistry`.
  - **Stimulus / Action:**
    1. Select custom theme from Status Menu.
    2. Verify `onThemeIdChanged` receives the custom theme ID without enum clobbering.
    3. Verify `ScreenManager` applies theme and adopts custom layout dimensions (`barHeight`, `minButtonWidth`, `maxButtonWidth`, `buttonSpacing`, `fontSize`, `iconSize`).
  - **Automated Verification:** `testCustomThemeSelectionDoesNotRevertToModernHybrid` in `StatusMenuThemeTests.swift` & `testScreenManagerDynamicCustomThemeSwitching` in `ThemeExpansionIntegrationTests.swift`.
  - **Pass/Fail Criteria:** Custom theme ID retained, status menu checkmark remains active, and layout metrics reflect theme configuration.
- **[TC-THEME-006] Dynamic Material & Blending Mode Adoption:**
  - **Category:** Theming / Translucency & Vibrancy
  - **Preconditions:** Theme JSON specifies `materials` with `material` and `blendingMode` tokens.
  - **Stimulus / Action:**
    1. Parse and validate `ThemeMaterials` decodes custom material and blending mode strings.
    2. Map tokens through `VisualEffectMapping` with normalization and safe fallbacks.
    3. Apply custom theme to `ScreenManager` and verify all panels adopt the target `NSVisualEffectView.Material` and `NSVisualEffectView.BlendingMode`.
    4. Switch back to Modern Hybrid and verify properties revert to `.underWindowBackground` and `.behindWindow`.
  - **Automated Verification:** `testVisualEffectMappingResolvesSupportedMaterialsAndBlendingModes` & `testScreenManagerAndTaskbarViewDynamicMaterialAndBlendingModeAdoption` in `ThemeExpansionIntegrationTests.swift`.
  - **Pass/Fail Criteria:** Underlying `visualEffectView` properties on all display panels immediately match theme material and blending mode.

---

### 2.6 Pure Layout Engine, Grouping & Ordering (`TC-UNIT-*`)

- **[TC-UNIT-001] Empty & Pinned-Only Taskbar Geometry:** Empty states and pinned-only states calculate correct start button and pinned item bounds without NaN or negative widths.
- **[TC-UNIT-002] Dynamic Task Button Compression:** As available width contracts, button widths compress evenly within `[minButtonWidth, maxButtonWidth]` and hide title labels below visibility threshold.
- **[TC-UNIT-003] Overflow Button Reservation & Slot Allocation:** When available space is insufficient for all task buttons at `minButtonWidth`, overflow space is reserved and visible vs hidden counts are accurately computed.
- **[TC-UNIT-004] Extensible Slot Geometry for Window Grouping:** Pre-calculates geometric slots suitable for grouping multiple window items into unified bounds.
- **[TC-UNIT-005] Never Grouping Mode Leaves All Separate:** Validates 10 windows across 3 distinct app bundles form 10 individual `WindowGroup` objects.
- **[TC-UNIT-006] Always Grouping Mode Aggregates by Bundle ID:** Validates 10 windows across 3 distinct app bundles aggregate into exactly 3 `WindowGroup` objects.
- **[TC-UNIT-007] When Crowded Auto-Groups on Overflow:** Verifies that under ample width windows remain ungrouped, and under constrained width multi-window apps automatically aggregate until layout bounds fit.
- **[TC-UNIT-008] Group Derived States:** Verifies `isFocused`, `isMinimized`, `isAppHidden`, and `displayTitle` derivations for single vs multi-window groups.
- **[TC-UNIT-009] Reorder Item Shifts Indices:** Validates array slot moving and slot reindexing operations.
- **[TC-UNIT-010] Custom Order Persists Across New Windows:** Validates that newly opened applications append after manually ordered items without disturbing established order.
- **[TC-UNIT-011] Custom Order Purges Closed Windows:** Validates that closed windows are cleanly pruned from custom order dictionaries without dangling slots.
- **[TC-UNIT-012] Drag Slot Calculation & Boundary Clamping:** Validates `slotIndex(forHorizontalPosition:in:)` math and boundary clamping across task and pinned layout slots.
- **[TC-UNIT-013] Multi-Edge Screen Clamping Geometry:** Validates coordinate clamping across all 4 display edges (`.top`, `.bottom`, `.left`, `.right`), subpixel threshold filtering (2.0pt), and non-maximized window pass-through behavior.
- **[TC-UNIT-015] TaskbarEdge Domain Serialization & Settings:** Validates JSON encoding and decoding of `TaskbarEdge` and verifies fallback to `.bottom` when reading v0.1.0 – v0.3.1 configuration files lacking `taskbarEdge`.

---

### 2.7 Interactive Drag-and-Drop Slot Reordering (`TC-DRAG-*`)

- **[TC-DRAG-001] Dragging Task Button Beyond Threshold Reorders Slots:** Dragging a button beyond `dragThresholdPoints` activates insertion indicator; releasing commits slot change, updates button frames, and persists to `WindowStore.customOrders`.
- **[TC-DRAG-002] Vertical Mouse Escape & Escape Key Cancelation:** Moving mouse vertically beyond `verticalEscapeThreshold` or pressing `Escape` cleanly cancels drag session, hiding indicator and restoring original button frames.
- **[TC-DRAG-003] Multi-Display Drag Isolation:** Reordering buttons on Display 1 maintains independent order without disturbing Display 2 button layout or order maps.
- **[TC-DRAG-004] Dragging Pinned Button Reorders Settings & Broadcasts in Lockstep:** Dragging a pinned button reorders `Settings.pinnedApps`, immediately persists to disk, and broadcasts the updated pinned list across all connected screens via `ScreenManager`.

---

### 2.8 Application Window Grouping & Popup Menu (`TC-GROUP-*`)

- **[TC-GROUP-001] Multi-Window Aggregation & Badge Counter:** Multi-window application renders as a unified button with badge count pill (Modern) or stacked bevel ridges (Retro).
- **[TC-GROUP-002] Group Button Click Presents Window List Popup:** Clicking a multi-window group presents `GroupWindowPopup` anchored above the button displaying all constituent window titles and icons.
- **[TC-GROUP-003] Selecting Window in Popup Focuses Target Window:** Selecting a window row in the popup (via click or `Return` key) raises and focuses that specific window without raising other application windows, and dismisses the popup.
- **[TC-GROUP-004] Dynamic Grouping Mode Switching via ScreenManager:** Switching `WindowGroupingMode` via `ScreenManager` or Status Menu immediately reconfigures taskbar layout across all connected displays without restarting.
- **[TC-GROUP-005] Popup Mouse Interaction, Close Button Trigger & Dynamic Resize:**
  - **Category:** Window Grouping / Interactive Popup & Teardown
  - **Preconditions:** Multi-window application group open in `GroupWindowPopup`.
  - **Stimulus / Action:**
    1. Click the close button (`✕`) on a specific window row.
    2. Verify `onCloseWindow` fires for the target window key and remaining window count decrements.
    3. Verify popup panel smoothly shrinks its vertical height to fit remaining items.
    4. Close the final remaining window.
  - **Expected Outcome:**
    1. Target window closed, remaining windows retained in order.
    2. Popup dynamically resizes.
    3. Closing the last window automatically dismisses the popup panel.
  - **Automated Verification:** `TC-GROUP-005` in `WindowGroupingIntegrationTests.swift`
  - **Pass/Fail Criteria:** `closedKeys.contains(win.key)` and popup dismissed upon zero remaining windows.
- **[TC-GROUP-006] Popup Dismissal on Loss of Key Focus or Outside Interaction:**
  - **Category:** Window Grouping / Focus & Dismissal
  - **Preconditions:** `GroupWindowPopup` open and key.
  - **Stimulus / Action:**
    1. Simulate user interaction with foreground window or clicking outside popup causing loss of key status (`resignKey()`).
  - **Expected Outcome:**
    1. Popup receives `windowDidResignKey` notification.
    2. `TaskbarView.activeGroupPopup` is immediately set to `nil` and popup orders out.
  - **Automated Verification:** `TC-GROUP-006` in `WindowGroupingIntegrationTests.swift`
  - **Pass/Fail Criteria:** `view.activeGroupPopup == nil` immediately upon resigning key.

---

## 3. Requirements Traceability Matrix

| Feature Requirement | Specification IDs | Verification Test Target |
|---|---|---|
| **Window Discovery & Tracking** | `TC-FUNC-001`, `TC-FUNC-005` | `WindowLifecycleIntegrationTests` |
| **Window State Management** | `TC-FUNC-002`, `TC-FUNC-003` | `WindowLifecycleIntegrationTests` |
| **Window Focus & Multi-Display** | `TC-FUNC-004` | `WindowLifecycleIntegrationTests` |
| **Window Teardown & Quitting** | `TC-FUNC-006`, `TC-FUNC-007` | `WindowLifecycleIntegrationTests` |
| **Edge-Case Filtering** | `TC-EDGE-001`, `TC-EDGE-002` | `EdgeCasesIntegrationTests` |
| **Event Debounce, Multi-Monitor & Settle** | `TC-EDGE-003`, `TC-EDGE-004`, `TC-EDGE-005`, `TC-EDGE-006` | `EdgeCasesIntegrationTests` |
| **View Recycling & Overflow** | `TC-STRESS-001`, `TC-STRESS-002`, `TC-PERF-001` | `StressIntegrationTests` |
| **Pinned Quick Launch Bar** | `TC-PIN-001`, `TC-PIN-002`, `TC-PIN-003`, `TC-PIN-007` | `PinnedAppsIntegrationTests` |
| **Context Menus & Multi-Screen Sync** | `TC-PIN-004`, `TC-PIN-005` | `PinnedAppsIntegrationTests` |
| **Multi-Resolution Icon Sanitizer** | `TC-PIN-006` | `PinnedAppsIntegrationTests` |
| **Expanded Presets (Luna & Dark)** | `TC-THEME-001`, `TC-THEME-002` | `ThemeExpansionIntegrationTests` |
| **Custom JSON Theme Loader** | `TC-THEME-003`, `TC-THEME-004`, `TC-THEME-005`, `TC-THEME-006` | `ThemeExpansionIntegrationTests`, `StatusMenuThemeTests` |
| **Pure Layout Engine & Slot Allocation** | `TC-UNIT-001`, `TC-UNIT-002`, `TC-UNIT-003`, `TC-UNIT-004`, `TC-UNIT-012` | `TaskbarLayoutEngineTests`, `TaskbarLayoutEngineDragTests` |
| **Window Grouping Logic & Models** | `TC-UNIT-005`, `TC-UNIT-006`, `TC-UNIT-007`, `TC-UNIT-008` | `WindowGroupingLogicTests` |
| **Window Ordering Logic & Persistence** | `TC-UNIT-009`, `TC-UNIT-010`, `TC-UNIT-011` | `WindowOrderingLogicTests` |
| **Interactive Drag-and-Drop Reordering** | `TC-DRAG-001`, `TC-DRAG-002`, `TC-DRAG-003`, `TC-DRAG-004` | `WindowReorderingIntegrationTests`, `PinnedAppsIntegrationTests` |
| **Application Window Grouping & Popup** | `TC-GROUP-001`, `TC-GROUP-002`, `TC-GROUP-003`, `TC-GROUP-004`, `TC-GROUP-005`, `TC-GROUP-006` | `WindowGroupingIntegrationTests`, `StatusMenuGroupingTests` |
| **Multi-Edge Screen Clamping** | `TC-UNIT-013` | `WorkAreaMathTests` |
| **TaskbarEdge Domain Serialization** | `TC-UNIT-015` | `SettingsTests` |
| **Memory Bound (< 45 MB RSS)** | `TC-PERF-001` | `scripts/test-functional.sh --all` |
