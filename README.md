# Apple T1 Touch Bar Support for Linux

Enable Apple Touch Bar support on MacBook Pro 2016–2017 across **all Linux distributions and kernel versions**.

## Installation

```bash
sudo bash scripts/install-touchbar.sh
```

One-command installer that detects your distro, installs dependencies, builds drivers via DKMS, and configures permissions.

## Supported Hardware

- MacBook Pro 13" (2016, 2017)
- MacBook Pro 15" (2016, 2017)

## Supported Distributions

- Ubuntu / Debian
- Fedora / RHEL / CentOS
- Arch Linux
- Generic Linux (with systemd)

## How It Works

- **Feature detection**: Automatically detects kernel capabilities at build time (no hardcoding)
- **DKMS**: Drivers auto-rebuild on kernel updates
- **Adaptive patching**: Patches work across multiple kernel versions
- **Modular design**: Separate drivers for iBridge (MFD demux) and Touch Bar

## Troubleshooting

### Kernel headers not found
```bash
# Ubuntu/Debian
sudo apt-get install linux-headers-$(uname -r)

# Fedora
sudo dnf install kernel-devel-$(uname -r)
```

### Verify installation
```bash
lsmod | grep apple
dmesg | grep -i apple
```

### Check systemd service
```bash
systemctl status tiny-dfr
journalctl -u tiny-dfr -n 50
```

## Known Limitations

- Touch Bar displays basic function keys only (no custom apps yet)
- Ambient Light Sensor (ALS) available via HID but not integrated with system backlight
- Touch ID / Secure Enclave not implemented
- Recovery mode not supported

## License

GPL-2.0+ (drivers); MIT (tiny-dfr userspace)

All source code is original or properly licensed. **No Apple proprietary binaries or frameworks are redistributed.**

## References

- Original work: https://github.com/roadrunner2/macbook-touch-bar-driver
- Linux kernel HID: https://www.kernel.org/doc/html/latest/hid/
- DKMS: https://github.com/dell/dkms
- tiny-dfr: https://github.com/jeryini/tiny-dfr

## Support

- Issues: https://github.com/DeXeDoXv/t1-kernel-patches/issues
- When reporting bugs, include: kernel version, distro, `dmesg` output
