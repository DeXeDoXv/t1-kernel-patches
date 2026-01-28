#!/bin/bash
#
# build-kernel.sh - Helper to apply patches and build kernel with T1 support
#
# This script provides a framework for optionally building a custom kernel
# with Apple T1 support patches applied. DKMS-based installation is recommended.
#
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

KERNEL_SOURCE="${1:?Kernel source directory required}"
PATCHES_DIR="${2:-.}/kernel/patches"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

check_kernel_source() {
    if [[ ! -f "$KERNEL_SOURCE/Makefile" ]]; then
        log_error "Invalid kernel source directory: $KERNEL_SOURCE"
        exit 1
    fi
    
    log_info "Kernel source verified: $KERNEL_SOURCE"
}

apply_patches() {
    log_info "Applying Apple T1 patches..."
    
    cd "$KERNEL_SOURCE"
    
    if [[ ! -d "$PATCHES_DIR" ]]; then
        log_error "Patches directory not found: $PATCHES_DIR"
        return 1
    fi
    
    local patch_count=0
    local failed_count=0
    
    # Apply patches in order
    for patch_file in "$PATCHES_DIR"/0*.patch; do
        if [[ ! -f "$patch_file" ]]; then
            continue
        fi
        
        patch_count=$((patch_count + 1))
        local patch_name=$(basename "$patch_file")
        
        log_info "Applying: $patch_name"
        
        if patch -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
            # Patch applies cleanly
            if patch -p1 < "$patch_file"; then
                log_info "✓ $patch_name applied successfully"
            else
                log_error "✗ $patch_name failed to apply (error)"
                failed_count=$((failed_count + 1))
            fi
        else
            # Try fuzzy application
            log_warn "Patch $patch_name doesn't apply cleanly, trying fuzzy mode..."
            if patch -p1 -l < "$patch_file"; then
                log_info "✓ $patch_name applied with fuzzy matching"
            else
                log_error "✗ $patch_name failed even with fuzzy matching"
                failed_count=$((failed_count + 1))
            fi
        fi
    done
    
    log_info "Patch application complete: $patch_count patches, $failed_count failed"
    
    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

configure_kernel() {
    log_info "Configuring kernel for Apple T1 support..."
    
    cd "$KERNEL_SOURCE"
    
    # Enable required options
    local required_options=(
        "CONFIG_HID=y"
        "CONFIG_HID_SUPPORT=y"
        "CONFIG_HID_APPLE=m"
        "CONFIG_USB_HID=m"
        "CONFIG_MFD_CORE=y"
        "CONFIG_ACPI=y"
        "CONFIG_SENSORS_HID_IIO=y"
    )
    
    log_info "Kernel options to enable:"
    for option in "${required_options[@]}"; do
        echo "  $option"
    done
    
    # Try to update config
    if [[ -f .config ]]; then
        for option in "${required_options[@]}"; do
            local key="${option%%=*}"
            local value="${option#*=}"
            
            # Update if already present, else add
            if grep -q "^$key" .config; then
                sed -i "s/^$key=.*/$option/" .config
            else
                echo "$option" >> .config
            fi
        done
        
        log_info "Kernel config updated"
    else
        log_warn "No .config found, using defaults"
    fi
}

show_help() {
    cat << EOF
Usage: $0 <KERNEL_SOURCE> [PATCHES_DIR]

Helper script to apply Apple T1 patches to kernel source and build.

WARNING: This is intended for advanced users. Most users should use:
    sudo ./scripts/install-touchbar.sh

This script is provided for:
- Custom kernel builds
- Distribution packaging
- Development and testing

ARGUMENTS:
    KERNEL_SOURCE   Path to kernel source directory (required)
    PATCHES_DIR     Path to patches directory (default: ./kernel/patches)

ENVIRONMENT VARIABLES:
    SKIP_APPLY_PATCHES   Skip applying patches (default: 0)
    SKIP_CONFIG_UPDATE   Skip kernel config update (default: 0)

EXAMPLE:
    $0 /usr/src/linux-6.0 ./kernel/patches

EOF
}

main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    check_kernel_source
    
    if [[ "${SKIP_APPLY_PATCHES:-0}" != "1" ]]; then
        apply_patches
    fi
    
    if [[ "${SKIP_CONFIG_UPDATE:-0}" != "1" ]]; then
        configure_kernel
    fi
    
    log_info "Kernel preparation complete"
    echo ""
    log_info "Next steps:"
    echo "  1. Review kernel configuration:"
    echo "     cd $KERNEL_SOURCE && make menuconfig"
    echo ""
    echo "  2. Build kernel:"
    echo "     cd $KERNEL_SOURCE && make -j$(nproc)"
    echo ""
    echo "  3. Install:"
    echo "     cd $KERNEL_SOURCE && make install && make modules_install"
    echo ""
    echo "  4. Update bootloader and reboot"
}

main "$@"
