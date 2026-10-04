#!/usr/bin/env bash
# ==============================================================================
# scripts/package-release.sh
#
# Builds, tests, and packages Taskbar for distribution.
# Assembles standalone .dmg (Disk Image) and .zip archives in dist/ with SHA256
# checksums. Supports automated semver bumping (patch, minor, major) with atomic
# rollback if pre-flight tests or compilation fail.
# ==============================================================================
set -euo pipefail

# Locate project directories and load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

load_build_env

CONFIG_FILE="${BUILD_CONFIG_FILE}"
DIST_DIR="${PROJECT_ROOT}/dist"

BUMP_TYPE="none"
SKIP_TESTS=false

# Print usage instructions
show_help() {
    cat <<EOF
Usage: ./scripts/package-release.sh [OPTIONS]

Builds, tests, and packages Taskbar for distribution into .dmg and .zip archives.

Options:
  --bump <major|minor|patch>   Bump APP_VERSION in build.env before packaging
  --patch                      Shortcut for --bump patch
  --minor                      Shortcut for --bump minor
  --major                      Shortcut for --bump major
  --skip-tests                 Skip running 'swift test' prior to packaging
  --help, -h                   Show this help message

Examples:
  ./scripts/package-release.sh                 # Package current APP_VERSION
  ./scripts/package-release.sh --patch         # Bump patch (e.g. 0.1.0 -> 0.1.1) and package
  ./scripts/package-release.sh --minor         # Bump minor (e.g. 0.1.0 -> 0.2.0) and package
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bump)
            if [[ $# -lt 2 ]]; then
                echo "Error: --bump requires an argument (major, minor, or patch)" >&2
                exit 1
            fi
            BUMP_TYPE="$2"
            shift 2
            ;;
        --patch)
            BUMP_TYPE="patch"
            shift
            ;;
        --minor)
            BUMP_TYPE="minor"
            shift
            ;;
        --major)
            BUMP_TYPE="major"
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate bump type
if [[ "${BUMP_TYPE}" != "none" && "${BUMP_TYPE}" != "patch" && "${BUMP_TYPE}" != "minor" && "${BUMP_TYPE}" != "major" ]]; then
    echo "Error: Invalid bump type '${BUMP_TYPE}'. Must be 'major', 'minor', or 'patch'." >&2
    exit 1
fi

