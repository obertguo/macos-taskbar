#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

load_build_env

# Fail fast if any required setting is empty
REQUIRED_VARS=("APP_NAME" "BUNDLE_ID" "APP_VERSION" "BUILD_NUMBER" "MIN_MACOS_VERSION" "INSTALL_DIR")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: Required configuration variable '${var}' is missing or empty in ${CONFIG_FILE}!" >&2
        exit 1
    fi
done

SWIFT_CONFIG_DIR="${PROJECT_ROOT}/Sources/TaskbarCore/Config"
SWIFT_CONFIG_FILE="${SWIFT_CONFIG_DIR}/BuildConfiguration.swift"
INFO_PLIST_FILE="${PROJECT_ROOT}/Resources/Info.plist"

mkdir -p "${SWIFT_CONFIG_DIR}"
mkdir -p "${PROJECT_ROOT}/Resources"

# Generate Swift configuration file
cat <<EOF > "${SWIFT_CONFIG_FILE}"
// Auto-generated from config/build.env. Do not edit directly.
// To modify, edit config/build.env and run ./scripts/generate-config.sh

public struct BuildConfiguration: Sendable {
    public static let appName: String = "${APP_NAME}"
    public static let bundleID: String = "${BUNDLE_ID}"
    public static let appVersion: String = "${APP_VERSION}"
    public static let buildNumber: String = "${BUILD_NUMBER}"
    public static let minMacOSVersion: String = "${MIN_MACOS_VERSION}"
    public static let installDir: String = "${INSTALL_DIR}"
}
EOF

# Generate Info.plist synchronized with build.env
cat <<EOF > "${INFO_PLIST_FILE}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}App</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
EOF

log_success "Successfully synchronized config/build.env -> BuildConfiguration.swift & Info.plist"
