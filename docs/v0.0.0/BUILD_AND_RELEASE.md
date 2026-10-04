# Build & Release Guide

This document describes how to compile, bundle, codesign, and install `Taskbar.app`.

---

## 1. Prerequisites

- **macOS:** 14.0 (Sonoma) or newer.
- **Developer Tools:** Full Xcode (recommended for Apple Development signing certificates and Instruments) or Xcode Command Line Tools.
  Verify with:
  ```bash
  xcode-select -p
  swift --version
  ```

---

## 2. Code Signing Architecture

macOS Transparency, Consent, and Control (TCC) ties user-granted Accessibility permissions directly to the cryptographic code-signing identity of the binary:
- **Ad-Hoc Signing (`codesign -s -`):** Produces a new designated requirement on every recompile. macOS will revoke or invalidate Accessibility permissions each time the app is rebuilt.
- **Apple Development Certificate (Recommended):**
  1. Open Xcode $\rightarrow$ **Settings** $\rightarrow$ **Accounts**.
  2. Sign in with your Apple ID (free personal account is sufficient).
  3. Click **Manage Certificates...** $\rightarrow$ Click **+** $\rightarrow$ Select **Apple Development**.
  4. Verify the certificate in Terminal:
     ```bash
     security find-identity -v -p codesigning
     ```
- **Build Script Auto-Detection:**
  `scripts/build-app.sh` automatically searches Keychain for an Apple Development certificate. If found, it uses it; otherwise, it signs with the best available identity or falls back to ad-hoc.

---

## 3. Building and Packaging

### Standard Release Build & Install
To build the release binary, assemble the `.app` bundle, sign it, and install it to `~/Applications/Taskbar.app`:

```bash
./scripts/build-app.sh --install
```

### Debug Build
To build in debug mode for development:
```bash
./scripts/build-app.sh --debug
```

### Manual Build Steps
Under the hood, `scripts/build-app.sh` performs:
1. `swift build -c release --product TaskbarApp`
2. Creates the bundle directory layout:
   ```
   build/Taskbar.app/
   └── Contents/
       ├── Info.plist
       ├── MacOS/
       │   └── TaskbarApp
       └── Resources/
   ```
3. Copies `Resources/Info.plist` into `Contents/Info.plist`.
4. Executes:
   ```bash
   codesign --force --options runtime --sign "<IDENTITY>" build/Taskbar.app
   ```
5. Verifies signature:
   ```bash
   codesign --verify --deep --strict build/Taskbar.app
   ```

---

## 4. First-Time Setup & Accessibility Permission

1. Launch the app from `~/Applications/Taskbar.app` or via terminal:
   ```bash
   open ~/Applications/Taskbar.app
   ```
2. When prompted, open **System Settings** $\rightarrow$ **Privacy & Security** $\rightarrow$ **Accessibility**.
3. Toggle **Taskbar** to **ON**.
4. The taskbars will immediately populate on all attached displays without requiring an application restart.
