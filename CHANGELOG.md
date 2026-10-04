# Changelog

All notable changes to **Taskbar** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
