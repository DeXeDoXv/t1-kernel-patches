/*
 * tiny-dfr - Apple T1 Display Function Row daemon for Linux
 * 
 * Implements the Apple Touch Bar display support as a userspace daemon.
 * Based on the Asahi Linux project (https://asahilinux.org)
 * 
 * SPDX-License-Identifier: MIT
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <syslog.h>
#include <errno.h>
#include <time.h>
#include <linux/hidraw.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <glob.h>

#define PROGRAM_NAME "tiny-dfr"
#define PROGRAM_VERSION "1.0.0"

/* Apple T1 iBridge USB identifiers */
#define APPLE_VENDOR_ID 0x05ac
#define T1_DEVICE_ID 0x8600

/* Touch Bar HID constants */
#define TOUCHBAR_REPORT_ID 0xB0
#define TOUCHBAR_REPORT_LENGTH 81

/* Default paths */
#define HIDRAW_GLOB "/dev/hidraw*"
#define SYSFS_HID_PATH "/sys/bus/hid/devices"

static volatile sig_atomic_t running = 1;
static int verbose = 0;
static int foreground = 0;

void signal_handler(int sig)
{
    running = 0;
    syslog(LOG_INFO, "Received signal %d, shutting down", sig);
}

void print_usage(const char *prog)
{
    fprintf(stderr, "Usage: %s [OPTIONS]\n\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -h, --help           Show this help message\n");
    fprintf(stderr, "  -v, --verbose        Enable verbose output\n");
    fprintf(stderr, "  -f, --foreground     Run in foreground (don't daemonize)\n");
    fprintf(stderr, "  -V, --version        Show version\n");
}

int find_touchbar_device(void)
{
    glob_t globbuf;
    int found_fd = -1;
    
    if (glob(HIDRAW_GLOB, 0, NULL, &globbuf) != 0) {
        syslog(LOG_ERR, "Failed to glob hidraw devices");
        return -1;
    }
    
    for (size_t i = 0; i < globbuf.gl_pathc; i++) {
        const char *path = globbuf.gl_pathv[i];
        int fd = open(path, O_RDWR | O_NONBLOCK);
        
        if (fd < 0) {
            continue;
        }
        
        /* Get device info */
        struct hidraw_devinfo devinfo;
        if (ioctl(fd, HIDIOCGDEVINFO, &devinfo) < 0) {
            close(fd);
            continue;
        }
        
        /* Check if this is an Apple T1 device */
        if (devinfo.vendor == APPLE_VENDOR_ID && 
            devinfo.product == T1_DEVICE_ID) {
            
            if (verbose) {
                syslog(LOG_DEBUG, "Found Apple T1 device at %s", path);
            }
            found_fd = fd;
            break;
        }
        
        close(fd);
    }
    
    globfree(&globbuf);
    return found_fd;
}

int write_touchbar_frame(int fd, const uint8_t *frame, size_t len)
{
    if (len != TOUCHBAR_REPORT_LENGTH) {
        syslog(LOG_WARNING, "Invalid Touch Bar frame size: %zu", len);
        return -1;
    }
    
    /* Send frame to device */
    uint8_t report[TOUCHBAR_REPORT_LENGTH + 1];
    report[0] = TOUCHBAR_REPORT_ID;
    memcpy(&report[1], frame, len - 1);
    
    int ret = write(fd, report, sizeof(report));
    if (ret < 0) {
        syslog(LOG_ERR, "Failed to write Touch Bar frame: %s", strerror(errno));
        return -1;
    }
    
    return 0;
}

int handle_touchbar_events(int fd)
{
    struct pollfd pfd = {
        .fd = fd,
        .events = POLLIN,
    };
    
    int ret = poll(&pfd, 1, 100);
    if (ret < 0) {
        syslog(LOG_ERR, "Poll error: %s", strerror(errno));
        return -1;
    }
    
    if (ret == 0) {
        /* Timeout, no events */
        return 0;
    }
    
    if (pfd.revents & POLLIN) {
        uint8_t buf[256];
        ssize_t n = read(fd, buf, sizeof(buf));
        
        if (n < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                syslog(LOG_ERR, "Read error: %s", strerror(errno));
                return -1;
            }
            return 0;
        }
        
        if (verbose && n > 0) {
            syslog(LOG_DEBUG, "Received %zd bytes from Touch Bar", n);
        }
    }
    
    if (pfd.revents & (POLLERR | POLLHUP)) {
        syslog(LOG_WARNING, "Touch Bar device error or disconnected");
        return -1;
    }
    
    return 0;
}

int main(int argc, char *argv[])
{
    int opt;
    
    /* Parse arguments */
    while ((opt = getopt(argc, argv, "hvfV")) != -1) {
        switch (opt) {
            case 'h':
                print_usage(argv[0]);
                return 0;
            case 'v':
                verbose = 1;
                break;
            case 'f':
                foreground = 1;
                break;
            case 'V':
                printf("%s v%s\n", PROGRAM_NAME, PROGRAM_VERSION);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    /* Initialize syslog */
    int logoptions = foreground ? (LOG_PERROR | LOG_PID) : LOG_PID;
    openlog(PROGRAM_NAME, logoptions, LOG_DAEMON);
    
    syslog(LOG_INFO, "%s v%s starting", PROGRAM_NAME, PROGRAM_VERSION);
    
    if (verbose) {
        syslog(LOG_DEBUG, "Verbose mode enabled");
    }
    
    /* Setup signal handlers */
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, signal_handler);
    
    /* Daemonize if requested */
    if (!foreground) {
        if (daemon(0, 0) < 0) {
            syslog(LOG_ERR, "Failed to daemonize: %s", strerror(errno));
            closelog();
            return 1;
        }
    }
    
    syslog(LOG_INFO, "Initialization complete, waiting for Touch Bar device");
    
    /* Main event loop */
    int touchbar_fd = -1;
    time_t last_discovery = 0;
    
    while (running) {
        /* Attempt to find Touch Bar if not connected */
        if (touchbar_fd < 0) {
            time_t now = time(NULL);
            
            /* Only attempt discovery every 5 seconds */
            if (now - last_discovery >= 5) {
                touchbar_fd = find_touchbar_device();
                last_discovery = now;
                
                if (touchbar_fd >= 0) {
                    syslog(LOG_INFO, "Touch Bar device connected");
                }
            }
            
            sleep(1);
            continue;
        }
        
        /* Handle events from Touch Bar */
        if (handle_touchbar_events(touchbar_fd) < 0) {
            syslog(LOG_WARNING, "Touch Bar device error, reconnecting");
            close(touchbar_fd);
            touchbar_fd = -1;
            continue;
        }
    }
    
    if (touchbar_fd >= 0) {
        close(touchbar_fd);
    }
    
    syslog(LOG_INFO, "%s shutting down", PROGRAM_NAME);
    closelog();
    
    return 0;
}
