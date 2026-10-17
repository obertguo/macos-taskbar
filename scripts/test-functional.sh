#!/usr/bin/env bash
# scripts/test-functional.sh
# Automated functional, edge-case, and stress testing harness for Taskbar.
# Configuration and thresholds are sourced dynamically via scripts/common.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

# Source single-source-of-truth configuration
load_build_env

# Default test mode
MODE="all"
COVERAGE=0

usage() {
    echo -e "${BOLD}Usage:${NC} ./scripts/test-functional.sh [MODE] [OPTIONS]"
    echo ""
    echo -e "${BOLD}Test Modes:${NC}"
    echo "  --quick        Run fast window lifecycle tests (TC-FUNC-*, ~15s)"
    echo "  --edge-cases   Run boundary & corner case suite (TC-EDGE-*, ~5s)"
    echo "  --stress       Run high-density window stress & memory benchmark (TC-STRESS-*, TC-PERF-*)"
    echo "  --reordering   Run drag-and-drop slot reordering suite (TC-DRAG-*)"
    echo "  --grouping     Run application window grouping & popup suite (TC-GROUP-*)"
    echo "  --all          Run complete test suite (Unit + Functional + Edge + Stress + Reordering + Grouping, default)"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --coverage     Enable code coverage measurement and generate llvm-cov report"
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
        --reordering)
            MODE="reordering"
            shift
            ;;
        --grouping)
            MODE="grouping"
            shift
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --coverage)
            COVERAGE=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option '$1'"
            usage
            exit 1
            ;;
    esac
done

log_header "${APP_NAME} Automated Test Runner (Mode: ${MODE}, Coverage: $([[ ${COVERAGE} -eq 1 ]] && echo 'ON' || echo 'OFF'))"

# 1. Pre-flight Checks: macOS Version against MIN_MACOS_VERSION from build.env
check_min_macos_version "${MIN_MACOS_VERSION}"

# 2. Pre-flight Checks: Accessibility Permissions
check_accessibility() {
    echo -n "Checking Accessibility permissions... "
    local is_trusted
    is_trusted=$(osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || echo "false")
    
    if [[ "${is_trusted}" != "true" ]]; then
        echo -e "${YELLOW}NOT GRANTED${NC}"
        log_warn "Prompting for Accessibility permission in System Settings..."
        
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
                echo ""
                log_success "Accessibility permission granted!"
                return 0
            fi
            echo -n "."
        done
        echo ""
        log_error "Accessibility permissions not granted within ${TEST_AX_AUTH_TIMEOUT_SECONDS} seconds."
        echo "Please grant permissions in System Settings > Privacy & Security > Accessibility." >&2
        exit 1
    fi
    log_success "Accessibility permissions GRANTED"
}

# 3. Cleanup Dangling Fixtures
cleanup_fixtures() {
    osascript -e "if application \"${TEST_FIXTURE_APP}\" is running then tell application \"${TEST_FIXTURE_APP}\" to quit saving no" 2>/dev/null || true
    pkill -9 -x "${TEST_FIXTURE_APP}" 2>/dev/null || true
}

# Export TASKBAR_RUN_LIVE_AX_TESTS=1 for modes that involve live tests
if [[ "${MODE}" == "quick" ]]; then
    check_accessibility
    export TASKBAR_RUN_LIVE_AX_TESTS=1
    log_info "Enabled live Accessibility integration tests (TASKBAR_RUN_LIVE_AX_TESTS=1)"
elif [[ "${MODE}" == "edge-cases" || "${MODE}" == "all" ]]; then
    # In all or edge-cases mode, live AX is optional: enable if granted, but do not block or fail headless runs
    AX_TRUSTED=$(osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || echo "false")
    if [[ "${AX_TRUSTED}" == "true" ]]; then
        export TASKBAR_RUN_LIVE_AX_TESTS=1
        log_info "Live Accessibility permissions granted; enabling live integration tests (TASKBAR_RUN_LIVE_AX_TESTS=1)"
    else
        log_info "Accessibility permissions not granted; running headless test suites without live AX"
    fi
fi
cleanup_fixtures

# Trap exit to guarantee fixture cleanup
trap cleanup_fixtures EXIT

cd "${PROJECT_ROOT}"

# 4. Measure Baseline Memory
APP_PID=$(find_app_pid "${APP_NAME}")
BASELINE_RSS=$(get_process_rss_kb "${APP_PID}")

# Helper to execute a swift test suite with optional coverage instrumentation
run_test_suite() {
    local filter="$1"
    if [[ "${COVERAGE}" -eq 1 ]]; then
        swift test --enable-code-coverage --filter "${filter}" || FAILED=1
    else
        swift test --filter "${filter}" || FAILED=1
    fi
}

# 5. Run Test Target
START_TIME=$(date +%s)
FAILED=0

