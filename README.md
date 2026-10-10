# Taskbar

A lightweight, native macOS agent application (`LSUIElement`) that replaces the macOS system Dock with a classic or modern Windows-style taskbar.

Designed for peak responsiveness, ~0.0% idle CPU, and rock-solid stability using 100% public Apple APIs.

---

## Features

- **Multi-Display & Spaces Aware:** Every connected display gets its own dedicated taskbar showing only windows physically residing on that display on the active Space.
- **1-to-1 Window Task Buttons:** Every open standard window gets a dedicated button displaying its application icon and window title.
- **In-Place View Recycling:** Updates reuse existing button subviews in place, eliminating transient memory allocations, heap churn, and mouse tracking area flicker.
- **Windows-Style Click Interactions:**
  - Click unfocused window button $\rightarrow$ Raises and focuses the target window without raising background windows across other displays.
  - Click already-focused window button $\rightarrow$ Minimizes the window.
  - Click minimized window button $\rightarrow$ Restores and focuses the window.
  - Right-click $\rightarrow$ Context menu with Minimize/Restore, Close Window, and Quit Application.
- **Application Window Grouping & Lightweight Popup:**
  - Group multi-window applications into single taskbar buttons with badge count indicators (`App Name (Count)`).
  - Three configurable grouping modes in Status Menu and Settings: `Always (Group multi-window apps)`, `When Crowded (Auto-group on overflow)`, and `Never (One button per window)`.
  - Clicking a grouped button opens `GroupWindowPopup`: a lightweight, native `NSPanel` listing open window titles, focused state dot indicators, and individual close (`✕`) buttons.
  - Complete keyboard navigation: `Up`/`Down` arrow keys to highlight windows, `Return` to focus and raise, `Escape` to dismiss.
  - Right-click context menu offers "Close All Windows" alongside app management actions.
- **Interactive Drag-and-Drop Slot Reordering:**
  - Reorder running task buttons horizontally with smooth real-time visual feedback and an insertion indicator bar.
  - Display-isolated ordering for running tasks: custom orders are scoped per screen, persisting seamlessly as windows move across displays.
  - Quick Launch pinned button reordering: dragging pinned shortcuts reorders items, syncs across all connected monitors in lockstep, and immediately persists to `settings.json`.
  - Clean cancelation on vertical drag escape or Escape key press.
- **Button Overflow Handling:** When window density is high, buttons shrink gracefully down to `minButtonWidth` (80pt default), after which an interactive overflow chevron (`»`) appears with a popup menu to activate hidden windows.
- **Pinned Applications / Quick Launch Bar:**
  - Compact square buttons rendered between the Start button and window task buttons across all monitors.
  - One-click launch for closed apps or instant raise/focus for running applications.
  - Subtle running indicator dot at the bottom center reflecting active window presence.
  - Right-click task buttons to toggle "Pin to Taskbar" / "Unpin from Taskbar" in real time.
- **Data-Driven Theming & Preset Expansion:**
  - Pure token-based theme architecture (`ThemeDefinition`) decoupling colors, metrics, and visual materials into structured `Codable` models.
  - **Modern Hybrid:** Native macOS frosted glass vibrancy (`NSVisualEffectView`), subtle rounded pill buttons, and `SF Pro` system typography.
  - **Retro Classic:** Windows 95/98 style with `#C0C0C0` solid background, 3D raised/sunken beveled borders, and classic typography.
  - **Windows XP Luna:** Iconic royal blue taskbar with signature emerald green Start button and gold accents.
  - **Dark Minimal:** Pitch black `#121212` background, subtle borders, and cyan `#00BCD4` active accent indicator.
  - **User Custom Theme Engine:** Discovers and validates `*.json` themes in `~/.config/taskbar/themes/` with live reload, layout metric adoption (`barHeight`, `minButtonWidth`, `maxButtonWidth`, `buttonSpacing`), and export tools in the Status Menu.
- **High-DPI & Multi-Resolution Icon Sanitization:**
  - Filters corrupt legacy low-resolution bitmaps (<64px) from third-party app bundles (e.g. Electron / Antigravity) when high-resolution representations exist, guaranteeing crisp bilinear anti-aliasing across mixed-DPI displays.
- **Screen Space Reservation via AX Nudger (`WorkAreaEnforcer`):** Maximized windows (from native zoom, double-click titlebar, Rectangle, Raycast, etc.) are actively clamped so their bottom edges (status bars, terminal prompts, input boxes) remain visible above the bar. Features multi-pass debounce settling (150ms / 400ms / 650ms), in-flight resize debounce protection against passive move/reconcile events, TCC authorization polling on ad-hoc binary startup, active mouse-drag deferral, and self-inflicted notification filtering to prevent jitter and feedback loops.
- **Configurable System Dock Replacement & Safety:** Safely hides the system Dock during execution with user-configurable autohide reveal delays (1000s Permanently Hidden, 1.5s Deliberate Hover, 1.0s, 0.5s, 0.0s). Restores original settings automatically on quit, `SIGINT`/`SIGTERM` signals, or via `./scripts/restore-dock.sh`.
- **Full-Screen Space Suppression:** Taskbar panels automatically hide on native macOS full-screen spaces (keynote presentations, full-screen video, games).
- **Status Menu Customization:** Adjust Theme, Window Grouping Mode, Taskbar Height (26–44pt), Button Width / Overflow Threshold (28–120pt), Font Size (10–14pt), and Icon Size (14–24pt) dynamically without restarting.
- **Minimalist Start Button:** Quick-launches your preferred application launcher (Spotlight via Command+Space keystroke, Raycast, or custom path).
- **Unified Diagnostic Logging:** Apple unified `os.Logger` integration categorized across `Lifecycle`, `Tracking`, `WorkArea`, `Dock`, and `UI` subsystems for low-overhead production diagnostics.

