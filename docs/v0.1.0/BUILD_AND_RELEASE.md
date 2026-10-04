# Build & Release Guide (v0.1.0)

This document describes how to compile, bundle, codesign, verify, install, and uninstall `Taskbar.app`.

---

## 1. Prerequisites

- **Operating System:** macOS 14.0 (Sonoma) or newer.
- **Toolchain:** Swift 5.9+ and Xcode 15+ or Xcode Command Line Tools.
  Verify your installed versions:
  ```bash
  xcode-select -p
  swift --version
  ```

---

## 2. Code Signing Architecture

macOS Transparency, Consent, and Control (TCC) enforces that Accessibility permissions are tied to the cryptographic code-signing identity of the running executable:

### Ad-Hoc Signing (`codesign -s -`)
- Produces a unique designated requirement hash on every rebuild.
- **Consequence:** macOS invalidates granted Accessibility permissions after each rebuild, requiring manual toggling in System Settings.

### Apple Development Certificate (Recommended)
- Binds the binary to a persistent cryptographic identity in your macOS Keychain.
- **Consequence:** Accessibility permissions persist across rebuilds and app updates.
- **Setup:**
  1. Open Xcode $\rightarrow$ **Settings** $\rightarrow$ **Accounts**.
  2. Sign in with your Apple ID (a free personal Apple ID works).
  3. Select your account $\rightarrow$ Click **Manage Certificates...** $\rightarrow$ Click **+** $\rightarrow$ Choose **Apple Development**.
  4. Verify the certificate in Terminal:
     ```bash
     security find-identity -v -p codesigning
     ```

### Build Script Auto-Detection
[`scripts/build-app.sh`](file:///scripts/build-app.sh) automatically searches Keychain for an Apple Development certificate. If located, it signs with it; otherwise, it cleanly falls back to ad-hoc signing (`-`).

---

## 3. Configuration & Code Generation

Build and bundle metadata is centralized in [`config/build.env`](file:///config/build.env):
```bash
APP_NAME="Taskbar"
BUNDLE_ID="com.local.taskbar"
APP_VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS_VERSION="14.0"
INSTALL_DIR="~/Applications"
SIGN_IDENTITY="auto"
```

During build execution, [`scripts/generate-config.sh`](file:///scripts/generate-config.sh) synchronizes these variables into:
1. [`Sources/TaskbarCore/Config/BuildConfiguration.swift`](file:///Sources/TaskbarCore/Config/BuildConfiguration.swift) (typed Swift struct)
2. `Resources/Info.plist` (app bundle metadata with `LSUIElement = true`)

---

## 4. Building and Packaging

### Standard Release Build & Install
Compiles in release mode, generates configuration, creates the `.app` bundle, signs the binary, and installs it to `~/Applications/Taskbar.app`:
```bash
./scripts/build-app.sh --install
```

### Debug Build
Compiles with debug symbols for development:
```bash
./scripts/build-app.sh --debug
```

### Build Without Installing
Assembles and signs the application bundle in `build/Taskbar.app` without touching `~/Applications`:
```bash
./scripts/build-app.sh
```

### Bundle Layout
The script produces standard macOS application bundle layout:
```
build/Taskbar.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── TaskbarApp
    └── Resources/
```

---

## 5. Verification & Signature Inspection

After compilation, verify the signature and bundle integrity:

```bash
# Verify deep strict code signature
codesign --verify --deep --strict ~/Applications/Taskbar.app

# Inspect signing authority and designated requirement
codesign -dvv ~/Applications/Taskbar.app

# Verify executable architecture (arm64 / x86_64)
file ~/Applications/Taskbar.app/Contents/MacOS/TaskbarApp
```

---

## 6. First-Time Setup & Accessibility Permission

1. Launch `Taskbar.app`:
   ```bash
   open ~/Applications/Taskbar.app
   ```
2. On first launch, the app detects missing Accessibility permissions and presents the system prompt.
3. Open **System Settings** $\rightarrow$ **Privacy & Security** $\rightarrow$ **Accessibility**.
4. Enable the toggle for **Taskbar**.
5. Once enabled, taskbars immediately initialize on all connected monitors without needing an app restart.

### Resetting Permissions (Troubleshooting)
If testing first-run onboarding or fixing stale ad-hoc signatures, reset TCC permissions:
```bash
tccutil reset Accessibility com.local.taskbar
```

---

## 7. Clean Uninstallation & Removal

Before deleting the application, ensure the system Dock is restored to standard visibility:

1. Click the Taskbar status icon in the menu bar $\rightarrow$ select **Restore System Dock Now**, or run:
   ```bash
   ./scripts/restore-dock.sh
   ```
2. Quit Taskbar:
   ```bash
   pkill -x TaskbarApp
   ```
3. Remove the installed application bundle:
   ```bash
   rm -rf ~/Applications/Taskbar.app
   ```
4. (Optional) Clear persisted preferences:
   ```bash
   defaults delete com.local.taskbar
   ```

---

## 8. Packaging & Distributing Releases (`scripts/package-release.sh`)

To package standalone `.dmg` and `.zip` distribution bundles with checksums, use the automated release script:

### Packaging the Current Version
```bash
./scripts/package-release.sh
```

### Bumping Version and Packaging
The script supports semantic version increments (`major`, `minor`, `patch`). When a bump is specified, `config/build.env` serves as the single source of truth and is permanently updated upon a successful build:

```bash
# Bump patch: e.g. 0.1.0 -> 0.1.1 (increments BUILD_NUMBER)
./scripts/package-release.sh --patch

# Bump minor: e.g. 0.1.0 -> 0.2.0
./scripts/package-release.sh --minor

# Bump major: e.g. 0.1.0 -> 1.0.0
./scripts/package-release.sh --major
```

### Safety & Fail-Fast Guarantees
- **Automated Pre-Flight Verification:** Runs `swift test` prior to packaging; any test failure immediately halts the release process.
- **Atomic Rollback:** If tests, compilation, or disk image assembly fail at any point, `config/build.env` is automatically restored to its original state.
- **Artifacts Output:** Generated archives and checksums are placed into `dist/`:
  - `dist/Taskbar-v<VERSION>.dmg` (drag-and-drop disk image)
  - `dist/Taskbar-v<VERSION>.zip` (compressed application bundle)
  - `dist/SHA256SUMS.txt` (SHA256 checksums)

### Publishing on GitLab
1. Commit the updated version in `config/build.env` (and synchronized generated files):
   ```bash
   git add config/build.env Sources/TaskbarCore/Config/BuildConfiguration.swift Resources/Info.plist
   git commit -m "chore(release): bump version to v<VERSION>"
   ```
2. Create and push the Git tag:
   ```bash
   git tag -a "v<VERSION>" -m "Release v<VERSION>"
   git push origin main --tags
   ```
3. Navigate to GitLab $\rightarrow$ **Deploy** $\rightarrow$ **Releases** $\rightarrow$ **New release**:
   - Select tag `v<VERSION>`.
   - Paste release notes from `CHANGELOG.md`.
   - Attach `Taskbar-v<VERSION>.dmg` and `Taskbar-v<VERSION>.zip` from `dist/` as release assets.
