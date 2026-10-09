# Changelog

All notable changes to **Taskbar** will be documented in this file.

## [0.3.1] - 2026-10-09

### Window Grouping Responsiveness & Single-Window Focus Isolation

Version `0.3.1` is a targeted patch release that resolves single-window focus isolation across multi-window applications, eliminates double-click requirements in the window grouping list popup, and ensures immediate auto-dismissal on outside clicks.

#### Fixed
- **Single-Window Focus Isolation (`WindowActions` & `AXElement+Attributes`):**
  - Resolved an issue where clicking a task button or group row to focus a specific window caused macOS to elevate all windows belonging to that application across the desktop, burying intervening windows from other applications.
  - Resolved native window identity lookup: dynamically linked `_AXUIElementGetWindow` so `AXUIElement.windowID` returns the true `CGWindowID` matching WindowServer rather than a fallback pointer hash.
  - Replaced full application activation (`NSRunningApplication.activate`) with targeted WindowServer activation: invokes `SetFrontProcessWithOptions(&psn, 1 /* kSetFrontProcessFrontWindowOnly */)` and `_SLPSSetFrontProcessWithOptions(&psn, wid, 0x200 /* kCPSUserGenerated */)` in conjunction with Accessibility `kAXRaiseAction` and `kAXMainAttribute`.
  - Background sibling windows belonging to the same application now reliably remain behind intervening windows of other applications in their existing on-screen z-order.
- **Window Grouping List Popup Interaction (`GroupWindowPopup`):**
  - Resolved an issue where the window group popup appeared blank by separating the background `NSVisualEffectView` from the foreground `rowsContainerView`, eliminating subview hierarchy conflicts.
  - Enabled instantaneous single-click window switching and window closing by implementing `acceptsFirstMouse(for:) -> true` across row views and close buttons.
  - Implemented automatic popup dismissal upon losing key focus (`windowDidResignKey`) or when clicking anywhere outside the popup frame via global and local `NSEvent` monitors.
- **Test Harness Concurrency & Reliability (`TestFixtureApp`):**
  - Added an asynchronous `TestFixtureQueue` actor to serialize GUI fixture creation and teardown across test suites, eliminating AppleScript `Connection is invalid (-609)` test collisions.
- **Test Suite Verification (`TC-FUNC-004`):**
  - Upgraded `TC-FUNC-004` (`WindowLifecycleIntegrationTests`) to introduce an intervening Finder window and verify true on-screen z-order isolation using `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])`.

---

## [0.3.0] - 2026-10-07

### Application Window Grouping & Drag-and-Drop Slot Reordering

Version `0.3.0` introduces Phase 3 advanced window organization capabilities: configurable application window grouping and interactive drag-and-drop slot reordering with multi-display isolation.

#### Added
- **Application Window Grouping (`TaskbarCore` & `TaskbarKit`):**
  - Pure grouping engine (`WindowGroupingLogic`) supporting three modes: `Always (Group multi-window apps)`, `When Crowded (Auto-group on overflow)`, and `Never (One button per window)`.
  - Dynamic badge count indicator rendered on grouped buttons (`AppName (Count)`).
  - Lightweight native `GroupWindowPopup` (`NSPanel`) displaying open document titles, focus indicators, and individual close buttons (`✕`).
  - Full keyboard navigation: `Up`/`Down` arrow keys to highlight rows, `Return` to focus and raise, and `Escape` to dismiss.
  - Group button context menu with "Close All Windows" alongside app management actions.
  - Status Menu submenu for live switching between window grouping modes with checkmark states.
- **Interactive Drag-and-Drop Slot Reordering:**
  - Real-time horizontal drag-and-drop reordering with high-contrast insertion indicator bar (Option B).
  - Display-isolated ordering for running tasks: custom orders are scoped per screen, persisting seamlessly as windows move across displays.
  - Quick Launch pinned button reordering: dragging pinned shortcuts reorders items, syncs across all connected monitors in lockstep, and immediately persists to `settings.json`.
  - Smooth drag cancellation on vertical escape threshold (24pt) or Escape key press.
