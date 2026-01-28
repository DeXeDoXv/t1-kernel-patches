#!/bin/bash
#
# install-touchbar.sh - Universal Apple T1 Touch Bar installer for Linux
#
# Orchestrates complete installation including:
# - Kernel patch application with adaptive strategies
# - DKMS driver compilation for any kernel version
# - Userspace tiny-dfr daemon build and installation
# - systemd service integration
# - udev permissions configuration
#
# Usage: sudo bash install-touchbar.sh [OPTIONS]
#
# SPDX-License-Identifier: GPL-2.0

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly KERNEL_RELEASE="$(uname -r)"
readonly KERNEL_VERSION_MAJOR="${KERNEL_RELEASE%%.*}"
readonly KERNEL_VERSION_MINOR="${KERNEL_RELEASE#*.}"
readonly KERNEL_VERSION_MINOR="${KERNEL_VERSION_MINOR%%.*}"

# ============================================================================
# COLORS
# ============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ============================================================================
# VARIABLES
# ============================================================================

DISTRO=""
DISTRO_FAMILY=""
DRY_RUN=0
VERBOSE=0
SKIP_KERNEL=0
SKIP_DRIVERS=0
SKIP_DAEMON=0
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" >&2
}

log_debug() {
    [[ $VERBOSE -eq 1 ]] && echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

log_section() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
    echo ""
}


die() {
    log_error "$*"
    exit 1
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Use: sudo $0"
    fi
}

detect_distro() {
    log_section "Detecting Distribution"
    
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO="${ID}"
        log_info "Distribution: $PRETTY_NAME"
    else
        die "Cannot detect Linux distribution"
    fi
    
    # Normalize to distro family
    case "$DISTRO" in
        ubuntu|debian)
            DISTRO_FAMILY="debian"
            log_debug "Detected Debian-based distribution"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            DISTRO_FAMILY="fedora"
            log_debug "Detected Fedora/RHEL-based distribution"
            ;;
        arch|manjaro|endeavouros)
            DISTRO_FAMILY="arch"
            log_debug "Detected Arch-based distribution"
            ;;
        *)
            die "Unsupported distribution: $DISTRO"
            ;;
    esac
}

# ============================================================================
# DEPENDENCY INSTALLATION
# ============================================================================

install_dependencies() {
    log_section "Installing Build Dependencies"
    
    case "$DISTRO_FAMILY" in
        debian)
            log_info "Installing Debian/Ubuntu dependencies..."
            apt-get update || die "Failed to update package lists"
            apt-get install -y \
                build-essential \
                linux-headers-"${KERNEL_RELEASE}" \
                dkms \
                git \
                patch \
                curl \
                || die "Failed to install Debian dependencies"
            ;;
        fedora)
            log_info "Installing Fedora/RHEL dependencies..."
            dnf install -y \
                gcc \
                kernel-devel-"${KERNEL_RELEASE}" \
                kernel-headers-"${KERNEL_RELEASE}" \
                dkms \
                git \
                patch \
                curl \
                || die "Failed to install Fedora dependencies"
            ;;
        arch)
            log_info "Installing Arch dependencies..."
            pacman -Sy --noconfirm \
                base-devel \
                linux-headers \
                dkms \
                git \
                patch \
                curl \
                || die "Failed to install Arch dependencies"
            ;;
    esac
    
    log_info "Dependencies installed successfully"
}

# ============================================================================
# KERNEL PATCH APPLICATION
# ============================================================================

