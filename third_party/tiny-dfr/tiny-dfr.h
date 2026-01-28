/*
 * tiny-dfr.h - Touch Bar display definitions
 * SPDX-License-Identifier: MIT
 */

#ifndef TINY_DFR_H
#define TINY_DFR_H

#include <stdint.h>

/* Apple USB identifiers */
#define APPLE_VENDOR_ID 0x05ac
#define T1_IBRIDGE_ID 0x8600

/* HID report constants */
#define TOUCHBAR_REPORT_ID 0xB0
#define TOUCHBAR_REPORT_LENGTH 81

/* Display modes */
enum dfr_mode {
    DFR_MODE_OFF = 0,
    DFR_MODE_CLASSIC = 1,
    DFR_MODE_EXPANDED = 2,
};

#endif /* TINY_DFR_H */
