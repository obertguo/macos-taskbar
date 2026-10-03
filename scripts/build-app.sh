#!/usr/bin/env bash
set -euo pipefail

# Locate project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source build configuration
CONFIG_FILE="${PROJECT_ROOT}/config/build.env"
if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
else
    APP_NAME="Taskbar"
    BUNDLE_ID="com.obertguo.taskbar"
    APP_VERSION="0.1.0"
    INSTALL_DIR="$HOME/Applications"
    SIGN_IDENTITY="auto"
fi

INSTALL_FLAG=false
BUILD_CONFIG="release"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL_FLAG=true
            shift
            ;;
        --debug)
            BUILD_CONFIG="debug"
            shift
            ;;
        --help|-h)
            echo "Usage: ./scripts/build-app.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --install   Install to ${INSTALL_DIR} and replace existing copy"
            echo "  --debug     Build in debug configuration instead of release"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "==> Building ${APP_NAME} (${BUILD_CONFIG})..."
cd "${PROJECT_ROOT}"
swift build -c "${BUILD_CONFIG}" --product TaskbarApp

BIN_DIR="${PROJECT_ROOT}/.build/${BUILD_CONFIG}"
EXECUTABLE="${BIN_DIR}/TaskbarApp"

if [[ ! -f "${EXECUTABLE}" ]]; then
    echo "Error: Executable not found at ${EXECUTABLE}"
    exit 1
fi

APP_BUNDLE="${PROJECT_ROOT}/build/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Assembling ${APP_NAME}.app..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp "${EXECUTABLE}" "${MACOS_DIR}/${APP_NAME}App"
chmod +x "${MACOS_DIR}/${APP_NAME}App"

# Copy Info.plist
cp "${PROJECT_ROOT}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

# Code signing resolution
RESOLVED_IDENTITY="-"
if [[ "${SIGN_IDENTITY}" == "auto" || -z "${SIGN_IDENTITY}" ]]; then
    echo "==> Resolving code signing identity..."
    # Check for Apple Development certificate first
    DEV_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}' || true)
    if [[ -n "${DEV_IDENTITY}" ]]; then
        RESOLVED_IDENTITY="${DEV_IDENTITY}"
        echo "    Using Apple Development identity: ${RESOLVED_IDENTITY}"
    else
        # Any valid identity
        ANY_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -E '[0-9]+\) [0-9A-F]{40}' | head -n 1 | awk -F '"' '{print $2}' || true)
        if [[ -n "${ANY_IDENTITY}" ]]; then
            RESOLVED_IDENTITY="${ANY_IDENTITY}"
            echo "    Using codesigning identity: ${RESOLVED_IDENTITY}"
        else
            echo "    No Keychain identity found; falling back to ad-hoc signing (-)"
            RESOLVED_IDENTITY="-"
        fi
    fi
else
    RESOLVED_IDENTITY="${SIGN_IDENTITY}"
fi

echo "==> Signing ${APP_NAME}.app with [${RESOLVED_IDENTITY}]..."
codesign --force --options runtime --sign "${RESOLVED_IDENTITY}" "${APP_BUNDLE}"

echo "==> Build complete: ${APP_BUNDLE}"

if [[ "${INSTALL_FLAG}" == true ]]; then
    echo "==> Installing to ${INSTALL_DIR}..."
    mkdir -p "${INSTALL_DIR}"
    
    # Terminate running instance if any
    pkill -x "${APP_NAME}App" 2>/dev/null || true
    sleep 0.2

    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/${APP_NAME}.app"
    echo "==> Installed successfully to ${INSTALL_DIR}/${APP_NAME}.app"
fi