apply_kernel_patches() {
    log_section "Applying Kernel Patches"
    
    if [[ $SKIP_KERNEL -eq 1 ]]; then
        log_warn "Skipping kernel patches (--skip-kernel)"
        return 0
    fi
    
    local patch_count=0
    local failed=0
    
    for patch_file in "${PROJECT_ROOT}"/*.patch; do
        [[ -f "$patch_file" ]] || continue
        
        local patch_name=$(basename "$patch_file")
        log_info "Processing patch: $patch_name"
        
        # Strategy 1: Strict application (clean match)
        if patch --dry-run -p1 < "$patch_file" >/dev/null 2>&1; then
            log_debug "Patch applies cleanly with -p1"
            if [[ $DRY_RUN -eq 0 ]]; then
                patch -p1 < "$patch_file" || {
                    log_warn "Patch application failed"
                    ((failed++))
                }
            else
                log_debug "DRY RUN: Would apply patch"
            fi
            ((patch_count++))
            continue
        fi
        
        # Strategy 2: Fuzzy matching (reduced context)
        if patch --dry-run -p1 -l < "$patch_file" >/dev/null 2>&1; then
            log_debug "Patch applies with fuzzy matching (-l)"
            if [[ $DRY_RUN -eq 0 ]]; then
                patch -p1 -l < "$patch_file" || {
                    log_warn "Fuzzy patch application failed"
                    ((failed++))
                }
            else
                log_debug "DRY RUN: Would apply patch with fuzzy matching"
            fi
            ((patch_count++))
            continue
        fi
        
        # Strategy 3: Three-way merge
        if patch --dry-run -p1 --3way < "$patch_file" >/dev/null 2>&1; then
            log_debug "Patch applies with 3-way merge"
            if [[ $DRY_RUN -eq 0 ]]; then
                patch -p1 --3way < "$patch_file" || {
                    log_warn "3-way merge patch application failed"
                    ((failed++))
                }
            else
                log_debug "DRY RUN: Would apply patch with 3-way merge"
            fi
            ((patch_count++))
            continue
        fi
        
        log_warn "Patch did not apply with any strategy: $patch_name"
        ((failed++))
    done
    
    log_info "Applied $patch_count patches ($failed failed)"
    
    if [[ $failed -gt 0 ]]; then
        log_warn "Some patches failed to apply. This may be normal for kernel $KERNEL_RELEASE"
    fi
}

# ============================================================================
# DRIVER INSTALLATION
# ============================================================================

install_drivers_dkms() {
    log_section "Installing Drivers via DKMS"
    
    if [[ $SKIP_DRIVERS -eq 1 ]]; then
        log_warn "Skipping driver installation (--skip-drivers)"
        return 0
    fi
    
    # Check if DKMS is available
    if ! command -v dkms &>/dev/null; then
        log_error "DKMS not found. Install with:"
        case "$DISTRO_FAMILY" in
            debian) echo "  sudo apt-get install dkms" ;;
            fedora) echo "  sudo dnf install dkms" ;;
            arch) echo "  sudo pacman -S dkms" ;;
        esac
        return 1
    fi
    
    # Install apple-ibridge driver
    log_info "Installing apple-ibridge driver..."
    local ibridge_src="${PROJECT_ROOT}/apple-ibridge"
    if [[ -d "$ibridge_src" ]]; then
        _install_single_driver "apple-ibridge" "$ibridge_src"
    else
        log_warn "apple-ibridge source not found"
    fi
    
    # Install apple-touchbar driver
    log_info "Installing apple-touchbar driver..."
    local touchbar_src="${PROJECT_ROOT}/apple-touchbar"
    if [[ -d "$touchbar_src" ]]; then
        _install_single_driver "apple-touchbar" "$touchbar_src"
    else
        log_warn "apple-touchbar source not found"
    fi
    
    log_info "Drivers installed successfully"
}

_install_single_driver() {
    local driver_name="$1"
    local driver_src="$2"
    local version="1.0"
    local dkms_dir="/usr/src/${driver_name}-${version}"
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "DRY RUN: Would install $driver_name to $dkms_dir"
        return 0
    fi
    
    # Remove if already installed
    if dkms status "$driver_name/$version" &>/dev/null; then
        log_debug "Removing existing $driver_name installation"
        dkms remove -m "$driver_name" -v "$version" --all 2>/dev/null || true
    fi
    
    # Create DKMS directory and copy source
    mkdir -p "$dkms_dir"
    cp -r "$driver_src"/* "$dkms_dir/"
    
    # Register and build
    dkms add -m "$driver_name" -v "$version" || die "Failed to add $driver_name to DKMS"
    dkms build -m "$driver_name" -v "$version" || die "Failed to build $driver_name"
    dkms install -m "$driver_name" -v "$version" || die "Failed to install $driver_name"
    
    log_info "Successfully installed $driver_name"
}

# ============================================================================
# USERSPACE DAEMON INSTALLATION
# ============================================================================

install_daemon() {
    log_section "Installing tiny-dfr Daemon"
    
    if [[ $SKIP_DAEMON -eq 1 ]]; then
        log_warn "Skipping daemon installation (--skip-daemon)"
        return 0
    fi
    
    local daemon_src="${PROJECT_ROOT}/third_party/tiny-dfr"
    
    if [[ ! -d "$daemon_src" ]]; then
        die "tiny-dfr source not found: $daemon_src"
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "DRY RUN: Would build and install tiny-dfr"
        return 0
    fi
    
    log_info "Building tiny-dfr..."
    (cd "$daemon_src" && make clean && make -j"$(nproc)") || die "Failed to build tiny-dfr"
    
    log_info "Installing tiny-dfr..."
    (cd "$daemon_src" && make PREFIX="$INSTALL_PREFIX" install) || die "Failed to install tiny-dfr"
    
    log_info "tiny-dfr installed to $INSTALL_PREFIX/bin/tiny-dfr"
}

# ============================================================================
# CONFIGURATION FILE INSTALLATION
# ============================================================================

install_udev_rules() {
    log_section "Installing udev Rules"
    
    local src_rules="${PROJECT_ROOT}/udev/99-apple-touchbar.rules"
    local dst_rules="/etc/udev/rules.d/99-apple-touchbar.rules"
    
    if [[ ! -f "$src_rules" ]]; then
        log_warn "udev rules not found: $src_rules"
        return 0
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "DRY RUN: Would install udev rules to $dst_rules"
        return 0
    fi
    
    cp "$src_rules" "$dst_rules"
    chmod 644 "$dst_rules"
    
    # Reload udev rules
    if command -v udevadm &>/dev/null; then
        udevadm control --reload
        udevadm trigger
        log_info "udev rules installed and reloaded"
    else
        log_info "udev rules installed (udevadm not found, manual reload may be needed)"
    fi
}

install_systemd_service() {
    log_section "Installing systemd Service"
    
    local src_service="${PROJECT_ROOT}/systemd/touchbar.service"
    local dst_service="/etc/systemd/system/touchbar.service"
    
    if [[ ! -f "$src_service" ]]; then
        log_warn "systemd service not found: $src_service"
        return 0
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_debug "DRY RUN: Would install systemd service to $dst_service"
        return 0
    fi
    
    cp "$src_service" "$dst_service"
    chmod 644 "$dst_service"
    
    # Enable and start service
    if command -v systemctl &>/dev/null; then
        systemctl daemon-reload
        systemctl enable touchbar.service
        systemctl restart touchbar.service
        log_info "systemd service installed and enabled"
    else
        log_info "systemd service installed (systemctl not found)"
    fi
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_installation() {
    log_section "Verifying Installation"
    
    local issues=0
    
    # Check kernel modules
    if lsmod | grep -q apple_ibridge; then
        log_info "apple_ibridge kernel module loaded"
    else
        log_warn "apple_ibridge kernel module not loaded"
        ((issues++))
    fi
    
    if lsmod | grep -q apple_ib_tb; then
        log_info "apple_ib_tb kernel module loaded"
    else
        log_warn "apple_ib_tb kernel module not loaded"
        ((issues++))
    fi
    
    # Check daemon binary
    if [[ -x "$INSTALL_PREFIX/bin/tiny-dfr" ]]; then
        log_info "tiny-dfr daemon installed: $INSTALL_PREFIX/bin/tiny-dfr"
    else
        log_warn "tiny-dfr daemon not found or not executable"
        ((issues++))
    fi
    
    # Check systemd service
    if [[ -f /etc/systemd/system/touchbar.service ]]; then
        log_info "systemd service installed"
        if systemctl is-enabled touchbar.service &>/dev/null; then
            log_info "systemd service enabled"
        else
            log_warn "systemd service not enabled"
        fi
    else
        log_warn "systemd service not installed"
        ((issues++))
    fi
    
    # Check udev rules
    if [[ -f /etc/udev/rules.d/99-apple-touchbar.rules ]]; then
        log_info "udev rules installed"
    else
        log_warn "udev rules not installed"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_info "All components verified successfully"
    else
        log_warn "Some components missing or not loaded ($issues issues)"
    fi
}

# ============================================================================
# HELP AND USAGE
# ============================================================================

show_help() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Install Apple T1 Touch Bar support for Linux on MacBook Pro 2016-2017

OPTIONS:
    -h, --help              Show this help message
    -n, --dry-run          Don't make actual changes, just show what would happen
    -v, --verbose          Enable verbose debugging output
    --skip-kernel          Skip kernel patch application
    --skip-drivers         Skip driver installation
    --skip-daemon          Skip daemon installation
    --prefix DIR           Installation prefix (default: /usr/local)

EXAMPLES:
    # Full installation
    sudo $0
    
    # Dry run to see what would be done
    sudo $0 --dry-run
    
    # With verbose output
    sudo $0 --verbose
    
    # Custom installation prefix
    sudo $0 --prefix /opt

REQUIREMENTS:
    - Root/sudo access
    - Linux kernel 4.15+
    - Kernel headers installed
    - Build tools (gcc, make, patch)
    - DKMS (for automatic kernel updates)

SUPPORTED DISTRIBUTIONS:
    - Ubuntu 18.04+
    - Debian 9+
    - Fedora 29+
    - RHEL 8+
    - Arch Linux
    - Manjaro
    - EndeavourOS

TROUBLESHOOTING:
    1. Check kernel version: uname -r
    2. Verify modules loaded: lsmod | grep apple
    3. Check daemon status: systemctl status touchbar
    4. View daemon logs: journalctl -u touchbar -n 50

For more information, see: https://github.com/DeXeDoXv/t1-kernel-patches

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_section "Apple T1 Touch Bar Installer"
    log_info "Kernel version: $KERNEL_RELEASE"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=1
                log_warn "DRY RUN MODE - no actual changes will be made"
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                log_debug "Verbose mode enabled"
                shift
                ;;
            --skip-kernel)
                SKIP_KERNEL=1
                shift
                ;;
            --skip-drivers)
                SKIP_DRIVERS=1
                shift
                ;;
            --skip-daemon)
                SKIP_DAEMON=1
                shift
                ;;
            --prefix)
                INSTALL_PREFIX="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Sanity checks
    check_root
    detect_distro
    
    # Main installation sequence
    install_dependencies
    apply_kernel_patches
    install_drivers_dkms
    install_daemon
    install_udev_rules
    install_systemd_service
    verify_installation
    
    log_section "Installation Complete"
    echo ""
    log_info "Apple T1 Touch Bar support has been successfully installed!"
    echo ""
    echo "Next steps:"
    echo "  1. Reboot to ensure all modules are loaded:"
    echo "     sudo reboot"
    echo ""
    echo "  2. After reboot, verify the installation:"
    echo "     lsmod | grep apple"
    echo "     systemctl status touchbar"
    echo ""
    echo "  3. Check the daemon logs:"
    echo "     journalctl -u touchbar -n 50 -f"
    echo ""
    echo "Known limitations:"
    echo "  - Touch Bar displays function keys only (no custom app rendering yet)"
    echo "  - Ambient Light Sensor available via HID but not integrated with backlight"
    echo "  - Touch ID / Secure Enclave not implemented"
    echo ""
    echo "For troubleshooting, visit: https://github.com/DeXeDoXv/t1-kernel-patches"
}

main "$@"
