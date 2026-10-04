#!/usr/bin/env bash
# scripts/test-functional.sh
# Automated functional, edge-case, and stress testing harness for Taskbar.
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

# Default test mode
MODE="all"

usage() {
    cat <<EOF
${BOLD}Usage:${NC} ./scripts/test-functional.sh [MODE]

${BOLD}Test Modes:${NC}
  --quick        Run fast window lifecycle tests (TC-FUNC-*, ~15s)
  --edge-cases   Run boundary & corner case suite (TC-EDGE-*, ~5s)
  --stress       Run high-density window stress & memory benchmark (TC-STRESS-*, TC-PERF-*)
  --all          Run complete test suite (Unit + Functional + Edge + Stress, default)
  --help, -h     Show this help message

${BOLD}Requirements:${NC}
  - macOS 14.0 Sonoma or later
  - Accessibility Permissions enabled for Terminal/IDE (for --quick / --all)
EOF
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
echo -e "${BOLD}${CYAN}   Taskbar Automated Test Runner (Mode: ${MODE})       ${NC}"
echo -e "${BOLD}${CYAN}======================================================${NC}"

# 1. Pre-flight Checks: macOS Version
OS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [[ "${OS_VERSION}" -lt 14 ]]; then
    echo -e "${RED}Error: Taskbar requires macOS 14.0 Sonoma or later (detected macOS ${OS_VERSION}).${NC}" >&2
    exit 1
fi
echo -e "${GREEN}✓ OS check passed:${NC} macOS $(sw_vers -productVersion)"

# 2. Pre-flight Checks: Accessibility Permissions (for modes that interact with real windows)
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
        
        echo -n "Waiting for authorization (up to 15s)..."
        local waited=0
        while [[ $waited -lt 15 ]]; do
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
        echo -e "${RED}Error: Accessibility permissions not granted within 15 seconds.${NC}" >&2
        echo -e "${RED}Please grant permissions in System Settings > Privacy & Security > Accessibility.${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}✓ GRANTED${NC}"
}

# 3. Cleanup Dangling Fixtures
cleanup_fixtures() {
    osascript -e 'if application "TextEdit" is running then tell application "TextEdit" to quit saving no' 2>/dev/null || true
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
    pid=$(pgrep -x "Taskbar" || pgrep -x "TaskbarApp" || echo "")
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
    echo -e "Taskbar RSS:   ${BASELINE_MB} MB (Baseline) -> ${POST_MB} MB (Post-test)"
    
    # Assert Peak RSS < 45 MB
    if (( $(echo "${POST_MB} > 45.0" | bc -l) )); then
        echo -e "${RED}✗ Memory Warning: RSS exceeded 45.0 MB threshold (${POST_MB} MB)${NC}" >&2
        FAILED=1
    else
        echo -e "${GREEN}✓ Memory Bound: RSS is within 45.0 MB bound${NC}"
    fi
    
    # Sample CPU usage
    local_pid=$(pgrep -x "Taskbar" || pgrep -x "TaskbarApp" || echo "")
    if [[ -n "${local_pid}" ]]; then
        CPU_USAGE=$(ps -o %cpu= -p "${local_pid}" | tr -d ' ' || echo "0.0")
        echo -e "Taskbar CPU:   ${CPU_USAGE}%"
        if (( $(echo "${CPU_USAGE} > 2.0" | bc -l) )); then
            echo -e "${YELLOW}⚠ CPU Notice: Taskbar CPU during test was ${CPU_USAGE}%${NC}"
        else
            echo -e "${GREEN}✓ Idle CPU: CPU usage is well within bounds (${CPU_USAGE}%)${NC}"
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
