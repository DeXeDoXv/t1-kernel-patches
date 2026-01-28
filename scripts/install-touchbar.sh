#!/bin/bash
#
# install-touchbar.sh - Universal installer for Apple T1 Touch Bar support
#
# This is the main entry point that handles:
# - Distro detection and package management
# - Kernel feature detection
# - DKMS driver compilation
# - Userspace tools installation (tiny-dfr)
# - Permission and systemd integration
#
# Supported distros: Debian/Ubuntu, Fedora, Arch, generic Linux
#
# Usage: sudo ./install-touchbar.sh [OPTIONS]
#
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
DISTRO=""
KERNEL_RELEASE=$(uname -r)
KERNEL_BUILD_DIR="/lib/modules/$KERNEL_RELEASE/build"
KERNEL_SOURCE_DIR="/lib/modules/$KERNEL_RELEASE/source"
DRY_RUN=0
VERBOSE=0
SKIP_DKMS=0
SKIP_USERSPACE=0
INSTALL_DIR="${INSTALL_DIR:-/usr/local}"

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
    [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

log_section() {
    echo ""
    echo -e "${CYAN}==== $* ====${NC}"
    echo ""
}

# Detect Linux distribution
detect_distro() {
    log_section "Detecting Linux Distribution"
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="${ID}"
        DISTRO_VERSION="${VERSION_ID}"
        DISTRO_PRETTY="${PRETTY_NAME}"
    elif [[ -f /etc/lsb-release ]]; then
        . /etc/lsb-release
        DISTRO=$(echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]')
        DISTRO_VERSION="$DISTRIB_RELEASE"
        DISTRO_PRETTY="$DISTRIB_DESCRIPTION"
    else
        log_error "Cannot detect Linux distribution"
        return 1
    fi
    
    log_info "Distribution: $DISTRO_PRETTY"
    log_debug "ID: $DISTRO, Version: $DISTRO_VERSION"
}

# Normalize distro to family
normalize_distro() {
    case "$DISTRO" in
        ubuntu|debian)
            DISTRO_FAMILY="debian"
            ;;
        fedora|rhel|centos|rocky|alma)
            DISTRO_FAMILY="fedora"
            ;;
        arch|manjaro|endeavouros)
            DISTRO_FAMILY="arch"
            ;;
        *)
            log_warn "Unknown distro family for $DISTRO, assuming generic"
            DISTRO_FAMILY="generic"
            ;;
    esac
    
    log_debug "Distro family: $DISTRO_FAMILY"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo "Try: sudo $0"
        exit 1
    fi
}

# Check kernel headers
check_kernel_headers() {
    log_section "Checking Kernel Headers"
    
    if [[ ! -d "$KERNEL_BUILD_DIR" ]]; then
        log_error "Kernel build directory not found: $KERNEL_BUILD_DIR"
        log_info "Please install kernel headers for $KERNEL_RELEASE"
        
        case "$DISTRO_FAMILY" in
            debian)
                log_info "Install with: apt install linux-headers-$KERNEL_RELEASE"
                ;;
            fedora)
                log_info "Install with: dnf install kernel-devel-$KERNEL_RELEASE"
                ;;
            arch)
                log_info "Install with: pacman -S linux-headers"
                ;;
        esac
        
        return 1
    fi
    
    log_info "Found kernel build dir: $KERNEL_BUILD_DIR"
}

