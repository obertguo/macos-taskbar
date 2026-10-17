# Build & Release Guide

This document describes how to compile, bundle, codesign, verify, test, install, package, and publish `Taskbar.app`.

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
- **Consequence:** macOS invalidates granted Accessibility permissions after each rebuild, requiring manual re-authorization in System Settings.

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
[`scripts/build-app.sh`](../scripts/build-app.sh) automatically searches Keychain for an Apple Development certificate. If located, it signs with it; otherwise, it cleanly falls back to ad-hoc signing (`-`).

---

## 3. Configuration & Single Source of Truth

Build and bundle metadata is centralized in [`config/build.env`](../config/build.env):
```bash
APP_NAME="Taskbar"
BUNDLE_ID="com.local.taskbar"
APP_VERSION="0.3.2"
BUILD_NUMBER="9"
MIN_MACOS_VERSION="14.0"
INSTALL_DIR="~/Applications"
SIGN_IDENTITY="auto"

# Test Harness & Benchmark Thresholds
TEST_MAX_RSS_MB="45.0"
TEST_MAX_CPU_PERCENT="2.0"
TEST_AX_AUTH_TIMEOUT_SECONDS="15"
TEST_FIXTURE_APP="TextEdit"
```

Running `./scripts/generate-config.sh` automatically synchronizes:
1. `Sources/TaskbarCore/Config/BuildConfiguration.swift`
2. `Resources/Info.plist`

---

## 4. Automated Build Pipeline

Compile and bundle the production release:
```bash
# Clean build, sign, and bundle Taskbar.app inside build/
./scripts/build-app.sh

# Build, sign, and install into ~/Applications/
./scripts/build-app.sh --install
```

---

## 5. Automated Verification & Testing

Before packaging any release, run the automated test harness:
```bash
# Run all unit, integration, edge-case, and stress test suites with memory benchmarking
./scripts/test-functional.sh --all
```

Requirements for release readiness:
- 100% test pass rate across all 32 test suites (236 tests total: 124 Core + 112 Integration).
- Resident memory $< 45\text{ MB}$ RSS.
- Idle CPU $\sim 0.0\%$.

---

## 6. Packaging & Distribution Artifacts

The packaging script [`scripts/package-release.sh`](../scripts/package-release.sh) automates the generation of release artifacts:

```bash
# Package current version into dist/
./scripts/package-release.sh

# Or bump version and package atomically:
./scripts/package-release.sh --patch  # e.g. 0.3.1 -> 0.3.2
./scripts/package-release.sh --minor  # e.g. 0.2.0 -> 0.3.0
```

### Generated Artifacts in `dist/`:
- `Taskbar-v<VERSION>.dmg`: Drag-and-drop macOS disk image with Applications folder shortcut.
- `Taskbar-v<VERSION>.zip`: Standalone compressed zip archive of `Taskbar.app`.
- `SHA256SUMS.txt`: Cryptographic checksums for release integrity verification.
