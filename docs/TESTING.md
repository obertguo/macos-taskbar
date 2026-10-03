# Testing & Verification Guide

This document describes the testing strategy, unit test suites, mock test harness, and manual verification procedures for `Taskbar`.

---

## 1. Automated Testing

All core business logic is encapsulated in `TaskbarCore` without AppKit or Accessibility dependencies and is 100% testable via standard `XCTest`.

Run unit tests via:
```bash
swift test
```

### Unit Test Suites (`Tests/TaskbarCoreTests/`)

1. **`ScreenAssignmentTests.swift`:**
   - Verifies conversion between AX coordinates (top-left origin) and Cocoa coordinates (bottom-left origin).
   - Validates multi-monitor assignment: assigning a window to the screen containing the majority of its area.
   - Tests fallback behavior when a window sits between screens or is moved off-screen.

2. **`ButtonLayoutTests.swift`:**
   - Tests proportional button width shrinking when the bar is crowded (down to `minButtonWidth = 28.0`).
   - Verifies truncation of titles and calculation of `showTitle` flag.
   - Verifies overflow button (`»`) calculation when window count exceeds available horizontal width.

3. **`ClickPolicyTests.swift`:**
   - Tests state transitions:
     - Unfocused window $\rightarrow$ `.focus`
     - Already focused window $\rightarrow$ `.minimize`
     - Minimized / hidden window $\rightarrow$ `.restoreAndFocus`

4. **`WindowFilterTests.swift`:**
   - Validates rejection of non-standard windows: sheets, popovers, palettes, menu bars, and zero-sized hidden windows.
   - Confirms acceptance of standard application windows (`kAXStandardWindowSubrole`).

5. **`WorkAreaMathTests.swift`:**
   - Validates clamping logic:
     - Maximized window touching bottom edge $\rightarrow$ height reduced by taskbar height.
     - Window already above the taskbar $\rightarrow$ returns `nil` (no-op, preventing recursive AX updates).
     - Full-screen or non-overlapping windows $\rightarrow$ returns `nil`.

6. **`WindowStoreTests.swift`:**
   - Uses a `MockWindowSystem` to simulate windows opening, moving, renaming, minimizing, and closing.
   - Asserts stable open-order sorting.

---

## 2. Release Bundle Verification

After building and packaging, verify the integrity and signature of `Taskbar.app`:

```bash
# Verify bundle structure and signature
codesign --verify --deep --strict ~/Applications/Taskbar.app

# Check binary architecture
file ~/Applications/Taskbar.app/Contents/MacOS/TaskbarApp
```

---

## 3. Manual Verification Checklist

Follow this checklist when verifying a build:

| # | Test Case | Action | Expected Result |
|---|---|---|---|
| 1 | **Accessibility Prompt** | Launch `Taskbar.app` on a clean system | Prompts for Accessibility in System Settings. Upon toggle, bar populates immediately. |
| 2 | **Multi-Display Isolation** | Open windows on Display 1 and Display 2 | Display 1 taskbar shows only Display 1 windows; Display 2 taskbar shows only Display 2 windows. |
| 3 | **Window Drag** | Drag a window from Display 1 to Display 2 | Its task button moves from Display 1 bar to Display 2 bar as soon as majority area crosses screens. |
| 4 | **Space Switch** | Switch to a different Desktop / Space | Bar updates to reflect windows on that active Desktop. Minimized windows remain accessible. |
| 5 | **Click-to-Focus & Minimize** | Click an unfocused button; then click it again | 1st click: window raises and focuses. 2nd click: window minimizes. 3rd click: restores and focuses. |
| 6 | **Right-Click Context Menu** | Right-click a task button | Context menu appears with: Minimize/Restore, Close Window, Quit Application. |
| 7 | **AX Nudger Clamping** | Double-click title bar or maximize window | Window stops cleanly above the taskbar; bottom status bars and prompt lines remain visible. |
| 8 | **Theme Switch** | Click menu bar icon $\rightarrow$ Toggle Theme | Bar switches between Modern Hybrid and Retro Classic immediately. |
| 9 | **Dock Recovery** | Terminate app with `kill -SIGTERM` or quit via menu | macOS system Dock is immediately restored to standard settings. |
| 10 | **Performance Budget** | Open 30+ windows and monitor in Activity Monitor | Memory footprint < 40 MB; idle CPU remains ~0.0%. |
