# Apple T1 Touch Bar Support for Linux

Enable Apple Touch Bar support on MacBook Pro 2016–2017 across **all Linux distributions and kernel versions** (4.15+, optimized for 6.x).

## Quick Start

```bash
sudo bash scripts/install-touchbar.sh
sudo reboot
```

That's it! The installer handles everything:
- Distro detection (Ubuntu/Debian, Fedora, Arch, generic)
- Dependency installation via native package managers
- Dynamic kernel patch application with fallback strategies
- DKMS driver compilation for automatic kernel update support
- Userspace daemon (tiny-dfr) compilation and installation
- systemd service setup for autostart
- udev permission rules for unprivileged access

## Supported Hardware

- MacBook Pro 13" (2016, 2017)
- MacBook Pro 15" (2016, 2017)

## Supported Distributions

| Distro | Family | Package Manager | Status |
|--------|--------|-----------------|--------|
| Ubuntu 18.04+ | Debian | apt | ✓ Tested |
| Debian 9+ | Debian | apt | ✓ Tested |
| Fedora 29+ | RHEL | dnf | ✓ Tested |
| RHEL 8+ | RHEL | dnf | ✓ Tested |
| Arch Linux | Arch | pacman | ✓ Tested |
| Manjaro | Arch | pacman | ✓ Tested |
| EndeavourOS | Arch | pacman | ✓ Tested |

## Supported Kernels

- Minimum: Linux 4.15+ (HID subsystem maturity)
- Optimized: Linux 6.x series
- Dynamic patching: Automatically adapts to any kernel version
- DKMS auto-rebuild: Drivers automatically recompile on kernel updates

## How It Works

The installation orchestrates multiple components working together:

```
Hardware (Apple T1 USB device with Touch Bar)
         ↓
    Linux HID Subsystem (/dev/hidraw*)
         ↓
    apple-ibridge (kernel driver - MFD demultiplexer)
         ↓
    apple-touchbar (kernel driver - device binding)
         ↓
    tiny-dfr (userspace daemon - HID communication)
         ↓
    systemd Service (autostart at boot)
```

**Key Features:**
- **Feature detection**: Automatically detects kernel capabilities at build time (no hardcoding)
- **DKMS**: Drivers auto-rebuild on kernel updates
- **Adaptive patching**: Patches work across multiple kernel versions with fallback strategies
- **Modular design**: Separate drivers for iBridge (MFD demux) and Touch Bar
- **Security hardened**: systemd service with strict sandboxing

## Installation Options

```bash
# Standard installation with automatic detection
sudo bash scripts/install-touchbar.sh

# Dry run to see what would be done
sudo bash scripts/install-touchbar.sh --dry-run

# Verbose output for debugging
sudo bash scripts/install-touchbar.sh --verbose

# Skip specific components
sudo bash scripts/install-touchbar.sh --skip-kernel    # Don't patch kernel
sudo bash scripts/install-touchbar.sh --skip-drivers   # Don't compile drivers
sudo bash scripts/install-touchbar.sh --skip-daemon    # Don't build daemon

# Custom installation prefix
sudo bash scripts/install-touchbar.sh --prefix /opt
```

## Verification

### Check Installation Success

```bash
# Verify kernel modules are loaded
lsmod | grep apple

# Check for Touch Bar HID device
ls -la /dev/hidraw*

# Check systemd service status
systemctl status touchbar.service

# View daemon logs
journalctl -u touchbar -n 50

# Check kernel messages
dmesg | grep -i apple
```

Expected output:
```
$ lsmod | grep apple
apple_ib_tb             16384  0
apple_ibridge           28672  1 apple_ib_tb

$ systemctl status touchbar.service
● touchbar.service - Apple T1 Touch Bar Display Function Row daemon
     Loaded: loaded (/etc/systemd/system/touchbar.service; enabled; ...)
     Active: active (running) since Mon 2024-01-15 10:30:45 UTC; 2h 5min ago
  Main PID: 513 (tiny-dfr)
```

## Troubleshooting

### Issue: Kernel headers not found

```bash
# Ubuntu/Debian
sudo apt-get install linux-headers-$(uname -r)

# Fedora
sudo dnf install kernel-devel-$(uname -r) kernel-headers-$(uname -r)

# Arch
sudo pacman -S linux-headers
```

Re-run the installer afterward:
```bash
sudo bash scripts/install-touchbar.sh
```

### Issue: Drivers not loading

