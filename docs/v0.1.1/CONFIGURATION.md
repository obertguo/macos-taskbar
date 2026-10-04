# Taskbar Configuration & Theming Guide (v0.1.1)

This document describes the build configuration, runtime settings persistence, shared script utilities, and pure data-driven theme architecture in **Taskbar** v0.1.1.

---

## 1. Build & Test Configuration (`config/build.env`)

All build metadata, packaging properties, and test benchmarks are governed by [`config/build.env`](../../config/build.env) as the single source of truth.

```env
# Build and Packaging Configuration
APP_NAME="Taskbar"
BUNDLE_ID="com.local.taskbar"
APP_VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS_VERSION="14.0"
INSTALL_DIR="~/Applications"

# Code Signing Identity (auto, specific identity, or ad-hoc "-")
SIGN_IDENTITY="auto"

# Test Harness & Benchmark Thresholds (used by scripts/test-functional.sh)
TEST_MAX_RSS_MB="45.0"
TEST_MAX_CPU_PERCENT="2.0"
TEST_AX_AUTH_TIMEOUT_SECONDS="15"
TEST_FIXTURE_APP="TextEdit"
```

### Configuration Variables Reference:

| Variable | Description | Default | Consumers |
|---|---|---|---|
| `APP_NAME` | Product display name and process name. | `"Taskbar"` | `build-app.sh`, `package-release.sh`, `test-functional.sh` |
| `BUNDLE_ID` | macOS bundle identifier and `UserDefaults` domain. | `"com.local.taskbar"` | `generate-config.sh`, `BuildConfiguration.swift` |
| `APP_VERSION` | Semantic release version (X.Y.Z). | `"0.1.1"` | `generate-config.sh`, `package-release.sh`, `Info.plist` |
| `BUILD_NUMBER` | Monotonically increasing build integer. | `"1"` | `generate-config.sh`, `Info.plist` |
| `MIN_MACOS_VERSION` | Minimum supported macOS version. | `"14.0"` | `generate-config.sh`, `test-functional.sh` |
| `INSTALL_DIR` | Destination directory for `--install` flag. | `"~/Applications"` | `build-app.sh` |
| `SIGN_IDENTITY` | Codesigning certificate identity (`"auto"` searches Keychain). | `"auto"` | `build-app.sh` |
| `TEST_MAX_RSS_MB` | Maximum allowed resident memory during stress tests. | `"45.0"` | `test-functional.sh` |
| `TEST_MAX_CPU_PERCENT` | Maximum allowed test burst CPU percentage. | `"2.0"` | `test-functional.sh` |
| `TEST_AX_AUTH_TIMEOUT_SECONDS` | Maximum seconds to wait for Accessibility permission prompt. | `"15"` | `test-functional.sh` |
| `TEST_FIXTURE_APP` | Application name used for real-window lifecycle fixtures. | `"TextEdit"` | `test-functional.sh` |

---

## 2. Shared Script Utilities (`scripts/common.sh`)

In v0.1.1, all bash scripts source [`scripts/common.sh`](../../scripts/common.sh) for shared utilities:
- **`load_build_env`:** Validates and loads `config/build.env` with fallback defaults.
- **`check_min_macos_version`:** Validates host OS version against `MIN_MACOS_VERSION`.
- **`find_app_pid` / `get_process_rss_kb` / `get_process_cpu_percent`:** Standardized process discovery and performance monitoring.
- **`log_info` / `log_success` / `log_warn` / `log_error` / `log_header`:** Standardized ANSI terminal output.

---

## 3. Pure Data-Driven Theming (`ThemeDefinition` & `ThemeRegistry`)

In v0.1.1, theme definitions are completely decoupled from code enums and represented as structured `Codable` schemas.

### 3.1 Theme Schema Structure

A theme is composed of three token groups:
1. **`ThemePalette`:** Color definitions serialized as normalized RGBA floating point values (`0.0`–`1.0`).
2. **`ThemeMetrics`:** Corner radii, bevel flags, font sizes, icon sizes.
3. **`ThemeMaterials`:** Translucency and material flags.

### 3.2 Custom Theme JSON Specification (`*.json`)

Users and tools can author custom themes in standard `.json` format:

```json
{
  "id": "nord-frost",
  "displayName": "Nord Frost",
  "isCustom": true,
  "palette": {
    "backgroundColor": { "red": 0.18, "green": 0.20, "blue": 0.25, "alpha": 0.95 },
    "topBorderColor": { "red": 0.24, "green": 0.27, "blue": 0.33, "alpha": 1.0 },
    "textNormal": { "red": 0.93, "green": 0.94, "blue": 0.96, "alpha": 1.0 },
    "textPressed": { "red": 1.0, "green": 1.0, "blue": 1.0, "alpha": 1.0 },
    "buttonNormal": { "red": 0.24, "green": 0.27, "blue": 0.33, "alpha": 0.8 },
    "buttonHover": { "red": 0.30, "green": 0.34, "blue": 0.42, "alpha": 0.9 },
    "buttonPressed": { "red": 0.34, "green": 0.38, "blue": 0.46, "alpha": 1.0 },
    "buttonBorderNormal": { "red": 0.24, "green": 0.27, "blue": 0.33, "alpha": 1.0 },
    "buttonBorderPressed": { "red": 0.35, "green": 0.70, "blue": 0.90, "alpha": 1.0 }
  },
  "metrics": {
    "buttonCornerRadius": 6.0,
    "is3DBeveled": false,
    "fontBold": false,
    "fontSize": 12.0,
    "iconSize": 16.0
  },
  "materials": {
    "useTranslucency": true
  }
}
```

### 3.3 Runtime Registry Management

The thread-safe singleton `ThemeRegistry.shared` manages themes at runtime:
- **Built-in Presets:**
  - `modern-hybrid`: Frosted glass vibrancy, pill buttons, translucent borders.
  - `retro-classic`: Windows 95/98 3D beveled silver aesthetic.
- **Import/Export:**
  - `ThemeRegistry.shared.importTheme(from: jsonData)` registers custom themes dynamically.
  - `ThemeRegistry.shared.exportTheme(withId: themeId)` serializes any active theme to pretty-printed JSON.

---

## 4. Runtime Settings Persistence (`Settings.swift`)

Settings are persisted in `UserDefaults` under the domain `com.local.taskbar`:

- **`activeThemeId: String`:** Stores the ID of the selected theme (e.g. `"modern-hybrid"`, `"retro-classic"`, or custom ID).
- **`barHeight: Double`:** Taskbar vertical height (default `30.0` pt).
- **`minButtonWidth: Double`:** Minimum button width before overflow (default `80.0` pt).
- **`fontSize: Double`:** Task button title text size (default `12.0` pt).
- **`iconSize: Double`:** Task button icon size (default `18.0` pt).
- **`enableAXNudger: Bool`:** Enables window clamping by `WorkAreaEnforcer` (default `true`).
- **`hideSystemDock: Bool`:** Hides the native macOS Dock (default `true`).
- **`dockHideDelay: Double`:** Autohide delay in seconds (default `1000.0`s).
- **`launcherAction: LauncherAction`:** Action invoked by Start button (`.spotlight`, `.raycast`, or `.customPath`).