- **Automated Test Expansion:**
  - Added `TC-GROUP-001` through `TC-GROUP-006` covering grouping aggregation, popup presentation, row selection, dynamic mode switching, and outside dismissal.
  - Added `TC-DRAG-001` through `TC-DRAG-004` covering drag threshold detection, cancelation, multi-display order isolation, and pinned app synchronization.
  - Expanded test harness flags `--reordering` and `--grouping` in `scripts/test-functional.sh`.

---

### Initial Maximize Clamping & TCC Authorization Hardening

Version `0.2.3` is a targeted patch release that resolves initial window maximize clamping failures and hardens Accessibility tracking against macOS TCC authorization races and rapid event clobbering.

#### Fixed
- **In-Flight Resize Debounce Protection (`WorkAreaEnforcer`):**
  - Resolved an issue where maximizing an application window immediately after app launch or rebuild failed to clamp above the taskbar boundary, requiring an application defocus or window switch to re-trigger nudging.
  - Added protection in `handleWindowMovedOrResized` to ignore passive move (`AXWindowMoved`) or periodic 16ms window reconciliation events (`reconcileWindows()`) while a resize debounce burst is in-flight. This prevents `generationCounters[winID]` from incrementing prematurely and cancelling in-flight Pass 1 (150ms) and Pass 2 (400ms) animation settle clamping passes.
  - Cleaned up active debounce tracking flags upon Pass 3 settle completion.
  - Promoted work area nudger log events to `.info` level for transparent production diagnostics.
- **TCC / Accessibility Authorization Polling & Dynamic Observer Attachment (`AppTracker`):**
  - Resolved an issue on rebuilt ad-hoc binaries (`codesign --sign -`) where asynchronous TCC code directory hash (`cdhash`) verification on launch millisecond 0 caused `startTrackingAllRunningApps()` to bail out without retry when authorization was not immediately ready.
  - Added a background authorization polling task in `AppTracker` that checks authorization every 500ms for up to 30 seconds upon launch, automatically tracking all running applications as soon as authorization is confirmed.
  - Added dynamic observer attachment in `handleAppActivated` to immediately attach missing observers whenever an application is activated or brought to focus.
  - Added `trackingAttemptedPIDs` cache to prevent redundant AXThread attachment attempts on non-accessible background processes.
- **Resilient Window Observer Registration (`AXAppObserver`):**
  - Updated `observeWindow` to only insert `winID` into `observedWindows` if at least one core AX notification successfully registers, enabling transparent retry on subsequent events rather than permanently abandoning registration.
- **Startup Configuration Precedence (`AppDelegate`):**
  - Re-ordered startup initialization to configure `WorkAreaEnforcer.shared.configure` with persisted custom bar height before `ScreenManager` creates and initializes display panels.
- **Test Harness Hardening & Fixture Process Drain (`TestFixtureApp`):**
  - Added `waitForWindowElement(index:timeoutSeconds:)` in `TestFixtureApp` to dynamically poll up to 3.0 seconds for window elements in the AX hierarchy, eliminating test timing flakiness across CPU bursts and screensaver wake.
  - Added process teardown draining in `TestFixtureApp.terminateApp` to ensure previous fixture instances are fully unhooked before launching a new fixture.

#### Added
- **Integration Test `TC-EDGE-006` (`EdgeCasesIntegrationTests`):**
  - Added `testInitialMaximizeNudgingWithCustomBarHeight` asserting immediate initial maximize clamping with custom 40pt bar height without defocusing or app switching.
  - Enforced `.serialized` suite execution on `EdgeCasesIntegrationTests` to prevent concurrent fixture collisions.
  - Total test count expanded to 104 tests (71 unit + 33 integration) across 18 test suites passing at 100%.
- **Technical Postmortem & Analysis Document:**
  - Added `plans/v0.2.X/initial_maximize_nudger_and_tcc_race_analysis.md` documenting comprehensive root-cause analysis, reproduction mechanisms, and architectural solutions.

---

## [0.2.2] - 2026-10-04

### Custom Theme Activation & Layout Metric Adoption

Version `0.2.2` is a targeted patch release that resolves custom theme activation from the menu bar status menu and enables dynamic adoption of custom layout dimensions from user theme JSON files.

