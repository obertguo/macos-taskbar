# Taskbar Test Specifications & Traceability Catalog (v0.2.0)

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

#### [TC-FUNC-004] Single Window Focus Targeting & Display Isolation
- **Category:** Functional / Focus State & Multi-Display Isolation
- **Preconditions:** Application fixture running with two distinct document windows (e.g. on separate screens or behind other apps); an external application is currently frontmost.
- **Stimulus / Action:**
  1. Trigger window focus for the second document window via `WindowActions.performAction(.focus, for: win2.key)`.
  2. Verify target application process is activated.
- **Expected Outcome:**
  1. Target window performs `kAXRaiseAction` and is assigned `kAXMainAttribute`.
  2. Target application process is activated without `.activateAllWindows`.
  3. The target window is raised and focused, while other windows of the same application (e.g. on another monitor) remain in their background z-order without stealing focus or covering active windows on that display.
- **Automated Verification:** `TC-FUNC-004` in `WindowLifecycleIntegrationTests.swift`
- **Pass/Fail Criteria:** Targeted window is focused and raised while background windows of the same application remain undisturbed.

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
    2. Verify `onThemeIdChanged` receives the custom theme ID and legacy `onThemeChanged` does not fire with fallback `.modernHybrid`.
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

## 3. Requirements Traceability Matrix

| Feature Requirement | Specification IDs | Verification Test Target |
|---|---|---|
| **Window Discovery & Tracking** | `TC-FUNC-001`, `TC-FUNC-005` | `WindowLifecycleIntegrationTests` |
| **Window State Management** | `TC-FUNC-002`, `TC-FUNC-003` | `WindowLifecycleIntegrationTests` |
| **Window Focus & Multi-Display** | `TC-FUNC-004` | `WindowLifecycleIntegrationTests` |
| **Window Teardown & Quitting** | `TC-FUNC-006`, `TC-FUNC-007` | `WindowLifecycleIntegrationTests` |
| **Edge-Case Filtering** | `TC-EDGE-001`, `TC-EDGE-002` | `EdgeCasesIntegrationTests` |
| **Event Debounce, Multi-Monitor & Settle** | `TC-EDGE-003`, `TC-EDGE-004`, `TC-EDGE-005` | `EdgeCasesIntegrationTests` |
| **View Recycling & Overflow** | `TC-STRESS-001`, `TC-STRESS-002`, `TC-PERF-001` | `StressIntegrationTests` |
| **Pinned Quick Launch Bar** | `TC-PIN-001`, `TC-PIN-002`, `TC-PIN-003` | `PinnedAppsIntegrationTests` |
| **Context Menus & Multi-Screen Sync** | `TC-PIN-004`, `TC-PIN-005` | `PinnedAppsIntegrationTests` |
| **Multi-Resolution Icon Sanitizer** | `TC-PIN-006` | `PinnedAppsIntegrationTests` |
| **Expanded Presets (Luna & Dark)** | `TC-THEME-001`, `TC-THEME-002` | `ThemeExpansionIntegrationTests` |
| **Custom JSON Theme Loader** | `TC-THEME-003`, `TC-THEME-004`, `TC-THEME-005`, `TC-THEME-006` | `ThemeExpansionIntegrationTests`, `StatusMenuThemeTests` |
| **Memory Bound (< 45 MB RSS)** | `TC-PERF-001` | `scripts/test-functional.sh --all` |