# Source current configuration
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Validate current semver structure
if [[ ! "${APP_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: Current APP_VERSION '${APP_VERSION}' in ${CONFIG_FILE} is not valid semver (X.Y.Z)!" >&2
    exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"
CURRENT_BUILD="${BUILD_NUMBER:-1}"

TARGET_VERSION="${APP_VERSION}"
TARGET_BUILD="${CURRENT_BUILD}"

BACKUP_FILE="${CONFIG_FILE}.backup.$$"

# Rollback handler in case of failure during bumping/building
cleanup_on_failure() {
    local exit_code=$?
    echo "" >&2
    echo "==> Build/packaging failed with exit code ${exit_code}!" >&2
    if [[ -f "${BACKUP_FILE}" ]]; then
        echo "==> Rolling back ${CONFIG_FILE}..." >&2
        cp "${BACKUP_FILE}" "${CONFIG_FILE}"
        rm -f "${BACKUP_FILE}"
        "${SCRIPT_DIR}/generate-config.sh" >/dev/null 2>&1 || true
    fi
    exit "${exit_code}"
}

# Install failure trap
trap cleanup_on_failure ERR INT TERM

if [[ "${BUMP_TYPE}" != "none" ]]; then
    case "${BUMP_TYPE}" in
        patch)
            PATCH=$((PATCH + 1))
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
    esac
    TARGET_VERSION="${MAJOR}.${MINOR}.${PATCH}"
    TARGET_BUILD=$((CURRENT_BUILD + 1))
    
    echo "==> Bumping version: ${APP_VERSION} -> ${TARGET_VERSION} (Build ${CURRENT_BUILD} -> ${TARGET_BUILD})"
    
    # Back up build.env before modifying
    cp "${CONFIG_FILE}" "${BACKUP_FILE}"
    
    # Update APP_VERSION and BUILD_NUMBER in build.env preserving comments/format
    awk -v v="${TARGET_VERSION}" -v b="${TARGET_BUILD}" '
        /^APP_VERSION=/ { print "APP_VERSION=\"" v "\""; next }
        /^BUILD_NUMBER=/ { print "BUILD_NUMBER=\"" b "\""; next }
        { print }
    ' "${BACKUP_FILE}" > "${CONFIG_FILE}"
    
    # Synchronize Swift and Info.plist configurations
    "${SCRIPT_DIR}/generate-config.sh"
fi

echo "==> Packaging release for ${APP_NAME} v${TARGET_VERSION}..."

# 1. Run automated tests (Fail-fast verification)
if [[ "${SKIP_TESTS}" == false ]]; then
    echo "==> Running automated test suite via test-functional.sh..."
    "${SCRIPT_DIR}/test-functional.sh" --all
else
    echo "==> Skipping automated tests (--skip-tests)"
fi

# 2. Build release application bundle
echo "==> Compiling release binary and assembling .app bundle..."
"${SCRIPT_DIR}/build-app.sh"

APP_BUNDLE="${PROJECT_ROOT}/build/${APP_NAME}.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Error: Application bundle not found at ${APP_BUNDLE}" >&2
    exit 1
fi

# 3. Prepare clean dist output directory
mkdir -p "${DIST_DIR}"
DMG_NAME="${APP_NAME}-v${TARGET_VERSION}.dmg"
ZIP_NAME="${APP_NAME}-v${TARGET_VERSION}.zip"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"

rm -f "${DMG_PATH}" "${ZIP_PATH}"

# 4. Assemble Disk Image (DMG)
echo "==> Building Disk Image (${DMG_NAME})..."
DMG_STAGE="${PROJECT_ROOT}/build/dmg-staging"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"

cp -R "${APP_BUNDLE}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${DMG_STAGE}"

# 5. Assemble ZIP Archive
echo "==> Building ZIP archive (${ZIP_NAME})..."
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# 6. Generate Checksums
echo "==> Generating SHA256 checksums..."
(
    cd "${DIST_DIR}"
    shasum -a 256 "${DMG_NAME}" "${ZIP_NAME}" > "SHA256SUMS.txt"
)

# 7. Commit version bump on success
if [[ -f "${BACKUP_FILE}" ]]; then
    rm -f "${BACKUP_FILE}"
fi
trap - ERR INT TERM

echo ""
echo "============================================================"
echo "  Release packaging complete for ${APP_NAME} v${TARGET_VERSION}!"
echo "============================================================"
echo "Artifacts generated in dist/:"
echo "  - ${DIST_DIR}/${DMG_NAME}"
echo "  - ${DIST_DIR}/${ZIP_NAME}"
echo "  - ${DIST_DIR}/SHA256SUMS.txt"
echo ""
echo "Checksums:"
cat "${DIST_DIR}/SHA256SUMS.txt"
echo ""
echo "Next Steps to publish on GitLab:"
echo "  1. Commit version bump (if bumped):"
echo "     git add config/build.env Sources/TaskbarCore/Config/BuildConfiguration.swift Resources/Info.plist"
echo "     git commit -m \"chore(release): bump version to v${TARGET_VERSION}\""
echo "  2. Create and push Git tag:"
echo "     git tag -a \"v${TARGET_VERSION}\" -m \"Release v${TARGET_VERSION}\""
echo "     git push origin main --tags"
echo "  3. Upload packages to GitLab & publish release:"
echo "     ./scripts/upload-release.sh --create-release"
echo "     (Requires config/gitlab.env; see config/gitlab.env.example)"
echo "     Alternatively, upload manually in GitLab Web UI (Deploy -> Releases)."
echo "============================================================"
