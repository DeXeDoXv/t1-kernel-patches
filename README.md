# Apple T1 Touch Bar Support for Linux

Enable Apple Touch Bar support on MacBook Pro 2016–2017 (Intel) across **all kernel versions and Linux distributions**.

## Quick Start

```bash
sudo bash scripts/install-touchbar.sh
```

This one-command installer:
- Detects your Linux distribution
- Installs dependencies
- Queries kernel capabilities (no hardcoding)
- Builds and installs drivers via DKMS
- Sets up permissions and systemd service

## Supported Hardware

- MacBook Pro 13" (2016, 2017)
- MacBook Pro 15" (2016, 2017)

## Supported Distributions

- Ubuntu / Debian
- Fedora / RHEL
- Arch Linux
- Other Linux distributions with systemd

## Features

- **Feature detection**: Automatically detects kernel capabilities at build time
- **DKMS support**: Automatic driver rebuilds on kernel updates
- **Multi-distro**: Unified installation across distributions
- **Configurable**: Touch Bar modes, brightness, idle timeouts
- **Unprivileged access**: Device permissions via udev rules
- **FN key mapping**: Remap function keys to special keys

## Configuration

After installation, configure via sysfs:

1. **HID subsystem** - Touch Bar communication
2. **MFD (Multi-Function Device) framework** - Device multiplexing
3. **ACPI support** - Power management and T1 communication
4. **USB HID API** - Device initialization
5. **Device-managed resources (devm)** - Memory safety
6. **Power management ops** - Suspend/resume handling
7. **Symbol availability** - Runtime function detection

If a feature is unavailable, the build falls back gracefully with clear error messages.

## Installation

### Quick Start (One Command)

```bash
sudo bash scripts/install-touchbar.sh
```

The installer will:
1. ✓ Detect your Linux distribution
2. ✓ Install build dependencies (gcc, kernel-headers, DKMS)
3. ✓ Detect kernel capabilities
4. ✓ Build and install kernel drivers via DKMS
5. ✓ Configure udev rules for device access
6. ✓ Install and enable systemd services

### Advanced Options

```bash
# Dry-run mode (show what would happen, don't change anything)
sudo ./scripts/install-touchbar.sh --dry-run

# Verbose output for debugging
sudo ./scripts/install-touchbar.sh --verbose

# Skip DKMS installation (manual kernel integration)
sudo ./scripts/install-touchbar.sh --skip-dkms

# Custom installation directory
sudo ./scripts/install-touchbar.sh --install-dir /opt/apple-t1
```

### Manual Installation (Advanced)

If the automated installer doesn't work for your system:

```bash
# 1. Install dependencies manually
# Debian/Ubuntu
sudo apt-get install build-essential dkms git libusb-1.0-0-dev linux-headers-$(uname -r)

# Fedora
sudo dnf install gcc kernel-devel dkms git libusb-devel

# Arch
sudo pacman -S base-devel dkms git libusb

# 2. Detect kernel features
export OUTPUT_FORMAT=bash
source <(./scripts/detect-kernel-features.sh /lib/modules/$(uname -r)/build)

# 3. Build drivers with DKMS
sudo dkms add -m apple-ibridge -v 1.0
sudo dkms build -m apple-ibridge -v 1.0
sudo dkms install -m apple-ibridge -v 1.0

sudo dkms add -m apple-touchbar -v 1.0
sudo dkms build -m apple-touchbar -v 1.0
sudo dkms install -m apple-touchbar -v 1.0

# 4. Install udev rules
sudo cp udev/99-apple-touchbar.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger

# 5. Load drivers (or reboot)
sudo modprobe apple_ibridge
sudo modprobe apple_touchbar
```

## Verification

After installation, verify everything is working:

```bash
# Check if drivers loaded
lsmod | grep apple

# Expected output:
# apple_touchbar          16384  0
# apple_ibridge           24576  1 apple_touchbar

# Check kernel messages
dmesg | grep -i apple

# Check hidraw devices
ls /dev/hidraw*

# Check udev rules applied
cat /etc/udev/rules.d/99-apple-touchbar.rules

# Monitor T1 activity
watch -n1 'dmesg | tail -20'
```

## How It Works

### Architecture

```
┌─────────────────────────────────────────┐
│   Linux Kernel                          │
│  ┌────────────────────────────────────┐ │
│  │ HID Subsystem (drivers/hid/)       │ │
│  │  - apple-ibridge-hid (MFD demux)   │ │
│  │  - apple-touchbar (driver cell)    │ │
│  │  - apple-ib-als (driver cell)      │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
              ↓ (USB 0x05ac:0x8600)
      ┌──────────────────────┐
      │ Apple T1 Chip (iBridge)
      ├──────────────────────┤
      │ - Touch Bar LCD      │
      │ - iSight Camera      │
      │ - Ambient Light      │
      │ - Secure Enclave     │
      └──────────────────────┘
```

