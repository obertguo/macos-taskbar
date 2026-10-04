# Configuration Reference (v0.1.1)

This document provides a comprehensive reference for build-time configuration, runtime user preferences, centralized design tokens, and localized copy catalogs.

---

## 1. Build & Packaging Configuration (`config/build.env`)

Defined in [`config/build.env`](file:///config/build.env) and processed by [`scripts/generate-config.sh`](file:///scripts/generate-config.sh):

| Variable | Default Value | Description |
|---|---|---|
| `APP_NAME` | `"Taskbar"` | User-facing application bundle name. |
| `BUNDLE_ID` | `"com.local.taskbar"` | Reverse-DNS bundle identifier used for TCC permissions and `UserDefaults`. |
| `APP_VERSION` | `"0.1.0"` | Semantic version string (`CFBundleShortVersionString`). |
| `BUILD_NUMBER` | `"1"` | Internal build number (`CFBundleVersion`). |
| `MIN_MACOS_VERSION`| `"14.0"` | Minimum supported macOS version. |
| `INSTALL_DIR` | `"~/Applications"` | Target directory for `./scripts/build-app.sh --install`. |
| `SIGN_IDENTITY` | `"auto"` | Signing identity (`"auto"`, certificate common name, or `"-"` for ad-hoc). |

Values are compiled into the typed Swift struct [`BuildConfiguration`](file:///Sources/TaskbarCore/Config/BuildConfiguration.swift) and injected into `Resources/Info.plist`.

---

## 2. Runtime User Preferences (`Settings.swift`)

Preferences are strongly typed in [`Settings.swift`](file:///Sources/TaskbarCore/Config/Settings.swift), encoded as JSON, and persisted in `UserDefaults` under the domain `com.local.taskbar`.

| Property | Type | Default Value | Description |
|---|---|---|---|
| `themeStyle` | `ThemeStyle` | `.modernHybrid` | Active theme (`.modernHybrid` or `.retroClassic`). |
| `barHeight` | `Double` | `30.0` pt | Taskbar panel height. Presets: 26, 30, 34, 38, 44 pt. |
| `maxButtonWidth` | `Double` | `160.0` pt | Maximum button width when horizontal space is unconstrained. |
| `minButtonWidth` | `Double` | `80.0` pt | Minimum width before buttons overflow. Presets: 28, 60, 80, 100, 120 pt. |
| `buttonSpacing` | `Double` | `2.0` pt | Horizontal spacing between adjacent task buttons. |
| `titleVisibilityThreshold` | `Double` | `50.0` pt | Button width threshold below which titles hide (rendering icon-only). |
| `fontSize` | `Double` | `11.0` pt | Typography size for button labels. Presets: 10, 11, 12, 13, 14 pt. |
| `iconSize` | `Double` | `16.0` pt | Dimensions of window application icons. Presets: 14, 16, 18, 20, 24 pt. |
| `launcherAction` | `LauncherAction` | `.spotlight` | Triggered by Start button: `.spotlight`, `.raycast`, or `.customPath(String)`. |
| `enableAXNudger` | `Bool` | `true` | When enabled, clamps maximized windows above the taskbar. |
| `hideSystemDock` | `Bool` | `true` | When enabled, hides native macOS Dock. |
| `dockHideDelay` | `Double` | `1000.0` s | Dock autohide reveal delay. Presets: 1000s, 1.5s, 1.0s, 0.5s, 0.0s. |

### Backward-Compatible Decoding
`Settings.init(from: Decoder)` implements `decodeIfPresent` fallbacks for all properties. If a user upgrades from an older version lacking newly introduced keys (`fontSize`, `iconSize`, `dockHideDelay`), settings deserialize cleanly using default constants without crashing or resetting other user preferences.

---

## 3. Centralized Constants (`TaskbarConstants.swift`)

All design tokens, layout dimensions, geometry ratios, debounce intervals, and system binary paths are centralized in [`TaskbarConstants.swift`](file:///Sources/TaskbarCore/Config/TaskbarConstants.swift):

### Layout Constants (`TaskbarConstants.Layout`)
- `defaultBarHeight = 30.0` pt
- `defaultMinButtonWidth = 80.0` pt
- `defaultMaxButtonWidth = 160.0` pt
- `defaultButtonSpacing = 2.0` pt
- `defaultTitleVisibilityThreshold = 50.0` pt
- `defaultFontSize = 11.0` pt
- `defaultIconSize = 16.0` pt
- **Presets Available in Status Menu:**
  - `barHeightPresets`: `[Slim: 26, Classic: 30, Medium: 34, Large: 38, Spacious: 44]`
  - `buttonWidthPresets`: `[Icon Only: 28, Compact: 60, Balanced: 80, Roomy: 100, Spacious: 120]`
  - `fontSizePresets`: `[Small: 10, Standard: 11, Medium: 12, Large: 13, Extra Large: 14]`
  - `iconSizePresets`: `[Compact: 14, Standard: 16, Medium: 18, Large: 20, Extra Large: 24]`

### WorkArea & Window Geometry (`TaskbarConstants.WorkArea`)
- `minimumWindowHeight = 100.0` pt: Prevents window collapsing into invisible slices.
- `overlapTolerance = 2.0` pt: Sub-pixel tolerance ignoring insignificant edge touch.
- `screenHeightMaximizedRatio = 0.45`: Requires windows to occupy $\ge 45\%$ of screen height to qualify as vertically maximized/tiled.
- `screenTopToleranceBase = 120.0` pt: Origin tolerance accounting for menu bar, notch, and title bars.
- `clampingRecursionGuardDelta = 1.0` pt: Threshold below which minor adjustments are ignored to prevent feedback loops.
- `minimumWindowDimension = 50.0` pt: Excludes tiny tracking elements and invisible helper windows.

### Debounce & Timing (`TaskbarConstants.Debounce`)
- `settleInterval = 0.1` s: Settling delay before clamping window frames after live drag/resize.
- `coalescingInterval = 0.016` s: 16ms window batching AX notifications per display refresh frame.

### System Dock Constants (`TaskbarConstants.Dock`)
- `defaultAutohideDelaySeconds = 1000.0` s
- `dockDelayPresets`:
  - `1000.0` s: Permanently Hidden
  - `1.5` s: Deliberate Hover
  - `1.0` s: Slow Hover
  - `0.5` s: Normal Autohide
  - `0.0` s: Instant Reveal
- `defaultsBinaryPath = "/usr/bin/defaults"`
- `killallBinaryPath = "/usr/bin/killall"`
- `domain = "com.apple.dock"`
- `autohideKey = "autohide"`
- `autohideDelayKey = "autohide-delay"`
- `originalStateUserDefaultsKey = "com.taskbar.original_dock_state"`

---

## 4. Localized Copy Catalog (`TaskbarStrings.swift`)

All user-facing strings are defined in [`TaskbarStrings.swift`](file:///Sources/TaskbarCore/Config/TaskbarStrings.swift):
- **`StartButton`**: Title (`"Start"`), SF Symbol (`"square.grid.2x2.fill"`), fallback glyph (`"⊞"`).
- **`Overflow`**: Button glyph (`"»"`).
- **`StatusMenu`**: App header, submenu titles (`Theme`, `Taskbar Height`, `Button Width`, `Font Size`, `Icon Size`, `Dock Autohide Delay`), action items (`Open Start Launcher`, `Nudge Maximized Windows`, `Hide macOS System Dock`, `Restore System Dock Now`, `Quit Taskbar`).
- **`Presets`**: Display titles for all dimension and delay options.
- **`Themes`**: Display names for `Modern Hybrid` and `Retro Classic`.

---

## 5. Status Menu Controls Reference

Clicking the Taskbar status item in the macOS menu bar presents:

1. **Header:** Disabled item displaying app name and version (e.g. `Taskbar v0.1.0`).
2. **Theme Submenu:** Switch between `Modern Hybrid` and `Retro Classic` with instant redraw.
3. **Taskbar Height Submenu:** Choose from Slim (26pt) up to Spacious (44pt).
4. **Button Width Submenu:** Adjust overflow trigger threshold from Icon-Only (28pt) up to Spacious (120pt).
5. **Font Size Submenu:** Adjust label typography from Small (10pt) to Extra Large (14pt).
6. **Icon Size Submenu:** Adjust application icon size from Compact (14pt) to Extra Large (24pt).
7. **Open Start Launcher:** Triggers the configured launcher (Spotlight / Raycast).
8. **Nudge Maximized Windows:** Toggles the `WorkAreaEnforcer` AX background clamping.
9. **Hide macOS System Dock:** Toggles hiding the system Dock.
10. **Dock Autohide Delay Submenu:** When Dock is hidden, choose reveal delay (1000s, 1.5s, 1.0s, 0.5s, 0.0s).
11. **Restore System Dock Now:** Immediately restores original user Dock settings.
12. **Quit Taskbar:** Cleanly restores the Dock and terminates the process.
