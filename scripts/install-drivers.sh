#!/bin/bash
#
# install-drivers.sh - Install and build Apple T1 drivers via DKMS
#
# This script handles:
# - Copying driver source to DKMS source directory
# - Building drivers with kernel
# - Installing kernel modules
# - Handling kernel updates via DKMS
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

# Logging functions
log_info() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

log_debug() {
    [[ "${VERBOSE:-0}" -eq 1 ]] && echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Install driver via DKMS
install_driver_dkms() {
    local driver_name="$1"
    local driver_src_dir="$2"
    local version="${3:-1.0}"
    local dkms_src_dir="/usr/src/${driver_name}-${version}"
    
    log_info "Installing $driver_name (v$version) via DKMS..."
    
    # Check if already installed
    if dkms status "$driver_name/$version" >/dev/null 2>&1; then
        log_warn "$driver_name/$version already registered with DKMS"
        log_info "Removing old version..."
        dkms remove -m "$driver_name" -v "$version" --all 2>/dev/null || true
    fi
    
    # Create DKMS source directory
    log_debug "Creating DKMS source directory: $dkms_src_dir"
    mkdir -p "$dkms_src_dir"
    
    # Copy driver source
    log_debug "Copying driver source to $dkms_src_dir"
    cp -r "$driver_src_dir"/* "$dkms_src_dir/" 2>/dev/null || {
        log_error "Failed to copy driver source"
        return 1
    }
    
    # Verify dkms.conf exists
    if [[ ! -f "$dkms_src_dir/dkms.conf" ]]; then
        log_error "dkms.conf not found in $dkms_src_dir"
        return 1
    fi
    
    # Register with DKMS
    log_info "Registering $driver_name with DKMS..."
    if ! dkms add -m "$driver_name" -v "$version" 2>&1 | grep -v "^DKMS"; then
        log_error "Failed to register $driver_name with DKMS"
        return 1
    fi
    
    # Build driver
    log_info "Building $driver_name..."
    if ! dkms build -m "$driver_name" -v "$version" 2>&1 | grep -v "^DKMS"; then
        log_error "Failed to build $driver_name"
        log_warn "Check dkms status with: dkms status"
        return 1
    fi
    
    # Install driver
    log_info "Installing $driver_name..."
    if ! dkms install -m "$driver_name" -v "$version" 2>&1 | grep -v "^DKMS"; then
        log_error "Failed to install $driver_name"
        return 1
    fi
    
    log_info "Successfully installed $driver_name"
    return 0
}

# Build driver directly (fallback if DKMS unavailable)
build_driver_direct() {
    local driver_name="$1"
    local driver_src_dir="$2"
    
    log_warn "DKMS not available, building driver directly..."
    
    if [[ ! -d "$driver_src_dir" ]]; then
        log_error "Driver source directory not found: $driver_src_dir"
        return 1
    fi
    
    log_info "Building $driver_name..."
    if ! (cd "$driver_src_dir" && make -j$(nproc)); then
        log_error "Failed to build $driver_name"
        return 1
    fi
    
    log_info "Installing $driver_name..."
    if ! (cd "$driver_src_dir" && make install); then
        log_error "Failed to install $driver_name"
        return 1
    fi
    
    log_info "Successfully built and installed $driver_name"
    return 0
}

# Verify driver is loaded
verify_driver() {
    local driver_name="$1"
    local module_name="${2:-$driver_name}"
    
    log_info "Verifying $driver_name is loaded..."
    
    # Wait a moment for module to load
    sleep 1
    
    if lsmod | grep -q "^$module_name"; then
        log_info "$driver_name is loaded"
        return 0
    else
        log_warn "$driver_name not yet loaded"
        log_info "Attempting to load module..."
        if modprobe "$module_name" 2>/dev/null; then
            log_info "$driver_name loaded successfully"
            return 0
        else
            log_warn "$driver_name failed to load (may require other modules first)"
            return 1
        fi
    fi
}

# Main function
main() {
    check_root
    
    log_info "Apple T1 Driver Installation Script"
    echo ""
    
    # Detect if DKMS is available
    local use_dkms=0
    if command -v dkms &>/dev/null; then
        log_info "DKMS found, using automatic kernel module management"
        use_dkms=1
    else
        log_warn "DKMS not installed, will build drivers directly"
        log_info "For automatic kernel updates, install DKMS package"
    fi
    
    # Install apple-ibridge driver
    log_info ""
    if [[ $use_dkms -eq 1 ]]; then
        install_driver_dkms "apple-ibridge" "$PROJECT_ROOT/drivers/apple-ibridge-src" "1.0" || {
            log_error "Failed to install apple-ibridge via DKMS"
            return 1
        }
    else
        build_driver_direct "apple-ibridge" "$PROJECT_ROOT/drivers/apple-ibridge-src" || {
            log_error "Failed to build apple-ibridge"
            return 1
        }
    fi
    verify_driver "apple-ibridge" "apple_ibridge" || true
    
    # Install apple-touchbar driver
    log_info ""
    if [[ $use_dkms -eq 1 ]]; then
        install_driver_dkms "apple-touchbar" "$PROJECT_ROOT/drivers/apple-touchbar-src" "1.0" || {
            log_error "Failed to install apple-touchbar via DKMS"
            return 1
        }
    else
        build_driver_direct "apple-touchbar" "$PROJECT_ROOT/drivers/apple-touchbar-src" || {
            log_error "Failed to build apple-touchbar"
            return 1
        }
    fi
    verify_driver "apple-touchbar" "apple_ib_tb" || true
    
    log_info ""
    log_info "Driver installation complete"
    
    # Load modules
    log_info "Loading kernel modules..."
    modprobe apple_ibridge 2>/dev/null || log_warn "Failed to load apple_ibridge"
    modprobe apple_ib_tb 2>/dev/null || log_warn "Failed to load apple_ib_tb"
    
    log_info "Drivers are ready for use"
    return 0
}

main "$@"
