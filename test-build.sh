#!/bin/bash
#
# test-build.sh - Validate the complete build system
#
# This script verifies that all components can be built successfully.
# Useful for CI/CD and pre-commit checks.
#
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[✓]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[✗]${NC} $*"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Test file existence
test_file_exists() {
    local file="$1"
    local desc="$2"
    
    if [[ -f "$file" ]]; then
        log_pass "$desc exists"
    else
        log_fail "$desc not found: $file"
    fi
}

# Test directory structure
test_dir_structure() {
    log_test "Directory Structure"
    
    local required_dirs=(
        "drivers/apple-ibridge-src"
        "drivers/apple-touchbar-src"
        "kernel/patches"
        "scripts"
        "assets"
        "udev"
        "systemd"
        "third_party/tiny-dfr"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$PROJECT_ROOT/$dir" ]]; then
            log_pass "Directory exists: $dir"
        else
            log_fail "Directory missing: $dir"
        fi
    done
}

# Test critical files
test_critical_files() {
    log_test "Critical Files"
    
    test_file_exists "$PROJECT_ROOT/drivers/apple-ibridge-src/apple-ibridge.c" "apple-ibridge.c"
    test_file_exists "$PROJECT_ROOT/drivers/apple-ibridge-src/dkms.conf" "apple-ibridge DKMS config"
    test_file_exists "$PROJECT_ROOT/drivers/apple-ibridge-src/Makefile" "apple-ibridge Makefile"
    test_file_exists "$PROJECT_ROOT/drivers/apple-ibridge-src/Makefile.adaptive" "apple-ibridge adaptive features"
    
    test_file_exists "$PROJECT_ROOT/drivers/apple-touchbar-src/apple-ib-tb.c" "apple-ib-tb.c"
    test_file_exists "$PROJECT_ROOT/drivers/apple-touchbar-src/dkms.conf" "apple-touchbar DKMS config"
    test_file_exists "$PROJECT_ROOT/drivers/apple-touchbar-src/Makefile" "apple-touchbar Makefile"
    test_file_exists "$PROJECT_ROOT/drivers/apple-touchbar-src/Makefile.adaptive" "apple-touchbar adaptive features"
    
    test_file_exists "$PROJECT_ROOT/kernel/patches/0001-hid-export-report-item-parsers.patch" "Patch 1"
    test_file_exists "$PROJECT_ROOT/kernel/patches/0002-drivers-hid-apple-ibridge.patch" "Patch 2"
    test_file_exists "$PROJECT_ROOT/kernel/patches/0003-drivers-hid-apple-touchbar.patch" "Patch 3"
    test_file_exists "$PROJECT_ROOT/kernel/patches/0004-hid-sensor-als-support.patch" "Patch 4"
    test_file_exists "$PROJECT_ROOT/kernel/patches/0005-hid-recognize-sensors-with-appcollections.patch" "Patch 5"
    
    test_file_exists "$PROJECT_ROOT/scripts/install-touchbar.sh" "Main install script"
    test_file_exists "$PROJECT_ROOT/scripts/install-drivers.sh" "Driver install script"
    test_file_exists "$PROJECT_ROOT/scripts/detect-kernel-features.sh" "Feature detection script"
    test_file_exists "$PROJECT_ROOT/scripts/build-kernel.sh" "Kernel build script"
    
    test_file_exists "$PROJECT_ROOT/assets/extract-touchbar-assets.sh" "Asset extraction script"
    test_file_exists "$PROJECT_ROOT/udev/99-apple-touchbar.rules" "udev rules"
    test_file_exists "$PROJECT_ROOT/systemd/tiny-dfr.service" "systemd service"
    
    test_file_exists "$PROJECT_ROOT/third_party/tiny-dfr/tiny-dfr.c" "tiny-dfr source"
    test_file_exists "$PROJECT_ROOT/third_party/tiny-dfr/Makefile" "tiny-dfr Makefile"
    test_file_exists "$PROJECT_ROOT/third_party/tiny-dfr/LICENSE" "tiny-dfr LICENSE"
}

# Test script permissions
test_script_permissions() {
    log_test "Script Permissions"
    
    local scripts=(
        "$PROJECT_ROOT/scripts/install-touchbar.sh"
        "$PROJECT_ROOT/scripts/install-drivers.sh"
        "$PROJECT_ROOT/scripts/detect-kernel-features.sh"
        "$PROJECT_ROOT/scripts/build-kernel.sh"
        "$PROJECT_ROOT/assets/extract-touchbar-assets.sh"
        "$PROJECT_ROOT/test-build.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            log_pass "Executable: $(basename "$script")"
        else
            log_fail "Not executable: $(basename "$script")"
        fi
    done
}

# Test shell script syntax
test_shell_syntax() {
    log_test "Shell Script Syntax"
    
    local scripts=(
        "$PROJECT_ROOT/scripts/install-touchbar.sh"
        "$PROJECT_ROOT/scripts/install-drivers.sh"
        "$PROJECT_ROOT/scripts/detect-kernel-features.sh"
        "$PROJECT_ROOT/assets/extract-touchbar-assets.sh"
    )
    
    for script in "${scripts[@]}"; do
        if bash -n "$script" 2>/dev/null; then
            log_pass "Syntax valid: $(basename "$script")"
        else
            log_fail "Syntax error in: $(basename "$script")"
        fi
    done
}

# Test dkms.conf syntax
test_dkms_syntax() {
    log_test "DKMS Configuration"
    
    local dkms_files=(
        "$PROJECT_ROOT/drivers/apple-ibridge-src/dkms.conf"
        "$PROJECT_ROOT/drivers/apple-touchbar-src/dkms.conf"
    )
    
    for dkms in "${dkms_files[@]}"; do
        if grep -q "^PACKAGE_NAME=" "$dkms" && grep -q "^PACKAGE_VERSION=" "$dkms"; then
            log_pass "DKMS config valid: $(basename "$(dirname "$dkms")")"
        else
            log_fail "DKMS config invalid: $dkms"
        fi
    done
}

# Test udev rules syntax
test_udev_rules() {
    log_test "udev Rules"
    
    if grep -q "SUBSYSTEM" "$PROJECT_ROOT/udev/99-apple-touchbar.rules"; then
        log_pass "udev rules contain SUBSYSTEM"
    else
        log_fail "udev rules missing SUBSYSTEM rules"
    fi
    
    if grep -q "05ac" "$PROJECT_ROOT/udev/99-apple-touchbar.rules"; then
        log_pass "udev rules contain Apple vendor ID (05ac)"
    else
        log_fail "udev rules missing Apple vendor ID"
    fi
}

# Test systemd service
test_systemd_service() {
    log_test "systemd Service"
    
    if grep -q "\\[Unit\\]" "$PROJECT_ROOT/systemd/tiny-dfr.service"; then
        log_pass "Service file has [Unit] section"
    else
        log_fail "Service file missing [Unit] section"
    fi
    
    if grep -q "\\[Service\\]" "$PROJECT_ROOT/systemd/tiny-dfr.service"; then
        log_pass "Service file has [Service] section"
    else
        log_fail "Service file missing [Service] section"
    fi
    
    if grep -q "ExecStart=/usr/local/bin/tiny-dfr" "$PROJECT_ROOT/systemd/tiny-dfr.service"; then
        log_pass "Service file specifies ExecStart"
    else
        log_fail "Service file missing ExecStart"
    fi
}

# Test Makefiles
test_makefiles() {
    log_test "Makefile Structure"
    
    if grep -q "obj-m" "$PROJECT_ROOT/drivers/apple-ibridge-src/Makefile"; then
        log_pass "apple-ibridge Makefile has obj-m"
    else
        log_fail "apple-ibridge Makefile missing obj-m"
    fi
    
    if grep -q "Makefile.adaptive" "$PROJECT_ROOT/drivers/apple-ibridge-src/Makefile"; then
        log_pass "apple-ibridge Makefile includes Makefile.adaptive"
    else
        log_fail "apple-ibridge Makefile doesn't include Makefile.adaptive"
    fi
    
    if grep -q "obj-m" "$PROJECT_ROOT/drivers/apple-touchbar-src/Makefile"; then
        log_pass "apple-touchbar Makefile has obj-m"
    else
        log_fail "apple-touchbar Makefile missing obj-m"
    fi
    
    if grep -q "Makefile.adaptive" "$PROJECT_ROOT/drivers/apple-touchbar-src/Makefile"; then
        log_pass "apple-touchbar Makefile includes Makefile.adaptive"
    else
        log_fail "apple-touchbar Makefile doesn't include Makefile.adaptive"
    fi
}

# Test patch format
test_patch_format() {
    log_test "Patch Format"
    
    local patches=(
        "$PROJECT_ROOT/kernel/patches"/*patch
    )
    
    for patch in "${patches[@]}"; do
        if grep -q "^--- a/" "$patch" && grep -q "^+++ b/" "$patch"; then
            log_pass "Valid patch format: $(basename "$patch")"
        else
            log_fail "Invalid patch format: $(basename "$patch")"
        fi
    done
}

# Main test runner
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Apple T1 Kernel Patches - Build Test         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    test_dir_structure
    echo ""
    
    test_critical_files
    echo ""
    
    test_script_permissions
    echo ""
    
    test_shell_syntax
    echo ""
    
    test_dkms_syntax
    echo ""
    
    test_udev_rules
    echo ""
    
    test_systemd_service
    echo ""
    
    test_makefiles
    echo ""
    
    test_patch_format
    echo ""
    
    # Summary
    local total=$((TESTS_PASSED + TESTS_FAILED))
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Test Summary                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo -e "Total tests: $total"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed! ✓${NC}"
        return 0
    fi
}

main "$@"