# Install package dependencies
install_dependencies() {
    log_section "Installing Dependencies"
    
    local pkgs_debian=("build-essential" "dkms" "git" "libusb-1.0-0-dev")
    local pkgs_fedora=("gcc" "kernel-devel" "dkms" "git" "libusb-devel")
    local pkgs_arch=("gcc" "dkms" "git" "libusb")
    
    case "$DISTRO_FAMILY" in
        debian)
            log_info "Installing packages via apt..."
            if [[ $DRY_RUN -eq 1 ]]; then
                log_debug "Would run: apt update && apt install -y ${pkgs_debian[@]}"
            else
                apt-get update
                apt-get install -y "${pkgs_debian[@]}"
            fi
            ;;
        fedora)
            log_info "Installing packages via dnf..."
            if [[ $DRY_RUN -eq 1 ]]; then
                log_debug "Would run: dnf install -y ${pkgs_fedora[@]}"
            else
                dnf install -y "${pkgs_fedora[@]}"
            fi
            ;;
        arch)
            log_info "Installing packages via pacman..."
            if [[ $DRY_RUN -eq 1 ]]; then
                log_debug "Would run: pacman -S --noconfirm ${pkgs_arch[@]}"
            else
                pacman -S --noconfirm "${pkgs_arch[@]}"
            fi
            ;;
        generic)
            log_warn "Generic distro detected - please install manually:"
            echo "  - Build tools (gcc, make, etc.)"
            echo "  - Kernel development headers"
            echo "  - DKMS (optional but recommended)"
            echo "  - Git"
            echo "  - libusb development library"
            ;;
    esac
    
    log_info "Dependencies installation complete"
}

# Detect kernel features
detect_kernel_features() {
    log_section "Detecting Kernel Features"
    
    local detect_script="$PROJECT_ROOT/scripts/detect-kernel-features.sh"
    
    if [[ ! -f "$detect_script" ]]; then
        log_error "Feature detection script not found: $detect_script"
        return 1
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "Would run: $detect_script '$KERNEL_BUILD_DIR' '$KERNEL_SOURCE_DIR'"
        return 0
    fi
    
    chmod +x "$detect_script"
    
    # Run detection and capture output
    OUTPUT_FORMAT=bash source <("$detect_script" "$KERNEL_BUILD_DIR" "$KERNEL_SOURCE_DIR")
    
    log_info "Kernel feature detection complete"
    log_debug "HID_PARSE_REPORT_EXPORTED: ${CONFIG_HID_PARSE_REPORT_EXPORTED:-0}"
    log_debug "MFD_CORE_AVAILABLE: ${CONFIG_MFD_CORE_AVAILABLE:-0}"
    log_debug "DKMS_CAPABLE: ${CONFIG_DKMS_CAPABLE:-0}"
}

# Build and install DKMS drivers
install_dkms_drivers() {
    log_section "Installing DKMS Drivers"
    
    if [[ $SKIP_DKMS -eq 1 ]]; then
        log_warn "Skipping DKMS driver installation (--skip-dkms)"
        return 0
    fi
    
    if ! command -v dkms >/dev/null 2>&1; then
        log_warn "DKMS not found - drivers will not rebuild on kernel updates"
        log_info "Consider installing DKMS: apt install dkms (Debian) or dnf install dkms (Fedora)"
    fi
    
    # Install apple-ibridge
    install_dkms_driver "apple-ibridge"
    
    # Install apple-touchbar
    install_dkms_driver "apple-touchbar"
    
    log_info "DKMS drivers installed successfully"
}

