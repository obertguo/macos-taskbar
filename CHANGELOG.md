# Changelog

All notable changes to **Taskbar** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