#### Fixed
- **Custom JSON Theme Activation & Menu Selection (`StatusMenu` & `AppDelegate`):**
  - Resolved an issue where clicking custom themes in the status menu immediately reverted to Modern Hybrid due to a legacy `onThemeChanged` callback clobbering the active theme ID with the fallback `.modernHybrid` enum value.
  - Guarded `onThemeChanged` in `StatusMenu` to only trigger for built-in preset IDs, and consolidated all theme lifecycle handling in `AppDelegate` exclusively under `onThemeIdChanged`.
- **Custom Theme Typography & Icon Metric Preservation (`ScreenManager`):**
  - Fixed an issue where selecting a custom theme stripped its custom `fontSize` and `iconSize` and forcefully overwritten them with standard defaults via unconditional `.withCustomMetrics()`.
  - When switching to a custom theme, `ScreenManager` now directly adopts the theme's configured font size and icon size, keeping status menu controls in sync.
- **Extended Layout Metrics in Theme JSON (`ThemeMetrics`):**
  - Added optional decoding for `barHeight`, `minButtonWidth`, `maxButtonWidth`, and `buttonSpacing` in `ThemeMetrics`.
  - When custom themes provide custom taskbar heights or button layout parameters (e.g. 64pt bar height or custom button widths), `ScreenManager` and `WorkAreaEnforcer` now dynamically resize taskbar panels, recalculate work area clamping bounds, and update menu bar status items.

#### Added
- **Integration Tests:**
  - Added integration test `testCustomThemeSelectionDoesNotRevertToModernHybrid` in `StatusMenuThemeTests`.
  - Added integration test `testScreenManagerDynamicCustomThemeSwitching` in `ThemeExpansionIntegrationTests`.
  - Total test count expanded to 99 tests across 18 test suites passing at 100%.

---

## [0.2.1] - 2026-10-04

### Window Focus Isolation & Full-Screen Clamping Resilience

Version `0.2.1` is a targeted patch release that resolves multi-display window activation isolation and hardens full-screen window clamping within the Accessibility work area enforcer.

#### Fixed
- **Multi-Display Window Focus Isolation:**
  - Resolved an issue where clicking a taskbar button for an inactive window on a secondary monitor inadvertently raised and focused all background windows of the same application across all monitors.
  - Replaced bulk application activation (`.activateAllWindows`) with isolated window targeting using `kAXRaiseAction` and `kAXMainAttribute` directly on the target window, leaving background windows on other monitors undisturbed in their existing z-order.
- **Full-Screen Window Resize & Zoom Clamping (`WorkAreaEnforcer`):**
  - Resolved an issue where resizing or maximizing an application window to full-screen failed to clamp above the taskbar immediately, requiring the user to defocus or switch applications to re-trigger nudging.
  - **Self-Inflicted Notification Filtering:** Ignores programmatic resize notifications generated by Taskbar's own `setSize` within 350ms, preventing cancellation of downstream animation settle passes and recursion feedback loops.
  - **Active Mouse Drag Deferral:** Added mouse-down state detection (`CGEventSource.buttonState`) to defer clamping until mouse release, eliminating cursor jitter and preventing intermediate drag ticks from consuming recursion attempts.
  - **3-Pass Settle Verification:** Implemented multi-stage debounce settling (Pass 1 at 150ms, Pass 2 at 400ms, Pass 3 at 650ms) to reliably clamp both rapid window snaps and slower macOS zoom / window tiling animations.
  - **Dynamic Screen Fallback:** Added automatic fallback to `NSScreen.screens` if display descriptors are not yet populated during initial layout.
  - **App-Level Notification Registration:** Registered `kAXWindowResizedNotification` and `kAXWindowMovedNotification` at the application level to immediately track and clamp newly opened windows in Chromium and Electron applications.
- **Test Infrastructure & Specifications:**
  - Added integration test `TC-FUNC-004` validating single-window focus targeting without raising background windows.
  - Added integration test `TC-EDGE-005` validating full-screen window resize debounce and multi-pass animation settle clamping.
  - Updated test specifications and documentation in `docs/TEST_SPECIFICATIONS.md` and `docs/TESTING.md` (97 tests total passing at 100%).

---

## [0.2.0] - 2026-10-04

### Personalization & Quick Launch

