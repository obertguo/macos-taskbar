# Testing & Verification Guide (v0.1.1)

This document describes the automated test architecture, unit test suites, stress testing procedures, and manual verification checklists for `Taskbar.app`.

---

## 1. Automated Unit Testing

All core layout geometry, window filtering, screen assignment, state reconciliation, and settings serialization are implemented in `TaskbarCore` without AppKit or Accessibility dependencies and are 100% testable via `XCTest`.

### Running Tests
```bash
swift test
```

### Test Suite Directory (`Tests/TaskbarCoreTests/`)

The suite executes **41 automated tests** across **9 test suites** with 100% pass rate:

1. **[`ClickPolicyTests.swift`](file:///Tests/TaskbarCoreTests/ClickPolicyTests.swift) (5 tests):**
   - `testClickUnfocusedWindow`: Verifies clicking an unfocused window raises and activates it.
   - `testClickFocusedWindow`: Verifies clicking the currently focused window minimizes it.
   - `testClickMinimizedWindow`: Verifies clicking a minimized window restores and focuses it.
   - `testClickHiddenWindow`: Verifies clicking a hidden app window unhides and activates it.
   - `testClickWindowOnSecondaryScreen`: Verifies cross-display activation behavior.

2. **[`ScreenAssignmentTests.swift`](file:///Tests/TaskbarCoreTests/ScreenAssignmentTests.swift) (3 tests):**
   - `testWindowWhollyInsideScreen`: Confirms assignment when window frame is completely within display bounds.
   - `testWindowSpanningBothScreens`: Confirms majority intersection area rule when window straddles two displays.
   - `testOffscreenFallback`: Validates fallback to primary display when a window is moved offscreen.

3. **[`SettingsTests.swift`](file:///Tests/TaskbarCoreTests/SettingsTests.swift) (5 tests):**
   - `testDefaultSettings`: Validates all default constants and configuration values.
   - `testSettingsEncodingDecoding`: Verifies lossless JSON roundtrip serialization.
   - `testBackwardCompatibleDecodingWithoutDockHideDelay`: Ensures legacy saved settings missing newly added properties decode without crashing.
   - `testUserDefaultsPersistence`: Confirms saving and loading from persistent `UserDefaults`.
   - `testTaskbarStringsAndPresets`: Asserts preset arrays contain their respective defaults.

4. **[`TaskbarCoreTests.swift`](file:///Tests/TaskbarCoreTests/TaskbarCoreTests.swift) (1 test):**
   - `testBuildConfiguration`: Validates compiled build configuration metadata against expected bundle settings.

5. **[`ThemeTests.swift`](file:///Tests/TaskbarCoreTests/ThemeTests.swift) (2 tests):**
   - `testModernHybridTheme`: Validates color tokens, corner radii, and materials for Modern Hybrid.
   - `testRetroClassicTheme`: Validates classic beveled color tokens and dimensions for Retro Classic.

6. **[`WindowFilterTests.swift`](file:///Tests/TaskbarCoreTests/WindowFilterTests.swift) (5 tests):**
   - `testAcceptStandardWindow`: Validates acceptance of standard application windows.
   - `testRejectDialogsAndSheets`: Rejects modals, sheets, palettes, popovers, and drawers.
   - `testRejectNonRegularAppsAndSystemOverlays`: Excludes system daemons (Dock, Spotlight, ControlCenter).
   - `testAcceptMinimizedWindowWithZeroSize`: Retains minimized Chromium/Electron windows reporting $0 \times 0$ dimensions.
   - `testRejectTinyZeroSizedNonMinimizedWindows`: Discards hidden tracking windows and zero-sized helper frames.

7. **[`WindowStoreTests.swift`](file:///Tests/TaskbarCoreTests/WindowStoreTests.swift) (4 tests):**
   - `testAddAndOrderWindows`: Asserts stable creation-order sorting of window entries.
   - `testDisplayPartitioning`: Validates partitioning of window lists by assigned display ID.
   - `testFullScreenTransitionTracking`: Validates `isFullScreen` flag updates during full-screen transitions.
   - `testSyncSnapshotReconciliation`: Confirms diffing and atomic snapshot replacement during space transitions.

8. **[`WorkAreaMathTests.swift`](file:///Tests/TaskbarCoreTests/WorkAreaMathTests.swift) (10 tests):**
   - `testZeroTaskbarHeight`: Returns unmodified frame when taskbar reservation is zero.
   - `testWindowFlushWithTaskbar`: No overlap when window bottom touches taskbar top edge exactly.
   - `testSubpixelOverlapWithinThreshold`: Ignores subpixel variances $\le 2.0\text{ pt}$.
   - `testWindowBelowTaskbarRejected`: Excludes windows whose top edge is completely behind the taskbar.
   - `testWindowTooSmallAfterClamping`: Rejects adjustments that would collapse window height $< 100.0\text{ pt}$.
   - `testMaximizedWindowClamping`: Accurately computes clamped height for vertically maximized windows.
   - `testMultiMonitorClampingOnSecondaryScreen`: Validates coordinate transformation on secondary displays with non-zero origins.
   - `testIsVerticallyMaximized`: Validates detection of maximized/tiled windows based on screen height ratios.
   - `testAllowNonMaximizedFlag`: Respects manual override flags.
   - `testNoOverlap`: Returns `nil` when window is positioned comfortably above the bar.

9. **[`ButtonLayoutTests.swift`](file:///Tests/TaskbarCoreTests/ButtonLayoutTests.swift):**
   - Proportional button width contraction under crowding.
   - Accurate title truncation and `showTitle` flag evaluation at 50pt threshold.
   - Triggering and calculation of overflow chevron count.

---

## 2. Release Bundle Verification

After compiling with `./scripts/build-app.sh --install`, verify bundle integrity:

```bash
# Verify code signature
codesign --verify --deep --strict ~/Applications/Taskbar.app

# Check architecture
file ~/Applications/Taskbar.app/Contents/MacOS/TaskbarApp
```

---

## 3. High-Density & Stress Testing

### Benchmarking Window Overflow
To test layout responsiveness and overflow behavior with high window counts:
1. Open multiple applications (Terminal, Safari, TextEdit, Finder, Calculator).
2. Spawn 20–30 windows (or run a loop opening synthetic windows).
3. **Verify:**
   - Buttons compress gracefully down to `minButtonWidth` (default 80pt).
   - Window titles remain legible until reaching `titleVisibilityThreshold` (50pt).
   - Once total button width exceeds available screen width, the overflow button (`»`) appears.
   - Clicking `»` opens an interactive menu containing all hidden windows.
   - Selecting any window in the overflow menu immediately brings it to focus.
4. **Resource Verification:**
   - Open **Activity Monitor** $\rightarrow$ Search for `TaskbarApp`.
   - Verify Memory (RSS) remains $< 40\text{ MB}$.
   - Verify CPU usage settles to $0.0\%$ when the desktop is idle.

---

## 4. Manual Verification Checklist

| # | Feature / Test Area | Action | Expected Result |
|---|---|---|---|
| 1 | **Accessibility Onboarding** | Launch app on clean setup | Prompts for Accessibility. When enabled in System Settings, taskbars populate immediately without relaunching. |
| 2 | **Multi-Display Isolation** | Open windows on Display 1 and Display 2 | Display 1 taskbar displays only Display 1 windows; Display 2 taskbar displays only Display 2 windows. |
| 3 | **Window Drag Across Displays** | Drag a window between two screens | Task button transitions to the target display taskbar as soon as the majority area crosses the boundary. |
| 4 | **Space Switching** | Switch Mission Control Desktops (Spaces) | Taskbars update instantly to show windows belonging to the active Space. Minimized windows remain visible. |
| 5 | **Native Full-Screen Spaces** | Switch to a native full-screen app (e.g. Keynote or full-screen video) | Taskbar panels automatically hide on the full-screen space, reappearing when returning to standard desktops. |
| 6 | **Click Actions** | Click unfocused button $\rightarrow$ click focused button $\rightarrow$ click minimized button | 1st: Raises and focuses window. 2nd: Minimizes window. 3rd: Restores and focuses window. |
| 7 | **Context Menu** | Right-click a task button | Context menu displays: Minimize / Restore, Close Window, Quit App. Clicking actions executes them immediately. |
| 8 | **WorkArea Nudger** | Maximize a window (Terminal / VS Code) | Window height clamps smoothly above the taskbar; terminal command prompts and status bars remain visible. |
| 9 | **Theme Toggle** | Status Menu $\rightarrow$ Theme $\rightarrow$ Retro Classic / Modern Hybrid | Taskbars on all monitors switch themes instantly without flickering or restart. |
| 10 | **Layout Sizing Controls** | Status Menu $\rightarrow$ Height, Button Width, Font Size, Icon Size | Taskbars resize and redraw immediately; button text vertically aligns with icon centers. |
| 11 | **Dock Autohide Delays** | Status Menu $\rightarrow$ Dock Autohide Delay $\rightarrow$ 1.5s / 0.0s / 1000s | Delay updates immediately in system preferences; Dock reveals according to selected hover delay. |
| 12 | **Clean Termination & Recovery** | Quit via Status Menu or `kill -SIGTERM` | Native macOS Dock restores original settings immediately; taskbar panels close cleanly. |
