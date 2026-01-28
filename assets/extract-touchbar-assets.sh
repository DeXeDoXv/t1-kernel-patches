#!/bin/bash
#
# extract-touchbar-assets.sh - Extract Touch Bar assets from Apple recovery
#
# This script extracts Touch Bar frameworks and resources from Apple recovery images
# without redistributing Apple proprietary binaries.
#
# The extracted frameworks are required by the userspace tiny-dfr daemon to control
# the Touch Bar display.
#
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Global variables
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/apple-t1-assets"
ASSETS_INSTALL_DIR="${1:-/usr/share/tiny-dfr}"
TEMP_DIR=""

# Cleanup on exit
cleanup() {
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Create temporary directory
create_temp_dir() {
    TEMP_DIR=$(mktemp -d)
    log_debug "Created temporary directory: $TEMP_DIR"
}

# Download file with checksum verification
download_with_checksum() {
    local url="$1"
    local expected_checksum="${2:-}"
    local output_file="$3"
    
    log_info "Downloading: $(basename "$url")"
    log_debug "URL: $url"
    
    if ! curl -L --progress-bar -f -o "$output_file" "$url" 2>&1; then
        log_error "Failed to download: $url"
        return 1
    fi
    
    # Verify checksum if provided
    if [[ -n "$expected_checksum" ]]; then
        log_debug "Verifying checksum..."
        local actual_checksum=$(sha256sum "$output_file" | awk '{print $1}')
        if [[ "$actual_checksum" != "$expected_checksum" ]]; then
            log_error "Checksum mismatch!"
            log_error "Expected: $expected_checksum"
            log_error "Got:      $actual_checksum"
            return 1
        fi
        log_info "Checksum verified"
    else
        log_warn "No checksum provided, skipping verification"
    fi
    
    return 0
}

# Extract TouchBar frameworks from DMG
extract_from_dmg() {
    local dmg_path="$1"
    
    if [[ ! -f "$dmg_path" ]]; then
        log_error "DMG file not found: $dmg_path"
        return 1
    fi
    
    log_info "Extracting frameworks from: $(basename "$dmg_path")"
    
    local mount_point=$(mktemp -d)
    local dmg_device
    
    # Attach DMG
    log_debug "Attaching DMG..."
    dmg_device=$(hdiutil attach "$dmg_path" -readonly -noverify 2>/dev/null | grep -oE '/dev/disk[0-9]' | head -1)
    
    if [[ -z "$dmg_device" ]]; then
        log_error "Failed to attach DMG"
        rm -rf "$mount_point"
        return 1
    fi
    
    log_debug "DMG attached to: $dmg_device"
    
    # Wait for mount
    sleep 2
    
    # Find actual mount point
    mount_point=$(mount | grep "$dmg_device" | awk '{print $3}' | head -1)
    
    if [[ -z "$mount_point" ]]; then
        log_error "Could not determine DMG mount point"
        hdiutil detach "$dmg_device" 2>/dev/null || true
        return 1
    fi
    
    log_info "DMG mounted at: $mount_point"
    
    # Extract frameworks
    local frameworks=(
        "System/Library/PrivateFrameworks/DisplayServices.framework"
        "System/Library/Frameworks/ApplicationServices.framework"
        "System/Library/PrivateFrameworks/CoreBrightness.framework"
        "System/Library/PrivateFrameworks/ProximityServiceKit.framework"
    )
    
    local extracted=0
    for framework in "${frameworks[@]}"; do
        local src="$mount_point/$framework"
        if [[ -d "$src" ]]; then
            log_info "Extracting: $framework"
            mkdir -p "$TEMP_DIR/frameworks"
            cp -r "$src" "$TEMP_DIR/frameworks/" || log_warn "Failed to extract $framework"
            ((extracted++))
        fi
    done
    
    # Cleanup
    log_debug "Detaching DMG..."
    hdiutil detach "$dmg_device" 2>/dev/null || true
    
    if [[ $extracted -gt 0 ]]; then
        log_info "Successfully extracted $extracted framework(s)"
        return 0
    else
        log_warn "No frameworks found in DMG"
        return 1
    fi
}

# Extract from macOS installer ISO/IMG
extract_from_installer() {
    local installer_path="$1"
    
    if [[ ! -f "$installer_path" ]]; then
        log_error "Installer not found: $installer_path"
        return 1
    fi
    
    log_info "Extracting from macOS installer..."
    
    # Determine file type
    local file_type=$(file -b "$installer_path" | head -1)
    
    case "$file_type" in
        *"Mach-O"*|*"Mach"*)
            log_debug "Detected Mach-O binary"
            # Cannot extract from binary directly
            return 1
            ;;
        *"ISO 9660"*)
            # Handle ISO mounting
            log_debug "Detected ISO format"
            return 1
            ;;
    esac
    
    return 1
}