# Helper to install single DKMS driver
install_dkms_driver() {
    local driver_name="$1"
    local driver_dir="$PROJECT_ROOT/drivers/$driver_name"
    
    if [[ ! -d "$driver_dir" ]]; then
        log_error "Driver directory not found: $driver_dir"
        return 1
    fi
    
    log_info "Installing $driver_name..."
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "Would copy $driver_dir to /usr/src/"
        log_debug "Would run: dkms add -m $driver_name -v <version>"
        log_debug "Would run: dkms build -m $driver_name -v <version>"
        log_debug "Would run: dkms install -m $driver_name -v <version>"
        return 0
    fi
    
    # Copy driver to /usr/src for DKMS
    local driver_version="1.0"
    local dkms_dest="/usr/src/$driver_name-$driver_version"
    
    if [[ -d "$dkms_dest" ]]; then
        log_warn "DKMS driver already exists, removing: $dkms_dest"
        rm -rf "$dkms_dest"
    fi
    
    mkdir -p "$dkms_dest"
    cp -r "$driver_dir"/* "$dkms_dest/"
    
    # Add to DKMS
    dkms add -m "$driver_name" -v "$driver_version" 2>/dev/null || log_debug "Driver already added to DKMS"
    
    # Build
    log_info "Building $driver_name..."
    if ! dkms build -m "$driver_name" -v "$driver_version" -k "$KERNEL_RELEASE"; then
        log_error "Failed to build $driver_name"
        return 1
    fi
    
    # Install
    log_info "Installing $driver_name..."
    if ! dkms install -m "$driver_name" -v "$driver_version" -k "$KERNEL_RELEASE"; then
        log_error "Failed to install $driver_name"
        return 1
    fi
    
    log_info "✓ $driver_name installed"
}

# Install userspace tools
install_userspace() {
    log_section "Installing Userspace Tools"
    
    if [[ $SKIP_USERSPACE -eq 1 ]]; then
        log_warn "Skipping userspace installation (--skip-userspace)"
        return 0
    fi
    
    # TODO: Build and install tiny-dfr
    log_warn "Userspace tools installation not yet implemented"
}

# Setup udev rules
setup_udev() {
    log_section "Setting Up udev Rules"
    
    local udev_file="/etc/udev/rules.d/99-apple-touchbar.rules"
    local udev_src="$PROJECT_ROOT/udev/99-apple-touchbar.rules"
    
    if [[ ! -f "$udev_src" ]]; then
        log_warn "udev rules file not found: $udev_src"
        return 1
    fi
    
    log_info "Installing udev rules..."
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "Would copy $udev_src to $udev_file"
        log_debug "Would run: udevadm control --reload"
        return 0
    fi
    
    cp "$udev_src" "$udev_file"
    chmod 644 "$udev_file"
    
    udevadm control --reload
    udevadm trigger
    
    log_info "udev rules installed"
}

# Display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Apple T1 Touch Bar support installer for Linux

OPTIONS:
    -h, --help              Show this help message
    -n, --dry-run          Don't actually make changes, just show what would be done
    -v, --verbose          Verbose output for debugging
    --skip-dkms            Skip DKMS driver installation
    --skip-userspace       Skip userspace tools installation
    --install-dir DIR      Installation directory (default: /usr/local)

EXAMPLES:
    # Standard installation
    sudo $0
    
    # Dry run to see what would be done
    sudo $0 --dry-run
    
    # With verbose output for debugging
    sudo $0 --verbose

REQUIREMENTS:
    - Root/sudo access
    - Linux kernel 4.15+
    - Kernel headers installed
    - GCC and build tools

SUPPORTED DISTRIBUTIONS:
    - Debian/Ubuntu
    - Fedora/RHEL/CentOS
    - Arch Linux
    - Generic Linux distributions

For more information, see README.md
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=1
                log_warn "DRY RUN MODE - no changes will be made"
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            --skip-dkms)
                SKIP_DKMS=1
                shift
                ;;
            --skip-userspace)
                SKIP_USERSPACE=1
                shift
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main installation flow
main() {
    log_info "Apple T1 Touch Bar Installation for Linux"
    echo ""
    
    parse_args "$@"
    
    check_root
    detect_distro
    normalize_distro
    check_kernel_headers
    install_dependencies
    detect_kernel_features
    install_dkms_drivers
    install_userspace
    setup_udev
    
    log_section "Installation Complete!"
    log_info "Apple T1 Touch Bar support has been installed"
    echo ""
    log_info "Next steps:"
    echo "  1. Load the drivers: sudo modprobe apple_ibridge"
    echo "  2. Load the drivers: sudo modprobe apple_touchbar"
    echo "  3. Or reboot to load automatically"
    echo ""
    log_info "To verify installation:"
    echo "  - Check kernel log: dmesg | grep -i apple"
    echo "  - Check loaded modules: lsmod | grep apple"
    echo "  - Check udev rules: cat /etc/udev/rules.d/99-apple-touchbar.rules"
}

main "$@"
