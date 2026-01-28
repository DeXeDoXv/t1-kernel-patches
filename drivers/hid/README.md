# DKMS Driver Folders

This directory contains the DKMS driver folders cloned from the roadrunner2/macbook12-spi-driver repository.

## Directory Structure

### apple-ibridge/
The Apple iBridge driver provides support for the T1 chip found in modern MacBook Pro models. This driver:
- Acts as a demultiplexer for HID drivers
- Manages the Touch Bar and Ambient Light Sensor (ALS) interfaces
- Handles power management for the iBridge chip
- Exports utility functions for finding HID fields and managing drivers

**Key files:**
- `apple-ibridge.c` - Main driver implementation
- `apple-ibridge.h` - Header file with public API exports
- `Makefile` - Build configuration

### apple-touchbar/
The Apple Touch Bar driver provides support for the touch bar found on MacBook Pro models (13-inch and 14-15 inch from late 2016 onwards, and newer models). This driver:
- Manages touch bar functionality and modes
- Handles key remapping for function keys
- Implements display brightness control
- Provides device attributes for idle/dim timeouts and function key mode

**Key files:**
- `apple-ib-tb.c` - Main touch bar driver implementation
- `Makefile` - Build configuration

## Usage

These drivers are designed to work with the Linux kernel on MacBook Pro models with T1 chip.

### Building
```
make -C drivers/hid/apple-ibridge
make -C drivers/hid/apple-touchbar
```

### Installation with DKMS
```
sudo dkms install -m apple_ibridge -v 0.1
sudo dkms install -m apple_ib_tb -v 0.1
```

## Dependencies

Both drivers depend on:
- Linux HID subsystem
- USB HID support
- ACPI support (for iBridge power management)

The Touch Bar driver additionally depends on:
- Input subsystem
- Workqueue
- Sysfs support

## Module Parameters

### apple_ibridge
None currently.

### apple_ib_tb
- `appletb_tb_def_fn_mode` - Default Function key mode (0=normal, 1=F-keys)
- `appletb_tb_idle_timeout` - Idle timeout in seconds (default: 60)
- `appletb_tb_dim_timeout` - Dim timeout in seconds (default: 5)

## Source

These drivers were cloned from: https://github.com/roadrunner2/macbook12-spi-driver
