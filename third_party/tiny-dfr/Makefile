# Makefile for tiny-dfr userspace daemon
# SPDX-License-Identifier: MIT

CC ?= gcc
CFLAGS ?= -Wall -Wextra -O2
PREFIX ?= /usr/local

# Sources
SOURCES = tiny-dfr.c
OBJECTS = $(SOURCES:.c=.o)
TARGET = tiny-dfr

# Targets
all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

install: $(TARGET)
	install -D -m 755 $(TARGET) $(PREFIX)/bin/$(TARGET)

uninstall:
	rm -f $(PREFIX)/bin/$(TARGET)

clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: all install uninstall clean
