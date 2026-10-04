# macOS Taskbar Implementation Plan — Aligned & Updated

## Summary of Decisions

| Decision Area | Alignment / Resolution | Rationale |
|---|---|---|
| **Visual Style** | **Modern Hybrid & Retro Classic** (Live Switchable) | Both use the identical 1-window-to-1-button backend. Switchable via a lightweight `Theme` engine (AppKit `drawRect` bevels vs `NSVisualEffectView` translucency) with zero bloat. |
| **Button Model** | **1 Button per Window** | Displays app icon + window title. Left click focuses, minimizes (if already focused), or restores. Right-click context menu (Close/Quit). |
| **Screen Space** | **Floating Bar + AX Nudger (`WorkAreaEnforcer`)** | Maximized windows are actively nudged so their bottom edges (status bars, terminal prompts, input boxes) are never hidden under the bar. Includes recursion guard and debounce. |
| **Spaces & Monitors** | **Per-display, Current Space Only** | 100% public macOS Accessibility APIs (`kAXWindowsAttribute` per app). No fragile private SkyLight APIs; zero maintenance headaches across macOS updates. |
| **Start Button & Tray** | **Minimalist** | Start button triggers app launcher (Spotlight, Raycast, or Launchpad). Right edge is left empty, relying on the macOS top menu bar for clock and status. |
| **Dock Safety** | **Safe Autohide + Signal Traps** | Dock autohide set to 1000s delay; restored cleanly on quit, `SIGINT`, `SIGTERM`, `atexit`, menu bar item, and emergency `./scripts/restore-dock.sh`. |
| **Code Signing** | **Apple Development Cert** (via Xcode) | Binds to stable signing identity so macOS Accessibility permission sticks across rebuilds. |
| **Documentation** | **Modular Markdown Architecture** | `README.md` root handbook + `docs/ARCHITECTURE.md`, `docs/BUILD_AND_RELEASE.md`, `docs/CONFIGURATION.md`, `docs/TESTING.md`. |
| **Configuration** | **Centralized Config** | `config/build.env` for build/packaging metadata; `Settings.swift` for runtime user preferences. |
| **Engineering Philosophy** | **Performance-First & Pragmatic Extensibility** | Zero bloat, no over-engineering. Pure structs, direct AppKit drawing, cached 16x16 icons, event-driven zero-polling, with clean extensible hooks (`Theme`, `Settings`, `ButtonLayout`, `WindowFilter`). |

---

## File Structure

```
mac-dock-gemini/
├── Package.swift                     # SwiftPM configuration (macOS 14+)
├── README.md                         # Main guide for humans and AI agents
├── config/
│   └── build.env                     # App name, bundle ID, version, install dir
├── docs/
│   ├── ARCHITECTURE.md               # Threading, AX concurrency, data flow
│   ├── BUILD_AND_RELEASE.md          # Codesigning, building, installing
│   ├── CONFIGURATION.md              # Configuration reference
│   └── TESTING.md                    # Unit tests, mock harness, manual tests
├── Resources/
│   └── Info.plist                    # LSUIElement = true
├── scripts/
│   ├── build-app.sh                  # Release compile, bundle, sign, install
│   └── restore-dock.sh               # Standalone emergency Dock restore
├── Sources/
│   ├── TaskbarCore/                  # Pure Swift, unit-tested (zero OS dependencies)
│   │   ├── Model/                    # WindowInfo, AppInfo, WindowKey
│   │   ├── Logic/                    # ScreenAssignment, ButtonLayout, ClickPolicy, WindowFilter, WorkAreaMath, WindowStore
│   │   └── Config/                   # Settings, Theme (.modernHybrid & .retroClassic)
│   └── TaskbarApp/                   # AppKit shell & system integration
│       ├── main.swift                # App entry, POSIX signal handlers (SIGINT/SIGTERM/atexit)
│       ├── AppDelegate.swift         # Status bar menu, lifecycle, permissions
│       ├── StatusMenu.swift          # Menu bar icon: theme toggle, nudge toggle, restore dock, quit
│       ├── System/                   # AccessibilityPermission, DockController, Launcher
│       ├── Tracking/                 # AXThread, AppTracker, AXAppObserver, WorkAreaEnforcer
│       ├── Actions/                  # WindowActions (focus, minimize, restore, close, quit)
│       └── UI/                       # ScreenManager, TaskbarPanel, TaskbarView, TaskButton, StartButton, BevelDrawing
└── Tests/
    └── TaskbarCoreTests/             # Comprehensive unit test suite
```

---

## Execution Milestones

- **M0: Scaffold, Config & Documentation** — Package.swift, Info.plist, `config/build.env`, scripts, `README.md`, `docs/`.
- **M1: Panels & Theme Engine** — Multi-screen panels with live switching between Modern Hybrid and Retro Classic. Start button launches Spotlight/Raycast.
- **M2: Window Tracking & Core Tests** — Dedicated AX background thread, AppTracker, AXAppObserver, WindowStore, full unit test suite.
- **M3: Task Buttons & Window Actions** — 1-to-1 task buttons, left-click focus/minimize/restore, right-click menu, active window highlight.
- **M4: AX Nudger (`WorkAreaEnforcer`)** — Pure frame clamping logic + AX resize enforcer with recursion guard and settle debounce.
- **M5: Dock Controller & System Safety** — Auto-hide dock with signal traps, menu bar status icon, restore dock fallback.
- **M6: Polish & Verification** — Button overflow (`»`), performance benchmark (<40MB RSS, ~0.0% idle CPU).