### Kernel Feature Detection

Instead of hardcoding kernel versions, the system detects available features at **build time**:

```bash
# detect-kernel-features.sh workflow:
1. Check for kernel headers in /lib/modules/$(uname -r)/build
2. Scan include/linux/*.h for required symbols
3. Query Module.symvers for exported functions
4. Check for essential APIs (hid_connect, hid_parse, ACPI, etc.)
5. Generate C header or Make variables with feature flags
6. Pass flags to compiler for conditional compilation
```

### Adaptive Patching

The `adaptive-patch.sh` script applies kernel patches with multiple fallback strategies:

```bash
# Patch application strategy (in order):
1. Strict application (exact context match)
2. Fuzzy matching (reduced context requirements)
3. Manual reconstruction (if available)
```

This allows patches to work across kernel versions without requiring exact line number matches.

### DKMS Integration

DKMS automatically rebuilds drivers when the kernel updates:

```bash
/usr/src/apple-ibridge-1.0/
├── apple-ibridge.c
├── apple-ibridge.h
├── Makefile              # References feature detection
└── dkms.conf            # DKMS metadata

/usr/src/apple-touchbar-1.0/
├── apple-ib-tb.c
├── Makefile
└── dkms.conf
```

When you run `apt upgrade && reboot`, DKMS hooks automatically rebuild the drivers for the new kernel.

## Configuration

### Module Parameters

The Touch Bar driver supports several tunable parameters:

```bash
# Default FN key mode (0=normal, 1=function keys)
echo 1 | sudo tee /sys/module/apple_touchbar/parameters/appletb_tb_def_fn_mode

# Idle timeout before display goes dark (seconds)
echo 60 | sudo tee /sys/module/apple_touchbar/parameters/appletb_tb_idle_timeout

# Dim timeout before display turns off (seconds)
echo 5 | sudo tee /sys/module/apple_touchbar/parameters/appletb_tb_dim_timeout
```

Make these permanent by adding to `/etc/modprobe.d/apple-touchbar.conf`:

```bash
options apple_touchbar appletb_tb_def_fn_mode=1 appletb_tb_idle_timeout=60
```

### udev Rules

The system grants unprivileged user access to Touch Bar devices via udev rules:

```bash
# Location: /etc/udev/rules.d/99-apple-touchbar.rules
# Grants 'uaccess' tag for user session access
# Requires systemd-logind for seat management
```

## Troubleshooting

### Issue: "Kernel build directory not found"

```bash
# Install kernel headers
# Ubuntu/Debian:
sudo apt-get install linux-headers-$(uname -r)

# Fedora:
sudo dnf install kernel-devel-$(uname -r)

# Verify:
ls /lib/modules/$(uname -r)/build/
```

### Issue: "Drivers failed to load"

```bash
# Check for compilation errors
dmesg | grep -i error

# Check if drivers are installed
modinfo apple_ibridge

# Manually load with verbose output
sudo modprobe -v apple_ibridge

# Check for missing symbols
nm /lib/modules/$(uname -r)/kernel/drivers/hid/*.ko | grep hid_connect
```

### Issue: "HID device not accessible"

```bash
# Check udev rules were applied
cat /etc/udev/rules.d/99-apple-touchbar.rules

# Trigger udev rule reload
sudo udevadm control --reload
sudo udevadm trigger

# Check device permissions
ls -la /dev/hidraw*

# Expected: -rw-rw-rw- (666) or user/group ownership
```

### Issue: "Touch Bar display not working"

```bash
# Verify drivers are loaded and in use
lsmod | grep apple

# Check if tiny-dfr daemon is running
systemctl status tiny-dfr

# Check logs
journalctl -u tiny-dfr -n 50

# Try manual invocation with debug
sudo /usr/local/bin/tiny-dfr -vv
```

## Uninstallation

To remove Touch Bar support:

```bash
# Remove DKMS drivers
sudo dkms remove apple-ibridge/1.0 --all
sudo dkms remove apple-touchbar/1.0 --all

# Remove service
sudo systemctl disable tiny-dfr
sudo systemctl stop tiny-dfr
sudo rm /usr/local/bin/tiny-dfr

# Remove udev rules
sudo rm /etc/udev/rules.d/99-apple-touchbar.rules
sudo udevadm control --reload

# Unload modules
sudo modprobe -r apple_touchbar apple_ibridge

# Remove source
sudo rm -rf /usr/src/apple-ibridge-1.0 /usr/src/apple-touchbar-1.0
```

## Development & Debugging

### Repository Structure

