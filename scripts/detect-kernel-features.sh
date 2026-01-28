#!/bin/bash
#
# detect-kernel-features.sh - Runtime kernel feature detection for Apple T1 support
#
# This script detects kernel capabilities and API availability without hardcoding
# kernel versions or line numbers. It enables adaptive compilation across multiple
# kernel versions.
#
# SPDX-License-Identifier: GPL-2.0

set -e

KERNEL_BUILD_DIR="${1:-.}"
KERNEL_SOURCE_DIR="${2:-}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Feature tracking
declare -A FEATURES
declare -a FEATURE_NAMES

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if a file exists in kernel tree
kernel_file_exists() {
    local file="$1"
    [[ -f "$KERNEL_BUILD_DIR/$file" ]] || [[ -f "$KERNEL_SOURCE_DIR/$file" ]]
}

# Search for symbol in kernel headers
find_symbol() {
    local symbol="$1"
    local headers_dir="$KERNEL_BUILD_DIR/include"
    
    if [[ ! -d "$headers_dir" ]]; then
        headers_dir="$KERNEL_SOURCE_DIR/include"
    fi
    
    grep -r "^\s*[a-zA-Z_].*\b$symbol\b" "$headers_dir" 2>/dev/null | head -1
}

# Check if symbol is exported
check_symbol_exported() {
    local symbol="$1"
    local modules_symvers="$KERNEL_BUILD_DIR/Module.symvers"
    
    if [[ ! -f "$modules_symvers" ]] && [[ -f "$KERNEL_SOURCE_DIR/Module.symvers" ]]; then
        modules_symvers="$KERNEL_SOURCE_DIR/Module.symvers"
    fi
    
    if [[ -f "$modules_symvers" ]]; then
        grep -q "\s$symbol\s" "$modules_symvers" 2>/dev/null
        return $?
    fi
    
    return 1
}

# Feature detection functions

detect_hid_parse_report() {
    # Newer kernels export hid_parse_report; older ones don't
    if check_symbol_exported "hid_parse_report"; then
        FEATURES["HID_PARSE_REPORT_EXPORTED"]=1
        log_info "hid_parse_report is exported"
    else
        FEATURES["HID_PARSE_REPORT_EXPORTED"]=0
        log_warn "hid_parse_report not exported - will use fallback"
    fi
    FEATURE_NAMES+=("HID_PARSE_REPORT_EXPORTED")
}

detect_hid_connect() {
    # hid_connect API variations
    if find_symbol "hid_connect" >/dev/null; then
        FEATURES["HID_CONNECT_AVAILABLE"]=1
        log_info "hid_connect is available"
    else
        FEATURES["HID_CONNECT_AVAILABLE"]=0
        log_error "hid_connect not found - compilation may fail"
    fi
    FEATURE_NAMES+=("HID_CONNECT_AVAILABLE")
}

detect_mfd_core() {
    # MFD (Multi-Function Device) support
    if kernel_file_exists "include/linux/mfd/core.h"; then
        FEATURES["MFD_CORE_AVAILABLE"]=1
        log_info "MFD core framework available"
    else
        FEATURES["MFD_CORE_AVAILABLE"]=0
        log_error "MFD core not available"
    fi
    FEATURE_NAMES+=("MFD_CORE_AVAILABLE")
}

detect_acpi_support() {
    # ACPI device support
    if kernel_file_exists "include/linux/acpi.h"; then
        FEATURES["ACPI_AVAILABLE"]=1
        log_info "ACPI support available"
    else
        FEATURES["ACPI_AVAILABLE"]=0
        log_warn "ACPI not available"
    fi
    FEATURE_NAMES+=("ACPI_AVAILABLE")
}

detect_devm_managed() {
    # Device-managed (devm) resources
    if find_symbol "devm_kzalloc" >/dev/null; then
        FEATURES["DEVM_MANAGED_AVAILABLE"]=1
        log_info "Device-managed resources (devm) available"
    else
        FEATURES["DEVM_MANAGED_AVAILABLE"]=0
        log_warn "Device-managed resources not available"
    fi
    FEATURE_NAMES+=("DEVM_MANAGED_AVAILABLE")
}

detect_hidraw_device() {
    # hidraw device support
    if kernel_file_exists "include/linux/hidraw.h"; then
        FEATURES["HIDRAW_AVAILABLE"]=1
        log_info "hidraw device support available"
    else
        FEATURES["HIDRAW_AVAILABLE"]=0
        log_warn "hidraw not available"
    fi
    FEATURE_NAMES+=("HIDRAW_AVAILABLE")
}

detect_usb_hid() {
    # USB HID API
    if kernel_file_exists "include/linux/usb/ch9.h"; then
        FEATURES["USB_HID_AVAILABLE"]=1
        log_info "USB HID support available"
    else
        FEATURES["USB_HID_AVAILABLE"]=0
        log_error "USB HID support not available"
    fi
    FEATURE_NAMES+=("USB_HID_AVAILABLE")
}

detect_pm_ops() {
    # Power management operations
    if find_symbol "dev_pm_ops" >/dev/null; then
        FEATURES["PM_OPS_AVAILABLE"]=1
        log_info "Power management ops available"
    else
        FEATURES["PM_OPS_AVAILABLE"]=0
        log_warn "Power management ops not available"
    fi
    FEATURE_NAMES+=("PM_OPS_AVAILABLE")
}

