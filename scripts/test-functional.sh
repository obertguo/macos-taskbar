#!/usr/bin/env bash
# scripts/test-functional.sh
# Automated functional, edge-case, and stress testing harness for Taskbar.
# Configuration and thresholds are sourced dynamically from config/build.env.
set -euo pipefail

# ANSI color codes
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
NC="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Fail fast if configuration file is missing
CONFIG_FILE="${PROJECT_ROOT}/config/build.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo -e "${RED}Error: Required configuration file '${CONFIG_FILE}' is missing!${NC}" >&2
    echo "Please provide config/build.env before running test-functional.sh." >&2
    exit 1
fi

# Source single-source-of-truth configuration
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Configuration variables with fallbacks
APP_NAME="${APP_NAME:-Taskbar}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
TEST_MAX_RSS_MB="${TEST_MAX_RSS_MB:-45.0}"
TEST_MAX_CPU_PERCENT="${TEST_MAX_CPU_PERCENT:-2.0}"
TEST_AX_AUTH_TIMEOUT_SECONDS="${TEST_AX_AUTH_TIMEOUT_SECONDS:-15}"
TEST_FIXTURE_APP="${TEST_FIXTURE_APP:-TextEdit}"

# Default test mode
MODE="all"

usage() {
    echo -e "${BOLD}Usage:${NC} ./scripts/test-functional.sh [MODE]"
    echo ""
    echo -e "${BOLD}Test Modes:${NC}"
    echo "  --quick        Run fast window lifecycle tests (TC-FUNC-*, ~15s)"
    echo "  --edge-cases   Run boundary & corner case suite (TC-EDGE-*, ~5s)"
    echo "  --stress       Run high-density window stress & memory benchmark (TC-STRESS-*, TC-PERF-*)"
    echo "  --all          Run complete test suite (Unit + Functional + Edge + Stress, default)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo -e "${BOLD}Configuration (from config/build.env):${NC}"
    echo "  - Application:       ${APP_NAME}"
    echo "  - Min macOS Version: ${MIN_MACOS_VERSION}"
    echo "  - RSS Threshold:     ${TEST_MAX_RSS_MB} MB"
    echo "  - CPU Threshold:     ${TEST_MAX_CPU_PERCENT}%"
    echo "  - AX Auth Timeout:   ${TEST_AX_AUTH_TIMEOUT_SECONDS}s"
    echo "  - Fixture App:       ${TEST_FIXTURE_APP}"
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)
            MODE="quick"
            shift
            ;;
        --edge-cases)
            MODE="edge-cases"
            shift
            ;;
        --stress)
            MODE="stress"
            shift
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

echo -e "${BOLD}${CYAN}======================================================${NC}"
echo -e "${BOLD}${CYAN}   ${APP_NAME} Automated Test Runner (Mode: ${MODE})       ${NC}"
echo -e "${BOLD}${CYAN}======================================================${NC}"

# 1. Pre-flight Checks: macOS Version against MIN_MACOS_VERSION from build.env
CURRENT_OS_VERSION=$(sw_vers -productVersion)
CURRENT_MAJOR=$(echo "${CURRENT_OS_VERSION}" | cut -d. -f1)
MIN_MAJOR=$(echo "${MIN_MACOS_VERSION}" | cut -d. -f1)

if [[ "${CURRENT_MAJOR}" -lt "${MIN_MAJOR}" ]]; then
    echo -e "${RED}Error: ${APP_NAME} requires macOS ${MIN_MACOS_VERSION} or later (detected macOS ${CURRENT_OS_VERSION}).${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✓ OS check passed:${NC} macOS ${CURRENT_OS_VERSION} (required: >= ${MIN_MACOS_VERSION})"

# 2. Pre-flight Checks: Accessibility Permissions
check_accessibility() {
    echo -n "Checking Accessibility permissions... "
    local is_trusted
    is_trusted=$(osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || echo "false")
    
    if [[ "${is_trusted}" != "true" ]]; then
        echo -e "${YELLOW}NOT GRANTED${NC}"
        echo -e "${YELLOW}==> Prompting for Accessibility permission in System Settings...${NC}"
        
        # Trigger macOS System Settings prompt
        swift -e '
        import ApplicationServices
        import CoreFoundation
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        ' 2>/dev/null || true
        
        echo -n "Waiting for authorization (up to ${TEST_AX_AUTH_TIMEOUT_SECONDS}s)..."
        local waited=0
        while [[ $waited -lt "${TEST_AX_AUTH_TIMEOUT_SECONDS}" ]]; do
            sleep 1
            waited=$((waited + 1))
            is_trusted=$(osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || echo "false")
            if [[ "${is_trusted}" == "true" ]]; then
                echo -e "\n${GREEN}✓ Accessibility permission granted!${NC}"
                return 0
            fi
            echo -n "."
        done
        echo ""
        echo -e "${RED}Error: Accessibility permissions not granted within ${TEST_AX_AUTH_TIMEOUT_SECONDS} seconds.${NC}" >&2
        echo -e "${RED}Please grant permissions in System Settings > Privacy & Security > Accessibility.${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}✓ GRANTED${NC}"
}