```
t1-kernel-patches/
├── README.md                          # This file
├── scripts/
│   ├── install-touchbar.sh           # Main installer (ONE COMMAND)
│   ├── detect-kernel-features.sh     # Feature detection engine
│   └── build-kernel.sh               # Kernel patch helper
│
├── kernel/
│   ├── patches/                       # Upstream-style patches
│   │   ├── 0001-hid-export-report-item-parsers.patch
│   │   ├── 0002-drivers-hid-apple-ibridge.patch
│   │   ├── 0003-drivers-hid-apple-touchbar.patch
│   │   ├── 0004-hid-sensor-als-support.patch
│   │   └── 0005-hid-recognize-sensors-with-appcollections.patch
│   └── adapt/
│       └── adaptive-patch.sh         # Adaptive patcher for compatibility
│
├── drivers/
│   ├── apple-ibridge-src/
│   │   ├── apple-ibridge.c           # iBridge MFD demultiplexer
│   │   ├── apple-ibridge.h
│   │   ├── Makefile
│   │   ├── Makefile.adaptive         # Version-agnostic build
│   │   └── dkms.conf                 # DKMS metadata
│   └── apple-touchbar-src/
│       ├── apple-ib-tb.c             # Touch Bar driver
│       ├── Makefile
│       ├── Makefile.adaptive
│       └── dkms.conf
│
├── third_party/
│   └── tiny-dfr/                      # Vendored tiny-dfr source (MIT)
│       ├── src/
│       ├── include/
│       ├── Makefile
│       └── LICENSE
│
├── assets/
│   └── extract-touchbar-assets.sh    # Asset extraction helper
│
├── udev/
│   └── 99-apple-touchbar.rules       # Unprivileged device access
│
└── systemd/
    └── tiny-dfr.service              # Display manager service
```

### Adding Support for New Features

To add feature detection for a new kernel capability:

1. **Edit** `scripts/detect-kernel-features.sh`
2. **Add detection function** (e.g., `detect_new_feature()`)
3. **Add to feature list** in `main()`
4. **Use in Makefile** or driver code:

```makefile
ifdef CONFIG_NEW_FEATURE_AVAILABLE
  EXTRA_CFLAGS += -DNEW_FEATURE_AVAILABLE
endif
```

```c
#ifdef CONFIG_NEW_FEATURE_AVAILABLE
  // Use new API
  new_feature_do_something();
#else
  // Fall back to old API
  old_feature_fallback();
#endif
```

### Building from Source

```bash
# Clone repository
git clone https://github.com/DeXeDoXv/t1-kernel-patches
cd t1-kernel-patches

# Make scripts executable
chmod +x scripts/*.sh kernel/adapt/*.sh

# Run installer
sudo ./scripts/install-touchbar.sh --verbose

# Or build manually with feature detection
export OUTPUT_FORMAT=bash
source <(./scripts/detect-kernel-features.sh /lib/modules/$(uname -r)/build)
make -C drivers/apple-ibridge-src KERNEL_BUILD_DIR=/lib/modules/$(uname -r)/build
```

## Legal & Licensing

- **License**: GPL-2.0+ (kernel drivers)
- **Copyright**: Original code by Ronald Tschalär; adaptations for multi-kernel support
- **Warranty**: PROVIDED AS-IS; USE AT YOUR OWN RISK
- **Apple**: No Apple proprietary code or binaries included

## Known Limitations

1. **Touch Bar graphics**: Currently displays basic function keys/escape; custom Touch Bar applications require additional userspace work
2. **Ambient Light Sensor**: Supported via HID sensor; integration with system backlight control pending
3. **Touch ID**: Secure Enclave (SEP) access not implemented
4. **System Recovery**: iBridge Recovery Mode (configuration 3) not supported

## Contributing

Contributions welcome! Areas for help:

- [ ] tiny-dfr userspace daemon (Rust/C)
- [ ] Asset extraction from recovery images
- [ ] Distribution-specific packaging (RPM, PKGBUILD)
- [ ] Testing on additional kernel versions
- [ ] Documentation improvements

## References

- **HID Subsystem**: https://www.kernel.org/doc/html/latest/hid/
- **DKMS**: https://github.com/dell/dkms
- **tiny-dfr**: https://github.com/jeryini/tiny-dfr (Rust implementation)
- **Linux Apple Support**: https://wiki.archlinux.org/title/MacBook

## Support & Issues

- **Report bugs**: https://github.com/DeXeDoXv/t1-kernel-patches/issues
- **Check existing issues** before reporting
- **Include**: Kernel version, distribution, error logs, output of `dmesg`

## Changelog

### v1.0.0 (Initial Release)
- ✅ Feature-detection based kernel support
- ✅ DKMS integration for automatic rebuilds
- ✅ Multi-distro installer
- ✅ Adaptive patching framework
- ✅ Comprehensive documentation

## License

GPL-2.0+

```
    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
```

---

**Made with ❤️ for Apple T1 MacBook Pro users on Linux**