Version `0.2.0` introduces comprehensive personalization options and a persistent Quick Launch bar across all connected displays. This includes modularized built-in themes, new Windows XP Luna and Dark Minimal presets, user custom JSON theming from disk, pinned application shortcuts with running state indicators, and multi-resolution icon sanitization.

#### Added
- **Pinned Applications & Quick Launch Bar:**
  - Compact square buttons rendered between the Start button and window task buttons across all monitors.
  - One-click launch for closed applications and instant raise/focus for running applications.
  - Dynamic running status indicator dot rendered at the bottom center of pinned buttons, adapting to the active theme.
  - In-place view recycling for `PinnedButton` subviews, eliminating mouse tracking flicker and heap churn.
  - Full multi-display synchronization via `ScreenManager` when apps are pinned, unpinned, or reordered.
- **Context Menu Pinning UX:**
  - Right-click dynamic `TaskButton` to toggle "Pin to Taskbar" / "Unpin from Taskbar" in real time.
  - Right-click `PinnedButton` to access "Open <App>", "Unpin from Taskbar", and "Quit <App>".
- **Modular Theming & Preset Expansion:**
  - Refactored monolithic theme definitions into dedicated, single-responsibility files under `Sources/TaskbarCore/Config/Theme/Presets/`.
  - **Windows XP Luna (`windows-xp-luna`):** Classic royal blue gradient taskbar, signature emerald green Start button with gold accents, sunken darker royal blue active buttons, and sky-blue hover highlights.
  - **Dark Minimal (`dark-minimal`):** Pitch black `#121212` background, subtle borders, flat minimal hover states, and cyan `#00BCD4` active accent indicator.
- **External User Custom Theme Engine (`ThemeFileLoader`):**
  - Auto-discovers and validates external `*.json` themes from `~/.config/taskbar/themes/`.
  - Dynamic Status Menu integration displaying discovered themes in real-time with checkmarks.
  - On-demand "Reload Themes from Disk" action with automatic fallback for pruned files.
  - "Export Current Theme as JSON..." tool supporting disk export and custom sharing.
  - Resilient JSON decoder rejecting empty/colliding preset IDs and gracefully ignoring corrupted files without crashing.
- **Multi-Resolution Icon Sanitization (`IconCache`):**
  - High-DPI icon preparation filtering out corrupt legacy 1x bitmaps (<64px) from third-party app bundles (e.g. Electron / Antigravity) when high-resolution representations exist.
  - Forces AppKit to downsample from pristine high-resolution bitmaps with smooth bilinear anti-aliasing on non-Retina displays.
  - Dimension-aware cache keys ensuring proper icon scaling when `settings.iconSize` is modified.
- **New Test Suites & Expanded Coverage (95 Tests Total):**
  - `ThemePresetsTests` (10 tests) & `ThemeExpansionIntegrationTests` (2 tests) verifying presets and multi-screen propagation.
  - `ThemeFileLoaderTests` (8 tests) & `StatusMenuThemeTests` (3 tests) validating custom theme lifecycles and dynamic menus.
  - `PinnedAppTests` (9 tests) & `PinnedAppsIntegrationTests` (8 tests) validating domain models, layout, recycling, and context menus.

#### Changed
- **Settings Persistence & Backward Compatibility:**
  - Extended `Settings` with `pinnedApps: [PinnedApp]`, defaulting to Finder, Safari, and Terminal for seamless backward compatibility with older v0.1.x preferences.

#### Fixed
- **macOS Window Minimization Subrole Morphing:**
  - Resolved an issue where minimized Cocoa windows temporarily morph their accessibility subrole to `AXDialog`, preventing dropped window buttons during Dock minimization.
- **Observer Notification Coalescing:**
  - Added `needsReconcileAgain` latching in `AppTracker` to prevent dropping notifications arriving during in-flight snapshot reconciliations.

---

## [0.1.1] - 2026-10-04

### Automated Test Harness, Performance Optimization & Theme Registry

Version `0.1.1` delivers foundational testing infrastructure, significant memory/rendering performance optimizations, a pure data-driven theme architecture, and comprehensive architectural documentation.

