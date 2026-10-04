#!/usr/bin/env bash
set -euo pipefail

# Locate project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/config"
BUILD_CONFIG="${CONFIG_DIR}/build.env"
GITLAB_CONFIG="${CONFIG_DIR}/gitlab.env"
DIST_DIR="${PROJECT_ROOT}/dist"

# Show help message
show_help() {
    cat <<EOF
Usage: ./scripts/upload-release.sh [OPTIONS]

Uploads release packages (.dmg, .zip, and SHA256SUMS.txt) from dist/ to the
GitLab Generic Package Registry.

Options:
  --version <X.Y.Z>      Specify target version (default: from build.env)
  --dist-dir <DIR>       Directory containing release files (default: 'dist')
  --create-release       Also create/update a GitLab Release linking the uploaded assets
  --help, -h             Show this help message

Configuration:
  Settings are loaded from 'config/gitlab.env' (gitignored) or environment variables:
    GITLAB_PROJECT_ID    Numeric GitLab project ID (required)
    GITLAB_TOKEN         GitLab Access Token with 'api' scope (required)
    GITLAB_URL           GitLab instance URL (default: https://gitlab.com)
    GITLAB_PACKAGE_NAME  Package name in registry (default: lowercase app name)

To set up your credentials:
  cp config/gitlab.env.example config/gitlab.env
  # Edit config/gitlab.env with your Project ID and Token
EOF
}

# Handle --help / -h early
for arg in "$@"; do
    if [[ "${arg}" == "--help" || "${arg}" == "-h" ]]; then
        show_help
        exit 0
    fi
done

# Fail fast if build configuration is missing
if [[ ! -f "${BUILD_CONFIG}" ]]; then
    echo "Error: Required build configuration file '${BUILD_CONFIG}' is missing!" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "${BUILD_CONFIG}"

# Fail fast if GitLab configuration file is missing and env vars not exported
if [[ ! -f "${GITLAB_CONFIG}" ]]; then
    if [[ -z "${GITLAB_PROJECT_ID:-}" || -z "${GITLAB_TOKEN:-}" ]]; then
        echo "Error: Required GitLab configuration file '${GITLAB_CONFIG}' is missing!" >&2
        echo "" >&2
        echo "Please set up your credentials:" >&2
        echo "  cp config/gitlab.env.example config/gitlab.env" >&2
        echo "  # Edit config/gitlab.env with your Project ID and Token" >&2
        echo "" >&2
        echo "Alternatively, export GITLAB_PROJECT_ID and GITLAB_TOKEN in your environment." >&2
        exit 1
    fi
else
    # shellcheck source=/dev/null
    source "${GITLAB_CONFIG}"
fi

# Fail fast if any required GitLab setting is empty
REQUIRED_GITLAB_VARS=("GITLAB_PROJECT_ID" "GITLAB_TOKEN")
for var in "${REQUIRED_GITLAB_VARS[@]}"; do
    val="${!var:-}"
    if [[ -z "${val}" ]]; then
        echo "Error: Required configuration variable '${var}' is missing or empty!" >&2
        echo "Please provide '${var}' in config/gitlab.env or export it in your environment." >&2
        exit 1
    fi
done

# Fail fast if credentials are still set to example placeholders
if [[ "${GITLAB_PROJECT_ID}" == "12345678" || "${GITLAB_TOKEN}" == glpat-*xxxx* ]]; then
    echo "Error: config/gitlab.env contains unedited placeholder credentials!" >&2
    echo "Please update GITLAB_PROJECT_ID and GITLAB_TOKEN with your real GitLab project details." >&2
    exit 1
fi

# Defaults
GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
GITLAB_PACKAGE_NAME="${GITLAB_PACKAGE_NAME:-$(echo "${APP_NAME:-taskbar}" | tr '[:upper:]' '[:lower:]')}"
VERSION="${APP_VERSION}"
CREATE_RELEASE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            if [[ $# -lt 2 ]]; then
                echo "Error: --version requires an argument (X.Y.Z)" >&2
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        --dist-dir)
            if [[ $# -lt 2 ]]; then
                echo "Error: --dist-dir requires a directory path" >&2
                exit 1
            fi
            DIST_DIR="$2"
            shift 2
            ;;
        --create-release)
            CREATE_RELEASE=true
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

# Validate artifacts exist in dist directory
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
ZIP_NAME="${APP_NAME}-v${VERSION}.zip"
CHECKSUM_NAME="SHA256SUMS.txt"

DMG_FILE="${DIST_DIR}/${DMG_NAME}"
ZIP_FILE="${DIST_DIR}/${ZIP_NAME}"
CHECKSUM_FILE="${DIST_DIR}/${CHECKSUM_NAME}"

MISSING_FILES=()
for f in "${DMG_FILE}" "${ZIP_FILE}" "${CHECKSUM_FILE}"; do
    if [[ ! -f "$f" ]]; then
        MISSING_FILES+=("$(basename "$f")")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    echo "Error: The following release artifacts for v${VERSION} are missing in '${DIST_DIR}':" >&2
    for mf in "${MISSING_FILES[@]}"; do
        echo "  - ${mf}" >&2
    done
    echo "" >&2
    echo "Please run the packaging script first:" >&2
    echo "  ./scripts/package-release.sh" >&2
    exit 1
fi

# Endpoint for Generic Package Registry
API_BASE="${GITLAB_URL%/}/api/v4/projects/${GITLAB_PROJECT_ID}"
PACKAGE_ENDPOINT="${API_BASE}/packages/generic/${GITLAB_PACKAGE_NAME}/${VERSION}"

echo "==> Preparing to upload release artifacts for ${APP_NAME} v${VERSION}..."
echo "    Registry endpoint: ${PACKAGE_ENDPOINT}"
echo ""

upload_file() {
    local file_path="$1"
    local file_name="$2"
    local target_url="${PACKAGE_ENDPOINT}/${file_name}"
    local tmp_resp
    tmp_resp=$(mktemp)

    echo -n "==> Uploading ${file_name}... "
    local http_code
    http_code=$(curl -sS -w "%{http_code}" -o "${tmp_resp}" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        --upload-file "${file_path}" \
        "${target_url}" || true)

    if [[ "${http_code}" =~ ^(200|201)$ ]]; then
        echo "Done (HTTP ${http_code})"
        rm -f "${tmp_resp}"
    else
        echo "FAILED (HTTP ${http_code})" >&2
        echo "Response from GitLab:" >&2
        cat "${tmp_resp}" >&2
        echo "" >&2
        rm -f "${tmp_resp}"
        exit 1
    fi
}

# Upload artifacts
upload_file "${DMG_FILE}" "${DMG_NAME}"
upload_file "${ZIP_FILE}" "${ZIP_NAME}"
upload_file "${CHECKSUM_FILE}" "${CHECKSUM_NAME}"

DMG_DOWNLOAD_URL="${PACKAGE_ENDPOINT}/${DMG_NAME}"
ZIP_DOWNLOAD_URL="${PACKAGE_ENDPOINT}/${ZIP_NAME}"
CHECKSUM_DOWNLOAD_URL="${PACKAGE_ENDPOINT}/${CHECKSUM_NAME}"

# Optionally create or update GitLab Release
if [[ "${CREATE_RELEASE}" == true ]]; then
    echo ""
    echo "==> Creating/linking GitLab Release for tag v${VERSION}..."
    RELEASE_ENDPOINT="${API_BASE}/releases"
    
    # Check for release notes in CHANGELOG.md if available
    RELEASE_DESC="Release v${VERSION} of ${APP_NAME}."
    if [[ -f "${PROJECT_ROOT}/CHANGELOG.md" ]]; then
        RELEASE_DESC="See CHANGELOG.md for details."
    fi

    RELEASE_PAYLOAD=$(cat <<EOF
{
  "name": "${APP_NAME} v${VERSION}",
  "tag_name": "v${VERSION}",
  "description": "${RELEASE_DESC}",
  "assets": {
    "links": [
      {
        "name": "${DMG_NAME}",
        "url": "${DMG_DOWNLOAD_URL}",
        "link_type": "package"
      },
      {
        "name": "${ZIP_NAME}",
        "url": "${ZIP_DOWNLOAD_URL}",
        "link_type": "package"
      },
      {
        "name": "${CHECKSUM_NAME}",
        "url": "${CHECKSUM_DOWNLOAD_URL}",
        "link_type": "other"
      }
    ]
  }
}
EOF
)

    REL_RESP=$(mktemp)
    REL_CODE=$(curl -sS -w "%{http_code}" -o "${REL_RESP}" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        --header "Content-Type: application/json" \
        --request POST \
        --data "${RELEASE_PAYLOAD}" \
        "${RELEASE_ENDPOINT}" || true)

    if [[ "${REL_CODE}" =~ ^(200|201)$ ]]; then
        echo "==> Release v${VERSION} created successfully on GitLab!"
    elif [[ "${REL_CODE}" == "409" ]]; then
        echo "==> Note: Release v${VERSION} already exists on GitLab (HTTP 409). Assets are available in the Package Registry."
    else
        echo "==> Warning: Could not create release automatically (HTTP ${REL_CODE}):"
        cat "${REL_RESP}"
    fi
    rm -f "${REL_RESP}"
fi

echo ""
echo "============================================================"
echo "  Upload complete for ${APP_NAME} v${VERSION}!"
echo "============================================================"
echo "Permanent Package Registry URLs:"
echo "  - DMG: ${DMG_DOWNLOAD_URL}"
echo "  - ZIP: ${ZIP_DOWNLOAD_URL}"
echo "  - Checksums: ${CHECKSUM_DOWNLOAD_URL}"
echo ""
echo "GitLab Package Registry:"
echo "  ${GITLAB_URL%/}/projects/${GITLAB_PROJECT_ID}/packages"
echo "============================================================"
