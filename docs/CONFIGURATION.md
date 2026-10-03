# Configuration Reference

This guide details all configurable parameters for both the build pipeline and the runtime application.

---

## 1. Build & Packaging Configuration (`config/build.env`)

Located at the repository root in `config/build.env`. Sourced by `scripts/build-app.sh`.

| Variable | Default Value | Description |
|---|---|---|
| `APP_NAME` | `"Taskbar"` | Name of the assembled `.app` bundle and display name. |
| `BUNDLE_ID` | `"com.obertguo.taskbar"` | Reverse-DNS bundle identifier. |
| `APP_VERSION` | `"0.1.0"` | User-facing semantic version string (`CFBundleShortVersionString`). |
| `BUILD_NUMBER` | `"1"` | Build iteration string (`CFBundleVersion`). |
| `MIN_MACOS_VERSION`| `"14.0"` | Minimum supported macOS version. |
| `INSTALL_DIR` | `"$HOME/Applications"` | Destination path when running `./scripts/build-app.sh --install`. |
| `SIGN_IDENTITY` | `"auto"` | Code-signing identity. Set to `"auto"`, a certificate common name, or `"-"` for ad-hoc. |

---

## 2. Runtime User Preferences (`Sources/TaskbarCore/Config/Settings.swift`)

Runtime settings are managed through `Settings.swift` and persisted in `UserDefaults` under the domain `com.obertguo.taskbar`.

| Setting | Type | Default Value | Description |
|---|---|---|---|
| `themeStyle` | `ThemeStyle` | `.modernHybrid` | Visual style: `.modernHybrid` (vibrancy + pill buttons) or `.retroClassic` (gray `#C0C0C0` + 3D bevels). |
| `barHeight` | `CGFloat` | `30.0` | Vertical height in points of the taskbar on each screen. |
| `maxButtonWidth` | `CGFloat` | `160.0` | Maximum width in points for an individual window button. |
| `minButtonWidth` | `CGFloat` | `28.0` | Minimum width in points when the bar is crowded (icon only). |
| `launcherAction` | `LauncherAction`| `.spotlight` | Action triggered by Start button: `.spotlight`, `.raycast`, or `.customPath(String)`. |
| `enableAXNudger` | `Bool` | `true` | When `true`, automatically clamps maximized windows so bottom edges stay above the taskbar. |
| `hideSystemDock` | `Bool` | `true` | When `true`, hides the macOS system Dock while Taskbar is running. |

---

## 3. Theme Engine Configuration (`Sources/TaskbarCore/Config/Theme.swift`)

The visual theme is defined in `Theme.swift` without heavy runtime indirection:

### Modern Hybrid (`ThemeStyle.modernHybrid`)
- **Background:** `NSVisualEffectView` with `.underWindowBackground` material.
- **Button Shape:** Rounded rectangle pill with 4pt corner radius.
- **Typography:** `NSFont.systemFont(ofSize: 11, weight: .medium)`.
- **States:** Subtle translucency change on hover; darkened accent fill when active/focused.

### Retro Classic (`ThemeStyle.retroClassic`)
- **Background:** Solid `#C0C0C0` gray fill.
- **Top Border:** 1pt white highlight border.
- **Button Shape:** Square rectangle with classic 3D bevel borders.
  - Normal: Top/Left `#FFFFFF`, Bottom/Right `#404040`.
  - Focused / Pressed: Sunken bevel (Top/Left `#404040`, Bottom/Right `#FFFFFF`), background `#DCDCDC`.
- **Typography:** `NSFont.systemFont(ofSize: 11, weight: .regular)`.