#### Added
- **Automated Test Harness (`scripts/test-functional.sh`):** Fail-fast test runner supporting `--quick` (functional lifecycle), `--edge-cases` (boundary conditions), `--stress` (100-window capacity & chevron overflow), and `--all` modes with automated memory (<45 MB RSS) and CPU benchmarking.
- **Formal Test Specifications (`docs/v0.1.1/TEST_SPECIFICATIONS.md`):** Complete test case taxonomy (`TC-FUNC-*`, `TC-EDGE-*`, `TC-STRESS-*`, `TC-PERF-*`, `TC-UNIT-*`) with preconditions, stimulus/actions, expected outcomes, and requirements traceability matrix.
- **Swift Testing Integration Suites (`Tests/TaskbarIntegrationTests`):**
  - `WindowLifecycleIntegrationTests`: Real-window lifecycle automation via `TestFixtureApp` (`TextEdit`) with guaranteed `defer { fixture.terminate() }` self-cleaning.
  - `EdgeCasesIntegrationTests`: Minimized 0x0 Chromium frame preservation, modal sheet/dialog (`AXSheet`/`AXDialog`) filtering, 25-burst rapid title debouncing, and dual-monitor boundary partitioning.
  - `StressIntegrationTests`: 100-window burst load capacity, overflow chevron activation, and pointer-equal button recycling.
- **Pure Data-Driven Theme Registry (`ThemeRegistry.swift`):** Decoupled visual styling into structured `Codable` token groups (`ThemePalette`, `ThemeMetrics`, `ThemeMaterials`). Supports runtime import/export of user `.json` themes alongside built-ins (`modern-hybrid`, `retro-classic`).
- **Shared Automation Utilities (`scripts/common.sh`):** Shared ANSI styling, logging helpers (`log_info`, `log_success`, `log_warn`, `log_error`), OS version validation, and single-source configuration loader used across all project scripts.
- **Centralized Test Benchmarking (`config/build.env`):** Single-source-of-truth configuration for test thresholds (`TEST_MAX_RSS_MB`, `TEST_MAX_CPU_PERCENT`, `TEST_AX_AUTH_TIMEOUT_SECONDS`, `TEST_FIXTURE_APP`).

#### Changed
- **Modular SPM Architecture:** Decoupled the project into `TaskbarCore` (pure Swift models/math/logging), `TaskbarKit` (AppKit & Accessibility engine), and `TaskbarApp` (executable entrypoint), enabling isolated unit and integration testing.
- **In-Place View Recycling:** Implemented `buttonMap: [WindowKey: TaskButton]` in `TaskbarView`, reusing button subview instances across updates and eliminating memory churn and tracking area thrashing.
- **Unified Logging (`TaskbarLogger`):** Replaced all ad-hoc `print(...)` statements with Apple's unified `os.Logger` across categories: `Lifecycle`, `Tracking`, `WorkArea`, `Dock`, and `UI`.
- **Hardened Observer Teardown:** Explicitly unregistered window and application notifications via `AXObserverRemoveNotification` prior to clearing run loop sources in `AXAppObserver`. Added explicit `stopTracking()` to `AppTracker` and `ScreenManager`.

#### Fixed
- Fixed transient heap allocations and tracking area churn during window switching.
- Resolved zero-sized (0x0) frame filtering anomalies for minimized Chromium/Electron windows.

---

## [0.1.0] - 2026-10-03

### Initial Release — Native Windows-Style Taskbar for macOS

Version `0.1.0` is the initial production release of **Taskbar**, a lightweight, native macOS agent application (`LSUIElement`) designed to replace the native Dock with a fast, responsive Windows-style taskbar using 100% public Apple APIs.

### Key Features

#### 🪟 Window Management & Task Buttons
- **1-to-1 Window Buttons:** Displays an application icon and truncated title for every standard window on the active desktop space.
- **Click Actions:**
  - Left-click unfocused button $\rightarrow$ raises and focuses the target window.
  - Left-click currently focused button $\rightarrow$ minimizes the window.
  - Left-click minimized button $\rightarrow$ unminimizes, restores, and focuses the window.
