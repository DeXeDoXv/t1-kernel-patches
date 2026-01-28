#!/bin/bash
#
# adaptive-patch.sh - Apply patches with fallback for multiple kernel versions
#
# This script attempts to apply patches using multiple strategies:
# 1. Direct patch application
# 2. Fuzzy matching (patch with -l flag)
# 3. Manual context reconstruction
#
# SPDX-License-Identifier: GPL-2.0

set -e

PATCH_FILE="${1:?ERROR: patch file required}"
TARGET_DIR="${2:-.}"
KERNEL_BUILD_DIR="${3:-.}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

# Check if patch applies cleanly
try_patch() {
    local patch_args="$1"
    
    log_debug "Trying patch with args: $patch_args"
    
    # Use --dry-run first to test
    if patch -p1 --dry-run $patch_args < "$PATCH_FILE" >/dev/null 2>&1; then
        log_info "Patch dry-run successful"
        # Now apply for real
        patch -p1 $patch_args < "$PATCH_FILE"
        return 0
    fi
    
    return 1
}

# Strategy 1: Strict patch application
attempt_strict() {
    log_info "Attempting strict patch application..."
    if try_patch ""; then
        return 0
    fi
    return 1
}

# Strategy 2: Fuzzy matching with reduced context
attempt_fuzzy() {
    log_info "Attempting fuzzy patch application (reduced context)..."
    if try_patch "-l"; then
        return 0
    fi
    return 1
}

# Strategy 3: Extract and manually apply
attempt_manual() {
    log_info "Attempting manual patch reconstruction..."
    
    local tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT
    
    # Parse patch file for hunks
    local file_section=0
    local current_file=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^---\ (.+) ]]; then
            current_file="${BASH_REMATCH[1]}"
            log_debug "Processing file: $current_file"
        elif [[ "$line" =~ ^@@\ -([0-9]+) ]]; then
            # Found hunk marker
            file_section=$((file_section + 1))
        fi
    done < "$PATCH_FILE"
    
    log_warn "Manual reconstruction not yet implemented"
    return 1
}

# Analyze patch file for issues
analyze_patch() {
    log_info "Analyzing patch file: $PATCH_FILE"
    
    # Count hunks
    local hunk_count=$(grep -c "^@@" "$PATCH_FILE" || echo 0)
    log_info "Number of hunks: $hunk_count"
    
    # Extract affected files
    local files=$(grep "^---" "$PATCH_FILE" | sed 's/^--- //' | cut -d' ' -f1)
    log_info "Affected files:"
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        echo "  - $file"
    done <<< "$files"
    
    # Check if files exist
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ ! -f "$TARGET_DIR/$file" ]]; then
            log_warn "File not found: $TARGET_DIR/$file"
        fi
    done <<< "$files"
}

# Main execution
main() {
    cd "$TARGET_DIR"
    
    log_info "Adaptive patch application"
    log_info "Patch: $PATCH_FILE"
    log_info "Target: $TARGET_DIR"
    
    # Analyze first
    analyze_patch
    
    # Try strategies in order
    if attempt_strict; then
        log_info "✓ Patch applied successfully (strict)"
        return 0
    fi
    
    if attempt_fuzzy; then
        log_info "✓ Patch applied successfully (fuzzy)"
        return 0
    fi
    
    if attempt_manual; then
        log_info "✓ Patch applied successfully (manual)"
        return 0
    fi
    
    log_error "✗ Failed to apply patch with any strategy"
    log_error "Please review patch file and kernel compatibility"
    return 1
}

main "$@"
