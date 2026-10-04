# Taskbar Configuration & Theming Guide (v0.2.0)

This document describes the build configuration, runtime settings persistence, user custom theme JSON schema, and pinned applications configuration in **Taskbar** v0.2.0.

---

## 1. Build & Test Configuration (`config/build.env`)

All build metadata, packaging properties, and test benchmarks are governed by [`config/build.env`](../../config/build.env) as the single source of truth.

```env
# Build and Packaging Configuration
APP_NAME="Taskbar"
BUNDLE_ID="com.local.taskbar"
APP_VERSION="0.2.0"
BUILD_NUMBER="3"
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
| `APP_VERSION` | Semantic release version (X.Y.Z). | `"0.2.0"` | `generate-config.sh`, `package-release.sh`, `Info.plist` |
| `BUILD_NUMBER` | Monotonically increasing build integer. | `"3"` | `generate-config.sh`, `Info.plist` |
| `MIN_MACOS_VERSION` | Minimum supported macOS version. | `"14.0"` | `generate-config.sh`, `test-functional.sh` |
| `INSTALL_DIR` | Destination directory for `--install` flag. | `"~/Applications"` | `build-app.sh` |
| `SIGN_IDENTITY` | Codesigning certificate identity (`"auto"` searches Keychain). | `"auto"` | `build-app.sh` |
| `TEST_MAX_RSS_MB` | Maximum allowed resident memory during stress tests. | `"45.0"` | `test-functional.sh` |
| `TEST_MAX_CPU_PERCENT` | Maximum allowed test burst CPU percentage. | `"2.0"` | `test-functional.sh` |
| `TEST_AX_AUTH_TIMEOUT_SECONDS` | Maximum seconds to wait for Accessibility permission prompt. | `"15"` | `test-functional.sh` |
| `TEST_FIXTURE_APP` | Application name used for real-window lifecycle fixtures. | `"TextEdit"` | `test-functional.sh` |

---

## 2. Runtime Settings Persistence (`Settings.swift`)

Settings are stored in the user's domain via `UserDefaults.standard` under the key `com.local.taskbar.settings` and synchronized across all displays.

### Settings Model Properties:
- `barHeight`: Taskbar panel vertical thickness in points (default: `30.0`, range: `26.0` – `44.0`).
- `buttonWidth`: Maximum width of task buttons before shrinking (default: `160.0`, range: `80.0` – `240.0`).
- `fontSize`: Typography point size across buttons (default: `12.0`, range: `10.0` – `14.0`).
- `iconSize`: Application icon dimensions in points (default: `16.0`, range: `14.0` – `24.0`).
- `launcherAction`: Launcher invoked by Start button (`.spotlight`, `.raycast`, or `.custom(path)`).
- `activeThemeId`: Active theme ID (`"modern-hybrid"`, `"retro-classic"`, `"windows-xp-luna"`, `"dark-minimal"`, or custom theme ID).
- `pinnedApps`: Array of `PinnedApp` shortcuts displayed in the Quick Launch bar.
- `dockAutohideDelay`: System Dock autohide hover reveal delay in seconds (default: `1000.0` = Permanently Hidden).

### Backward Compatibility Guarantee:
`Settings` decodes existing `v0.1.0` and `v0.1.1` preference payloads with zero loss:
```swift
self.pinnedApps = try container.decodeIfPresent([PinnedApp].self, forKey: .pinnedApps) ?? PinnedApp.defaultPinnedApps
self.activeThemeId = try container.decodeIfPresent(String.self, forKey: .activeThemeId) ?? ThemeDefinition.forStyle(self.themeStyle).id
```
If `pinnedApps` is absent, it automatically defaults to `Finder`, `Safari`, and `Terminal`.

---

## 3. Pinned Applications Model (`PinnedApp.swift`)

Quick Launch shortcuts are modeled as `PinnedApp`:
```swift
public struct PinnedApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let bundleIdentifier: String
    public let displayName: String
    public let customPath: String?
}
```

### Management APIs in `Settings`:
- `pinApp(bundleIdentifier:displayName:customPath:) -> Bool`: Appends application if not already pinned.
- `unpinApp(bundleIdentifier:) -> Bool`: Removes application by bundle identifier.
- `isPinned(bundleIdentifier:) -> Bool`: Checks pinning status.
- `movePinnedApp(fromIndex:toIndex:) -> Bool`: Reorders pinned applications safely.

---

## 4. User Custom Themes (`~/.config/taskbar/themes/`)

Users can define custom themes by placing `*.json` files into `~/.config/taskbar/themes/`.

### JSON Theme Schema:
```json
{
  "id": "dracula-dark",
  "displayName": "Dracula Dark",
  "isCustom": true,
  "palette": {
    "backgroundColor": { "red": 0.16, "green": 0.16, "blue": 0.21, "alpha": 0.95 },
    "topBorderColor": { "red": 0.38, "green": 0.38, "blue": 0.49, "alpha": 0.7 },
    "textNormal": { "red": 0.95, "green": 0.95, "blue": 0.95, "alpha": 1.0 },
    "textPressed": { "red": 0.75, "green": 0.75, "blue": 0.75, "alpha": 1.0 },
    "buttonNormal": { "red": 0.27, "green": 0.28, "blue": 0.35, "alpha": 0.7 },
    "buttonHover": { "red": 0.38, "green": 0.38, "blue": 0.49, "alpha": 0.8 },
    "buttonPressed": { "red": 0.19, "green": 0.20, "blue": 0.25, "alpha": 1.0 },
    "buttonBorderNormal": { "red": 0.38, "green": 0.38, "blue": 0.49, "alpha": 0.5 },
    "buttonBorderPressed": { "red": 0.74, "green": 0.47, "blue": 0.85, "alpha": 1.0 }
  },
  "metrics": {
    "barHeight": 30.0,
    "minButtonWidth": 80.0,
    "maxButtonWidth": 160.0,
    "buttonSpacing": 4.0,
    "buttonPadding": 4.0,
    "buttonCornerRadius": 4.0,
    "fontSize": 12.0,
    "iconSize": 16.0,
    "fontBold": false,
    "is3DBeveled": false
  },
  "materials": {
    "useTranslucency": true,
    "material": "hudWindow",
    "blendingMode": "behindWindow"
  }
}
```

### Loading & Live Reload:
1. Discovered automatically when Taskbar launches.
2. Selectable from the **Theme** menu in the Status Menu bar.
3. Reloadable on demand via **Theme $\rightarrow$ Reload Themes from Disk**.
4. Active theme can be exported to disk via **Theme $\rightarrow$ Export Current Theme as JSON...**.