detect_kernel_version() {
    # Extract kernel version
    local version_file="$KERNEL_BUILD_DIR/include/generated/uapi/linux/version.h"
    if [[ ! -f "$version_file" ]] && [[ -f "$KERNEL_SOURCE_DIR/include/generated/uapi/linux/version.h" ]]; then
        version_file="$KERNEL_SOURCE_DIR/include/generated/uapi/linux/version.h"
    fi
    
    if [[ -f "$version_file" ]]; then
        local version=$(grep "LINUX_VERSION_CODE" "$version_file" | awk '{print $3}')
        FEATURES["KERNEL_VERSION"]=$version
        log_info "Kernel version code: $version"
    else
        log_warn "Could not determine kernel version"
        FEATURES["KERNEL_VERSION"]=0
    fi
    FEATURE_NAMES+=("KERNEL_VERSION")
}

detect_dkms_capable() {
    # Check if kernel can be used with DKMS
    local has_headers=0
    local has_build=0
    
    [[ -d "$KERNEL_BUILD_DIR/include" ]] && has_headers=1
    [[ -d "$KERNEL_BUILD_DIR/arch" ]] && has_build=1
    
    if [[ $has_headers -eq 1 ]] && [[ $has_build -eq 1 ]]; then
        FEATURES["DKMS_CAPABLE"]=1
        log_info "Kernel is DKMS capable"
    else
        FEATURES["DKMS_CAPABLE"]=0
        log_error "Kernel missing headers or build tree"
    fi
    FEATURE_NAMES+=("DKMS_CAPABLE")
}

detect_hid_sensor_als() {
    # HID ambient light sensor support
    if kernel_file_exists "drivers/iio/light/hid-sensor-als.c"; then
        FEATURES["HID_SENSOR_ALS_AVAILABLE"]=1
        log_info "HID sensor ALS support available"
    else
        FEATURES["HID_SENSOR_ALS_AVAILABLE"]=0
        log_warn "HID sensor ALS support not available"
    fi
    FEATURE_NAMES+=("HID_SENSOR_ALS_AVAILABLE")
}

detect_hid_apple_tb() {
    # Check if Apple Touch Bar already in kernel
    if kernel_file_exists "drivers/hid/hid-apple-touchbar.c"; then
        FEATURES["APPLE_TB_BUILTIN"]=1
        log_warn "Apple Touch Bar driver already in kernel"
    else
        FEATURES["APPLE_TB_BUILTIN"]=0
        log_info "Apple Touch Bar driver not in kernel - will build externally"
    fi
    FEATURE_NAMES+=("APPLE_TB_BUILTIN")
}

# Output formats

output_c_header() {
    echo "/* Auto-generated kernel feature detection header */"
    echo "/* DO NOT EDIT - generated by detect-kernel-features.sh */"
    echo ""
    echo "#ifndef _KERNEL_FEATURES_H"
    echo "#define _KERNEL_FEATURES_H"
    echo ""
    
    for feature in "${FEATURE_NAMES[@]}"; do
        local value=${FEATURES[$feature]}
        echo "#define CONFIG_$feature $value"
    done
    
    echo ""
    echo "#endif /* _KERNEL_FEATURES_H */"
}

output_make_vars() {
    echo "# Auto-generated Makefile variables"
    echo "# DO NOT EDIT - generated by detect-kernel-features.sh"
    echo ""
    
    for feature in "${FEATURE_NAMES[@]}"; do
        local value=${FEATURES[$feature]}
        echo "CONFIG_$feature := $value"
    done
}

output_json() {
    echo "{"
    local first=1
    for feature in "${FEATURE_NAMES[@]}"; do
        local value=${FEATURES[$feature]}
        if [[ $first -eq 0 ]]; then
            echo ","
        fi
        echo -n "  \"$feature\": $value"
        first=0
    done
    echo ""
    echo "}"
}

output_bash() {
    echo "#!/bin/bash"
    echo "# Auto-generated bash variables"
    echo "# DO NOT EDIT - generated by detect-kernel-features.sh"
    echo ""
    
    for feature in "${FEATURE_NAMES[@]}"; do
        local value=${FEATURES[$feature]}
        echo "CONFIG_$feature=$value"
    done
}

# Main execution

main() {
    log_info "Detecting kernel features..."
    log_info "Kernel build dir: $KERNEL_BUILD_DIR"
    
    if [[ -n "$KERNEL_SOURCE_DIR" ]]; then
        log_info "Kernel source dir: $KERNEL_SOURCE_DIR"
    fi
    
    # Run all detectors
    detect_kernel_version
    detect_dkms_capable
    detect_acpi_support
    detect_hid_connect
    detect_hid_parse_report
    detect_mfd_core
    detect_devm_managed
    detect_hidraw_device
    detect_usb_hid
    detect_pm_ops
    detect_hid_sensor_als
    detect_hid_apple_tb
    
    log_info "Feature detection complete"
    
    # Output results
    case "${OUTPUT_FORMAT:-c}" in
        c|header)
            output_c_header
            ;;
        make|makefile)
            output_make_vars
            ;;
        json)
            output_json
            ;;
        bash)
            output_bash
            ;;
        *)
            log_error "Unknown output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

main "$@"
