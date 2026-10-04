#!/usr/bin/env bash
# scripts/common.sh
# Shared utilities, logging helpers, configuration loaders, and system checks
# used across Taskbar build, test, and release automation scripts.

# Include guard
if [[ -n "${_TASKBAR_COMMON_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_TASKBAR_COMMON_SH_LOADED=1

# ANSI Color and Style Codes
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

# Base Directory Resolution
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${COMMON_DIR}/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/config"
BUILD_CONFIG_FILE="${CONFIG_DIR}/build.env"

# ==============================================================================
# Logging Helpers
# ==============================================================================

log_info() {
    echo -e "${CYAN}==>${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}Error:${NC} $*" >&2
}

log_header() {
    local title="$1"
    echo -e "${BOLD}${CYAN}======================================================${NC}"
    echo -e "${BOLD}${CYAN}   ${title}${NC}"
    echo -e "${BOLD}${CYAN}======================================================${NC}"
}

# ==============================================================================
# Configuration Loading
# ==============================================================================

# Loads and validates config/build.env, setting standard defaults for optional keys.
load_build_env() {
    if [[ ! -f "${BUILD_CONFIG_FILE}" ]]; then
        log_error "Required configuration file '${BUILD_CONFIG_FILE}' is missing!"
        echo "Please provide config/build.env before running this script." >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source "${BUILD_CONFIG_FILE}"

    # Default fallbacks
    APP_NAME="${APP_NAME:-Taskbar}"
    BUNDLE_ID="${BUNDLE_ID:-com.local.taskbar}"
    APP_VERSION="${APP_VERSION:-0.1.0}"
    BUILD_NUMBER="${BUILD_NUMBER:-1}"
    MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
    INSTALL_DIR="${INSTALL_DIR:-~/Applications}"
    SIGN_IDENTITY="${SIGN_IDENTITY:-auto}"

    # Test and benchmark defaults
    TEST_MAX_RSS_MB="${TEST_MAX_RSS_MB:-45.0}"
    TEST_MAX_CPU_PERCENT="${TEST_MAX_CPU_PERCENT:-2.0}"
    TEST_AX_AUTH_TIMEOUT_SECONDS="${TEST_AX_AUTH_TIMEOUT_SECONDS:-15}"
    TEST_FIXTURE_APP="${TEST_FIXTURE_APP:-TextEdit}"
}

# ==============================================================================
# System & Pre-flight Checks
# ==============================================================================

# Verifies that current macOS version satisfies the minimum requirement.
check_min_macos_version() {
    local min_ver="${1:-${MIN_MACOS_VERSION:-14.0}}"
    local current_ver
    current_ver=$(sw_vers -productVersion)
    local current_major
    current_major=$(echo "${current_ver}" | cut -d. -f1)
    local min_major
    min_major=$(echo "${min_ver}" | cut -d. -f1)

    if [[ "${current_major}" -lt "${min_major}" ]]; then
        log_error "${APP_NAME:-Taskbar} requires macOS ${min_ver} or later (detected macOS ${current_ver})."
        exit 1
    fi
    log_success "OS check passed: macOS ${current_ver} (required: >= ${min_ver})"
}

# Finds running process ID for an application name (e.g. Taskbar or TaskbarApp).
find_app_pid() {
    local name="${1:-${APP_NAME:-Taskbar}}"
    pgrep -x "${name}" || pgrep -x "${name}App" || echo ""
}

# Gets resident memory in KB for a PID (returns 0 if empty/dead).
get_process_rss_kb() {
    local pid="${1:-}"
    if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
        ps -o rss= -p "${pid}" | tr -d ' '
    else
        echo "0"
    fi
}

# Gets CPU percentage for a PID (returns 0.0 if empty/dead).
get_process_cpu_percent() {
    local pid="${1:-}"
    if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
        ps -o %cpu= -p "${pid}" | tr -d ' '
    else
        echo "0.0"
    fi
}
