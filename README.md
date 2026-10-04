# Taskbar

A lightweight, native macOS agent application (`LSUIElement`) that replaces the macOS system Dock with a classic or modern Windows-style taskbar.

Designed for peak responsiveness, ~0.0% idle CPU, and rock-solid stability using 100% public Apple APIs.

---

## Features

- **Multi-Display & Spaces Aware:** Every connected display gets its own dedicated taskbar showing only windows physically residing on that display on the active Space.
- **1-to-1 Window Task Buttons:** Every open standard window gets a dedicated button displaying its application icon and window title.
- **Windows-Style Click Interactions:**
  - Click unfocused window button $\rightarrow$ Raises and focuses the window.
  - Click already-focused window button $\rightarrow$ Minimizes the window.
  - Click minimized window button $\rightarrow$ Restores and focuses the window.
  - Right-click $\rightarrow$ Context menu with Minimize/Restore, Close Window, and Quit Application.
- **Button Overflow Handling:** When window density is high, buttons shrink gracefully down to `minButtonWidth` (80pt default), after which an interactive overflow chevron (`»`) appears with a popup menu to activate hidden windows.
- **Dual Visual Styles (Hybrid & Retro):**
  - **Modern Hybrid:** Native macOS frosted glass vibrancy (`NSVisualEffectView`), subtle rounded pill buttons, and `SF Pro` system typography.
  - **Retro Classic:** Windows 95/98 style with `#C0C0C0` solid background, 3D raised/sunken beveled borders, and classic typography.
  - Switchable on-the-fly via the menu bar status icon.
- **Screen Space Reservation via AX Nudger (`WorkAreaEnforcer`):** Maximized windows (from native zoom, Rectangle, Raycast, etc.) are actively clamped so their bottom edges (status bars, terminal prompts, input boxes) remain visible above the bar.
- **Configurable System Dock Replacement & Safety:** Safely hides the system Dock during execution with user-configurable autohide reveal delays (1000s Permanently Hidden, 1.5s Deliberate Hover, 1.0s, 0.5s, 0.0s). Restores original settings automatically on quit, `SIGINT`/`SIGTERM` signals, or via `./scripts/restore-dock.sh`.
- **Full-Screen Space Suppression:** Taskbar panels automatically hide on native macOS full-screen spaces (keynote presentations, full-screen video, games).
- **Status Menu Customization:** Adjust Theme, Taskbar Height (26–44pt), Button Width / Overflow Threshold (28–120pt), Font Size (10–14pt), and Icon Size (14–24pt) dynamically without restarting.
- **Minimalist Start Button:** Quick-launches your preferred application launcher (Spotlight via Command+Space keystroke, Raycast, or custom path).

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

# Or run automated unit tests
swift test
```

### Emergency Dock Restore
If the Dock ever remains hidden (e.g., following a force kill during development):
```bash
./scripts/restore-dock.sh
```

---

## Documentation Structure

For in-depth guides intended for human developers and AI coding agents:

- [**Changelog & Release Notes**](CHANGELOG.md): Release history and feature log for v0.1.0.
- [**Architecture & Concurrency Guide**](docs/v0.1.0/ARCHITECTURE.md): Threading model, AX concurrency, non-blocking UI, and data flow.
- [**Build & Release Guide**](docs/v0.1.0/BUILD_AND_RELEASE.md): Xcode configuration, code signing identities, and release packaging.
- [**Configuration Reference**](docs/v0.1.0/CONFIGURATION.md): Centralized build settings (`config/build.env`) and runtime user preferences (`Settings.swift`).
- [**Testing & Verification**](docs/v0.1.0/TESTING.md): Unit test specifications, mock window system harness, and manual verification checklists.
- [**Codebase Conventions & Best Practices**](docs/v0.1.0/CONVENTIONS.md): Architectural boundaries, threading invariants, constants management, and safety protocols.

---

## Engineering Principles

1. **Performance First:**
   - Pure event-driven updates via `NSWorkspace` and `AXObserver` notifications; zero background polling timers.
   - Dedicated background AX thread with timeouts (~0.3s) ensures hung third-party apps never freeze the UI.
   - 16x16 application icons are cached per bundle identifier.
   - Target footprint: <40 MB RAM, ~0.0% idle CPU.
2. **Pragmatic Extensibility (No Over-Engineering):**
   - Pure Swift value types (`struct`) for models and settings.
   - Clean, direct AppKit drawing without bloated abstraction layers.
   - All layout dimensions, timeouts, and strings are centralized in [`TaskbarConstants.swift`](Sources/TaskbarCore/Config/TaskbarConstants.swift) and [`TaskbarStrings.swift`](Sources/TaskbarCore/Config/TaskbarStrings.swift).
   - Architectural invariants documented in [`CONVENTIONS.md`](docs/v0.1.0/CONVENTIONS.md).