---

## Quickstart

### Prerequisites
- macOS 14.0 (Sonoma) or newer.
- Xcode 15+ or Xcode Command Line Tools with Swift 5.9+.
- Accessibility permission granted in System Settings.

### Build and Run
```bash
# Build release bundle, sign, and install to ~/Applications/Taskbar.app
./scripts/build-app.sh --install

# Or run automated test suites
swift test
```

### Automated Testing & Benchmarks
Taskbar includes a 3-tier test harness with automated memory and CPU benchmarking:
```bash
# Fast functional window lifecycle checks
./scripts/test-functional.sh --quick

# Edge-case suites (0x0 frames, sheets, debounce, multi-screen, settle passes)
./scripts/test-functional.sh --edge-cases

# Stress & capacity suite (100-window burst, chevron overflow, button recycling)
./scripts/test-functional.sh --stress

# Drag-and-drop slot reordering suite (TC-DRAG-*)
./scripts/test-functional.sh --reordering

# Application window grouping & popup suite (TC-GROUP-*)
./scripts/test-functional.sh --grouping

# Run all test suites (158 tests) + resident memory (<45 MB RSS) and CPU benchmarks
./scripts/test-functional.sh --all
```

### Packaging & Publishing Releases
```bash
# 1. Package DMG, ZIP, and SHA256 checksums into dist/
./scripts/package-release.sh

# Or bump semver (patch, minor, or major) and package
./scripts/package-release.sh --patch

# 2. One-time setup: configure GitLab Project ID and Token (gitignored)
cp config/gitlab.env.example config/gitlab.env
# Edit config/gitlab.env with your Project ID and Token

# 3. Upload to GitLab Package Registry & publish Release
./scripts/upload-release.sh --create-release
```

### Emergency Dock Restore
If the Dock ever remains hidden (e.g., following a force kill during development):
```bash
./scripts/restore-dock.sh
```

---

## Documentation Structure

For in-depth guides intended for human developers and AI coding agents:

- [**Changelog & Release Notes**](CHANGELOG.md): Complete release history and feature logs.
- [**Architecture & Concurrency Guide**](docs/ARCHITECTURE.md): SPM target hierarchy (`TaskbarCore`, `TaskbarKit`, `TaskbarApp`), threading model, AX concurrency, view recycling, work area clamping, focus isolation, and custom theme engine.
- [**Build & Release Guide**](docs/BUILD_AND_RELEASE.md): Compilation, code signing, installation, testing, and release packaging.
- [**Configuration Reference**](docs/CONFIGURATION.md): Centralized build settings (`config/build.env`), common shell utilities, and JSON theme specifications.
- [**Testing & Verification Guide**](docs/TESTING.md): 3-tier testing pyramid, fixture automation, runner modes, and resource benchmarking across 158 tests.
- [**Test Specifications Catalog**](docs/TEST_SPECIFICATIONS.md): Complete test taxonomy (`TC-FUNC-*`, `TC-EDGE-*`, `TC-STRESS-*`, `TC-PERF-*`, `TC-PIN-*`, `TC-THEME-*`, `TC-UNIT-*`) with requirement traceability.
- [**Codebase Conventions & Best Practices**](docs/CONVENTIONS.md): Architectural boundaries, threading invariants, constants management, and safety protocols.

---

## Engineering Principles

1. **Modular Architecture & Strict Decoupling:**
   - **`TaskbarCore`:** Pure Swift models, geometry math, layout solvers, logging, and data-driven theme registry. Zero AppKit/AX dependencies.
   - **`TaskbarKit`:** AppKit engine, AX thread, observer mechanics, and view recycling.
   - **`TaskbarApp`:** Minimal executable wrapper.
2. **Performance First:**
   - Pure event-driven updates via `NSWorkspace` and `AXObserver` notifications; zero background polling timers.
   - In-place view recycling (`buttonMap`) eliminates subview allocation thrashing during window changes.
   - Dedicated background AX thread with timeouts (~0.3s) ensures hung third-party apps never freeze the UI.
   - Application icons cached in memory per bundle identifier.
   - Target footprint: $< 45\text{ MB}$ RSS under load, $\sim 0.0\%$ idle CPU.
3. **Single Source of Truth:**
   - All build parameters, OS minimums, and test thresholds reside in [`config/build.env`](config/build.env).
   - Shell scripts share utilities, error traps, and colors via [`scripts/common.sh`](scripts/common.sh).
   - All layout dimensions, timeouts, and strings are centralized in [`TaskbarConstants.swift`](Sources/TaskbarCore/Config/TaskbarConstants.swift) and [`TaskbarStrings.swift`](Sources/TaskbarCore/Config/TaskbarStrings.swift).