```bash
# Check if modules exist
ls /lib/modules/$(uname -r)/extra/ | grep apple

# Manually load
sudo modprobe apple_ibridge
sudo modprobe apple_ib_tb

# Check kernel log
dmesg | grep -A5 -B5 apple
```

### Issue: Touch Bar not responding

```bash
# Verify daemon is running
systemctl status touchbar.service

# Check udev rules
cat /etc/udev/rules.d/99-apple-touchbar.rules

# Reload udev and trigger device rules
sudo udevadm control --reload
sudo udevadm trigger

# Restart daemon
sudo systemctl restart touchbar.service
```

### Issue: Permission denied on /dev/hidraw*

```bash
# Check device permissions
ls -la /dev/hidraw*

# Verify udev rules
ls -la /etc/udev/rules.d/99-apple-touchbar.rules

# Reload udev
sudo udevadm control --reload
sudo udevadm trigger

# Reboot if still not working
sudo reboot
```

### Getting Help

When reporting bugs, please include:
- Linux distribution and version
- Kernel version: `uname -r`
- Kernel messages: `dmesg | grep -i apple`
- Service status: `systemctl status touchbar.service`
- Service logs: `journalctl -u touchbar -n 50`

## Known Limitations

- **Touch Bar UI**: Displays basic function keys (F1-F12, brightness, volume)
  - No custom per-app Touch Bar rendering yet
  - Gesture support planned but not implemented
- **Ambient Light Sensor**: Available via HID but not integrated with system backlight control
- **Touch ID / Secure Enclave**: Not implemented (requires additional hardware support)
- **Recovery Mode**: macOS recovery partition not accessible from Linux
- **Apple Silicon**: This is Intel T1 only (Apple Silicon uses different architecture)

## Architecture & Design

### Components

- **apple-ibridge**: Multi-function device demultiplexer for all T1 functions
- **apple-touchbar**: Touch Bar device binding to HID subsystem
- **tiny-dfr**: Asahi Linux userspace daemon for display control
- **systemd Service**: Automatic daemon startup with security hardening
- **udev Rules**: Device permission management and discovery

### Dynamic Kernel Patching

Patches are applied using an adaptive strategy:

1. **Strict matching** (exact context): Works on original kernel source
2. **Fuzzy matching** (-l flag): Works with minor whitespace changes
3. **Three-way merge** (--3way): Works with significant modifications
4. **Automatic fallback**: If one strategy fails, tries the next

This ensures compatibility across kernel versions without hardcoding specific versions.

### DKMS Integration

Drivers automatically rebuild when:
- New kernel is installed
- System is rebooted (DKMS service detects change)
- Manual rebuild: `dkms install -m apple-ibridge -v 1.0 -k $(uname -r)`

## License

- **Kernel Drivers**: GPL-2.0+ (Linux kernel source)
- **Userspace Daemon**: MIT (tiny-dfr from Asahi Linux)
- **Patches & Config**: GPL-2.0+

**No Apple proprietary binaries, frameworks, or closed-source code are redistributed.**

All original source code follows Linux kernel licensing standards.

## Building from Source

For development:

```bash
# Build drivers
cd apple-ibridge && make && cd ..
cd apple-touchbar && make && cd ..

# Build daemon
cd third_party/tiny-dfr && make && cd ..

# Run tests (if available)
cd scripts && bash test-build.sh && cd ..
```

## References

- **Original Touch Bar Driver**: https://github.com/roadrunner2/macbook-touch-bar-driver
- **Linux HID Subsystem**: https://www.kernel.org/doc/html/latest/hid/
- **DKMS**: https://github.com/dell/dkms
- **tiny-dfr (Asahi Linux)**: https://github.com/asahi-explore/tiny-dfr
- **Linux Kernel Docs**: https://www.kernel.org/doc/

## Contributing

Contributions welcome! Areas needing work:

- [ ] Apple Silicon support (different architecture)
- [ ] Custom Touch Bar per-app rendering
- [ ] Ambient Light Sensor integration
- [ ] Better error recovery
- [ ] More distro testing
- [ ] Performance optimization

## Support & Issues

- **Issue Tracker**: https://github.com/DeXeDoXv/t1-kernel-patches/issues
- **When reporting bugs, please include**:
  - Linux distribution and version
  - Kernel version (`uname -r`)
  - `dmesg | grep -i apple` output
  - `systemctl status touchbar.service` output
  - Steps to reproduce

## Acknowledgments

- Linux kernel developers
- Asahi Linux project (tiny-dfr daemon)
- roadrunner2 (original macbook-touch-bar-driver)
- Community contributions and testing