- **Context Menu:** Right-click task buttons to access Minimize/Restore, Close Window, and Quit Application.
- **Multi-Display Isolation:** Independent taskbars on every connected monitor showing only windows physically residing on that display. Dragging a window across screens moves its button automatically.
- **Overflow Handling:** When open windows exceed horizontal space, buttons gracefully shrink down to `minButtonWidth` (80pt default). Beyond that, an interactive overflow chevron (`»`) appears with a popup menu to activate hidden windows.
- **Dynamic Title Visibility:** Titles remain readable down to 50pt button width before switching to icon-only mode.

#### 🎨 Dual Visual Themes (Live Switching)
- **Modern Hybrid:** Native macOS frosted glass vibrancy (`NSVisualEffectView`), rounded pill buttons, subtle translucent hover borders, and system typography.
- **Retro Classic:** Authentic Windows 95/98 aesthetic with `#C0C0C0` gray background, 1pt white highlight border, classic 3D beveled borders ([`BevelDrawing`](file:///Sources/TaskbarApp/UI/BevelDrawing.swift)), and retro typography.
- Instant live switching between themes from the menu bar without application restart.

#### 📐 Screen Space Reservation (AX Nudger)
- **[`WorkAreaEnforcer`](file:///Sources/TaskbarApp/Tracking/WorkAreaEnforcer.swift):** Automatically clamps vertically maximized or tiled windows so their bottom edges (status bars, terminals, text inputs) remain visible above the taskbar.
- Built-in recursion guard (1.0pt delta) and settle debouncing (100ms) to eliminate window server feedback loops and animation stutter.

#### ⚓ System Dock Replacement & Safety
- **Configurable Autohide Delays:** Replaces the macOS Dock with user-selectable reveal timing:
  - `Permanently Hidden (1000s)` (Default)
  - `1.5s (Deliberate Hover)`
  - `1.0s (Slow Hover)`
  - `0.5s (Normal Autohide)`
  - `0.0s (Instant Reveal)`
- **Crash-Safe Restoration:** Captures original user Dock preferences on first run. Restores original settings on quit, `SIGINT`, `SIGTERM`, `SIGHUP`, `atexit`, or via [`scripts/restore-dock.sh`](file:///scripts/restore-dock.sh).
- **Process Optimization:** Avoids redundant `killall Dock` restarts when delays or toggles have not changed.

#### ⚙️ User Customization & Status Menu
- Accessible via the menu bar status item:
  - **Theme:** Modern Hybrid vs. Retro Classic.
  - **Taskbar Height:** 26 pt (Slim), 30 pt (Classic), 34 pt (Medium), 38 pt (Large), 44 pt (Spacious).
  - **Button Width / Overflow Threshold:** 28 pt (Icon only), 60 pt (Compact), 80 pt (Balanced), 100 pt (Roomy), 120 pt (Spacious).
  - **Font Size:** 10 pt (Small), 11 pt (Standard), 12 pt (Medium), 13 pt (Large), 14 pt (Extra Large).
  - **Icon Size:** 14 pt (Compact), 16 pt (Standard), 18 pt (Medium), 20 pt (Large), 24 pt (Extra Large).
  - **Dock Autohide Delay:** Live preset selector.
  - **Start Launcher:** Quick launch Spotlight (via synthetic Command+Space keystroke), Raycast, or custom executable.

#### ⚡ Performance & System Integration
- **Dedicated Background AX Thread:** All Accessibility IPC queries run on a dedicated thread with strict 300ms timeouts; target app hangs never freeze the Taskbar UI.
- **Event-Driven:** Zero polling timers. Idle CPU stays at ~0.0% with <35 MB RAM usage.
- **Full-Screen Space Suppression:** Taskbar panels automatically hide on native macOS full-screen spaces (keynote presentations, full-screen video, games).
- **Edge-Case Resilience:** Robust tracking for Chromium/Electron apps (Chrome, Discord, Slack, VS Code) reporting 0x0 minimized frames.
- **Centralized Design Tokens:** Fully centralized [`TaskbarConstants.swift`](file:///Sources/TaskbarCore/Config/TaskbarConstants.swift) and [`TaskbarStrings.swift`](file:///Sources/TaskbarCore/Config/TaskbarStrings.swift).
- **Test Coverage:** 41 automated unit tests across 8 test suites passing at 100%.