# Create minimal stub assets if full extraction unavailable
create_stub_assets() {
    log_warn "Creating stub asset structure..."
    
    mkdir -p "$ASSETS_INSTALL_DIR"/frameworks
    mkdir -p "$ASSETS_INSTALL_DIR"/resources
    
    # Create version marker
    cat > "$ASSETS_INSTALL_DIR"/VERSION <<EOF
# Touch Bar Assets Version
# This is a stub installation
# For full Touch Bar functionality, extract from macOS recovery image
# See https://github.com/DeXeDoXv/t1-kernel-patches for instructions

VERSION=1.0
STUB=1
EOF
    
    # Create README for manual extraction
    cat > "$ASSETS_INSTALL_DIR"/EXTRACT_MANUAL.txt <<EOF
Manual Touch Bar Assets Extraction
===================================

The Touch Bar display requires frameworks from macOS. To extract them:

1. Obtain a macOS Sonoma/Monterey installer or recovery image
2. Mount the installer DMG or ISO
3. Extract frameworks from:
   - System/Library/PrivateFrameworks/DisplayServices.framework
   - System/Library/PrivateFrameworks/CoreBrightness.framework
   - System/Library/PrivateFrameworks/ProximityServiceKit.framework
4. Copy to: $ASSETS_INSTALL_DIR/frameworks/

Alternatively, boot into recovery mode and use:
  \$ sudo bash extract-touchbar-assets.sh

See README.md for detailed instructions.
EOF
    
    chmod 644 "$ASSETS_INSTALL_DIR"/EXTRACT_MANUAL.txt
    
    log_info "Stub assets created at: $ASSETS_INSTALL_DIR"
    return 0
}

# Install extracted assets
install_assets() {
    log_info "Installing assets to: $ASSETS_INSTALL_DIR"
    
    mkdir -p "$ASSETS_INSTALL_DIR"
    
    # Copy frameworks if extracted
    if [[ -d "$TEMP_DIR/frameworks" ]]; then
        log_debug "Copying frameworks..."
        cp -r "$TEMP_DIR/frameworks"/* "$ASSETS_INSTALL_DIR/" || {
            log_error "Failed to copy frameworks"
            return 1
        }
        log_info "Frameworks installed"
    fi
    
    # Create version marker
    cat > "$ASSETS_INSTALL_DIR/VERSION" <<EOF
VERSION=1.0
EXTRACTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOSTNAME=$(hostname)
EOF
    
    chmod 644 "$ASSETS_INSTALL_DIR/VERSION"
    
    log_info "Assets installation complete"
    return 0
}

# Main function
main() {
    log_info "Apple Touch Bar Asset Extraction Tool"
    echo ""
    
    # Check permissions for system installation
    if [[ "$ASSETS_INSTALL_DIR" == /usr/share/* ]] || [[ "$ASSETS_INSTALL_DIR" == /usr/local/share/* ]]; then
        if [[ $EUID -ne 0 ]]; then
            log_error "System installation requires root privileges"
            exit 1
        fi
    fi
    
    # Create directories
    mkdir -p "$CACHE_DIR"
    create_temp_dir
    
    log_info "Cache directory: $CACHE_DIR"
    log_info "Installation directory: $ASSETS_INSTALL_DIR"
    echo ""
    
    # Attempt extraction methods in order
    local success=0
    
    # Method 1: Extract from provided DMG file
    if [[ -n "${DMG_PATH:-}" ]] && [[ -f "$DMG_PATH" ]]; then
        log_info "Using provided DMG file: $DMG_PATH"
        if extract_from_dmg "$DMG_PATH"; then
            success=1
        fi
    fi
    
    # Method 2: Look for mounted recovery partitions
    if [[ $success -eq 0 ]]; then
        for mount_point in /mnt/recovery /Volumes/Recovery*; do
            if [[ -d "$mount_point" ]]; then
                log_info "Found recovery partition: $mount_point"
                # Try to extract frameworks directly from mounted volume
                if [[ -d "$mount_point/System/Library/PrivateFrameworks" ]]; then
                    log_info "Extracting frameworks from recovery mount..."
                    mkdir -p "$TEMP_DIR/frameworks"
                    if cp -r "$mount_point/System/Library/PrivateFrameworks"/{DisplayServices,CoreBrightness,ProximityServiceKit}.framework "$TEMP_DIR/frameworks/" 2>/dev/null; then
                        success=1
                        break
                    fi
                fi
            fi
        done
    fi
    
    # Method 3: Download from Apple (future implementation)
    if [[ $success -eq 0 ]]; then
        log_warn "Full framework extraction not yet available"
        log_info "Automatic download from Apple not implemented"
    fi
    
    # Install assets or create stub
    if [[ $success -eq 1 ]]; then
        install_assets
    else
        log_warn "Could not extract frameworks"
        log_info "Creating stub asset structure..."
        create_stub_assets
    fi
    
    echo ""
    log_info "Asset extraction complete"
    echo ""
    log_info "Next steps:"
    echo "  1. The kernel modules must be built and installed"
    echo "  2. The tiny-dfr daemon will control the Touch Bar display"
    echo "  3. For full functionality, extract and install Touch Bar frameworks"
    echo ""
    log_info "For troubleshooting, see: $ASSETS_INSTALL_DIR/EXTRACT_MANUAL.txt"
}

main "$@"