# 3. Cleanup Dangling Fixtures
cleanup_fixtures() {
    osascript -e "if application \"${TEST_FIXTURE_APP}\" is running then tell application \"${TEST_FIXTURE_APP}\" to quit saving no" 2>/dev/null || true
}

# Run pre-flight checks
if [[ "${MODE}" == "quick" || "${MODE}" == "all" ]]; then
    check_accessibility
fi
cleanup_fixtures

# Trap exit to guarantee fixture cleanup
trap cleanup_fixtures EXIT

cd "${PROJECT_ROOT}"

# 4. Measure Baseline Memory
get_taskbar_rss_kb() {
    local pid
    pid=$(pgrep -x "${APP_NAME}" || pgrep -x "${APP_NAME}App" || echo "")
    if [[ -n "${pid}" ]]; then
        ps -o rss= -p "${pid}" | tr -d ' '
    else
        echo "0"
    fi
}

BASELINE_RSS=$(get_taskbar_rss_kb)

# 5. Run Test Target
START_TIME=$(date +%s)
FAILED=0

case "${MODE}" in
    quick)
        echo -e "\n${BOLD}==> Running Quick Window Lifecycle Suite (TC-FUNC-*)...${NC}"
        swift test --filter WindowLifecycleIntegrationTests || FAILED=1
        ;;
    edge-cases)
        echo -e "\n${BOLD}==> Running Edge Cases Suite (TC-EDGE-*)...${NC}"
        swift test --filter EdgeCasesIntegrationTests || FAILED=1
        ;;
    stress)
        echo -e "\n${BOLD}==> Running Stress & Capacity Suite (TC-STRESS-*, TC-PERF-*)...${NC}"
        swift test --filter StressIntegrationTests || FAILED=1
        ;;
    all)
        echo -e "\n${BOLD}==> Running Core Unit Tests (TC-UNIT-*)...${NC}"
        swift test --filter TaskbarCoreTests || FAILED=1
        
        echo -e "\n${BOLD}==> Running Edge Cases Suite (TC-EDGE-*)...${NC}"
        swift test --filter EdgeCasesIntegrationTests || FAILED=1
        
        echo -e "\n${BOLD}==> Running Stress Suite (TC-STRESS-*)...${NC}"
        swift test --filter StressIntegrationTests || FAILED=1
        
        echo -e "\n${BOLD}==> Running Functional Lifecycle Suite (TC-FUNC-*)...${NC}"
        swift test --filter WindowLifecycleIntegrationTests || FAILED=1
        ;;
esac

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 6. Memory & Performance Verification
POST_RSS=$(get_taskbar_rss_kb)

echo -e "\n${BOLD}${CYAN}======================================================${NC}"
echo -e "${BOLD}${CYAN}   Test Execution Summary                            ${NC}"
echo -e "${BOLD}${CYAN}======================================================${NC}"
echo -e "Mode:          ${BOLD}${MODE}${NC}"
echo -e "Duration:      ${DURATION}s"

if [[ "${BASELINE_RSS}" != "0" ]]; then
    BASELINE_MB=$(echo "scale=2; ${BASELINE_RSS} / 1024" | bc)
    POST_MB=$(echo "scale=2; ${POST_RSS} / 1024" | bc)
    echo -e "${APP_NAME} RSS:   ${BASELINE_MB} MB (Baseline) -> ${POST_MB} MB (Post-test)"
    
    # Assert Peak RSS < TEST_MAX_RSS_MB
    if (( $(echo "${POST_MB} > ${TEST_MAX_RSS_MB}" | bc -l) )); then
        echo -e "${RED}✗ Memory Warning: RSS exceeded ${TEST_MAX_RSS_MB} MB threshold (${POST_MB} MB)${NC}" >&2
        FAILED=1
    else
        echo -e "${GREEN}✓ Memory Bound: RSS is within ${TEST_MAX_RSS_MB} MB bound${NC}"
    fi
    
    # Sample CPU usage
    local_pid=$(pgrep -x "${APP_NAME}" || pgrep -x "${APP_NAME}App" || echo "")
    if [[ -n "${local_pid}" ]]; then
        CPU_USAGE=$(ps -o %cpu= -p "${local_pid}" | tr -d ' ' || echo "0.0")
        echo -e "${APP_NAME} CPU:   ${CPU_USAGE}%"
        if (( $(echo "${CPU_USAGE} > ${TEST_MAX_CPU_PERCENT}" | bc -l) )); then
            echo -e "${YELLOW}⚠ CPU Notice: ${APP_NAME} CPU during test was ${CPU_USAGE}% (threshold: ${TEST_MAX_CPU_PERCENT}%)${NC}"
        else
            echo -e "${GREEN}✓ Idle CPU: CPU usage is well within bounds (${CPU_USAGE}% <= ${TEST_MAX_CPU_PERCENT}%)${NC}"
        fi
    fi
fi

if [[ "${FAILED}" -eq 0 ]]; then
    echo -e "\n${GREEN}${BOLD}✓ ALL TEST SUITES PASSED SUCCESSFULLY!${NC}\n"
    exit 0
else
    echo -e "\n${RED}${BOLD}✗ TEST FAILURES DETECTED!${NC}\n"
    exit 1
fi
