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
- **Dual Visual Styles (Hybrid & Retro):**
  - **Modern Hybrid:** Native macOS frosted glass vibrancy (`NSVisualEffectView`), subtle rounded pill buttons, and `SF Pro` system typography.
  - **Retro Classic:** Windows 98/2000 style with `#C0C0C0` solid background, 3D raised/sunken beveled borders, and classic typography.
  - Switchable on-the-fly via the menu bar status icon.
- **Screen Space Reservation via AX Nudger (`WorkAreaEnforcer`):** Maximized windows (from native zoom, Rectangle, Raycast, etc.) are actively clamped so their bottom edges (status bars, terminal prompts, input boxes) remain visible above the bar.
- **Minimalist Start Button:** Quick-launches your preferred application launcher (Spotlight, Raycast, or Launchpad).
- **Dock Replacement & Crash Recovery:** Safely hides the system Dock during execution. Restores the Dock automatically on exit, `SIGINT`/`SIGTERM` signals, crash recovery, or via the menu bar icon and `./scripts/restore-dock.sh`.

---

## Quickstart

### Prerequisites
- macOS 14.0 (Sonoma) or newer.
- Xcode or Command Line Tools with Swift 6.0+.
- Accessibility permission granted in System Settings.

### Build and Run
```bash
# Build release bundle, sign, and install to ~/Applications/Taskbar.app
./scripts/build-app.sh --install

# Or run tests
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

- [**Architecture & Concurrency Guide**](docs/ARCHITECTURE.md): Threading model, AX concurrency, non-blocking UI, and data flow.
- [**Build & Release Guide**](docs/BUILD_AND_RELEASE.md): Xcode configuration, code signing identities, and release packaging.
- [**Configuration Reference**](docs/CONFIGURATION.md): Centralized build settings (`config/build.env`) and runtime user preferences (`Settings.swift`).
- [**Testing & Verification**](docs/TESTING.md): Unit test specifications, mock window system harness, and manual verification checklists.

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
   - Extensibility hooks (`Theme`, `Settings`, `ButtonLayout`, `WindowFilter`) designed for straightforward addition of future options.