case "${MODE}" in
    quick)
        log_info "Running Quick Window Lifecycle Suite (TC-FUNC-*)..."
        run_test_suite WindowLifecycleIntegrationTests
        ;;
    edge-cases)
        log_info "Running Edge Cases Suite (TC-EDGE-*)..."
        run_test_suite EdgeCasesIntegrationTests
        ;;
    stress)
        log_info "Running Stress & Capacity Suite (TC-STRESS-*, TC-PERF-*)..."
        run_test_suite StressIntegrationTests
        ;;
    reordering)
        log_info "Running Window Reordering & Drag Suite (TC-DRAG-*)..."
        run_test_suite WindowReorderingIntegrationTests
        ;;
    grouping)
        log_info "Running Window Grouping Suite (TC-GROUP-*)..."
        run_test_suite WindowGroupingIntegrationTests
        run_test_suite StatusMenuGroupingTests
        ;;
    all)
        if [[ "${COVERAGE}" -eq 1 ]]; then
            log_info "Running complete test suite with code coverage (including all unit and integration suites)..."
            swift test --enable-code-coverage || FAILED=1
        else
            log_info "Running complete test suite (including all unit and integration suites)..."
            swift test || FAILED=1
        fi
        ;;
esac

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 6. Memory & Performance Verification
APP_PID=$(find_app_pid "${APP_NAME}")
POST_RSS=$(get_process_rss_kb "${APP_PID}")

log_header "Test Execution Summary"
echo -e "Mode:          ${BOLD}${MODE}${NC}"
echo -e "Duration:      ${DURATION}s"

if [[ "${BASELINE_RSS}" != "0" ]]; then
    BASELINE_MB=$(echo "scale=2; ${BASELINE_RSS} / 1024" | bc)
    POST_MB=$(echo "scale=2; ${POST_RSS} / 1024" | bc)
    echo -e "${APP_NAME} RSS:   ${BASELINE_MB} MB (Baseline) -> ${POST_MB} MB (Post-test)"
    
    # Assert Peak RSS < TEST_MAX_RSS_MB
    if (( $(echo "${POST_MB} > ${TEST_MAX_RSS_MB}" | bc -l) )); then
        log_error "Memory Warning: RSS exceeded ${TEST_MAX_RSS_MB} MB threshold (${POST_MB} MB)"
        FAILED=1
    else
        log_success "Memory Bound: RSS is within ${TEST_MAX_RSS_MB} MB bound"
    fi
    
    # Sample CPU usage
    if [[ -n "${APP_PID}" ]]; then
        CPU_USAGE=$(get_process_cpu_percent "${APP_PID}")
        echo -e "${APP_NAME} CPU:   ${CPU_USAGE}%"
        if (( $(echo "${CPU_USAGE} > ${TEST_MAX_CPU_PERCENT}" | bc -l) )); then
            log_warn "${APP_NAME} CPU during test was ${CPU_USAGE}% (threshold: ${TEST_MAX_CPU_PERCENT}%)"
        else
            log_success "Idle CPU: CPU usage is well within bounds (${CPU_USAGE}% <= ${TEST_MAX_CPU_PERCENT}%)"
        fi
    fi
fi

# 7. Code Coverage Report
generate_coverage_report() {
    log_header "Code Coverage Report"

    # Locate the profdata file
    local profdata
    profdata=$(find .build -name "default.profdata" 2>/dev/null | head -n 1)
    if [[ -z "${profdata}" ]]; then
        profdata=$(find .build -name "*.profdata" 2>/dev/null | head -n 1)
    fi

    # Locate test binaries
    local binaries=()
    local bin_dir=".build/debug"
    if [[ ! -d "${bin_dir}" ]]; then
        bin_dir=".build"
    fi

    while IFS= read -r bin; do
        if [[ -n "${bin}" && -x "${bin}" ]]; then
            binaries+=("${bin}")
        fi
    done < <(find -L "${bin_dir}" -type f \( -path "*/Contents/MacOS/*Tests" -o -name "*PackageTests" \) 2>/dev/null | sort -u)

    if [[ ${#binaries[@]} -eq 0 ]]; then
        while IFS= read -r bin; do
            if [[ -n "${bin}" && -x "${bin}" ]]; then
                binaries+=("${bin}")
            fi
        done < <(find .build -type f \( -path "*/Contents/MacOS/*Tests" -o -name "*PackageTests" \) 2>/dev/null | sort -u)
    fi

    if [[ -n "${profdata}" && ${#binaries[@]} -gt 0 ]]; then
        log_info "Profile data: ${profdata}"
        local primary_bin="${binaries[0]}"
        local extra_objects=()
        for ((i=1; i<${#binaries[@]}; i++)); do
            extra_objects+=("-object" "${binaries[i]}")
        done

        echo ""
        if [[ ${#binaries[@]} -gt 1 ]]; then
            xcrun llvm-cov report "${primary_bin}" "${extra_objects[@]}" -instr-profile="${profdata}" -ignore-filename-regex=".build|Tests" || log_warn "llvm-cov report returned an error"
        else
            xcrun llvm-cov report "${primary_bin}" -instr-profile="${profdata}" -ignore-filename-regex=".build|Tests" || log_warn "llvm-cov report returned an error"
        fi
        echo ""
    else
        log_warn "Could not generate coverage report: profdata or test binary not found."
        if [[ -z "${profdata}" ]]; then
            log_warn "No .profdata file found under .build"
        fi
        if [[ ${#binaries[@]} -eq 0 ]]; then
            log_warn "No test binary found under .build"
        fi
    fi
}

if [[ "${COVERAGE}" -eq 1 ]]; then
    generate_coverage_report
fi

if [[ "${FAILED}" -eq 0 ]]; then
    echo -e "\n${GREEN}${BOLD}✓ ALL TEST SUITES PASSED SUCCESSFULLY!${NC}\n"
    exit 0
else
    echo -e "\n${RED}${BOLD}✗ TEST FAILURES DETECTED!${NC}\n"
    exit 1
fi
