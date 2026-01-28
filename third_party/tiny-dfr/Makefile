CC ?= gcc
CFLAGS ?= -Wall -Wextra -O2 -fPIC
LDFLAGS ?= 
LIBS ?= 

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin

TARGET = tiny-dfr
SOURCES = tiny-dfr.c
OBJECTS = $(SOURCES:.c=.o)

.PHONY: all install uninstall clean

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

install: $(TARGET)
	install -D -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)

clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: all install uninstall clean
