include $(GNUSTEP_MAKEFILES)/common.make

# Require GNUstep development libraries (build will fail with clear message if missing)
GNUSUPPORT := $(shell pkg-config --exists gnustep-base && pkg-config --exists gnustep-gui && echo yes || echo no)
ifeq ($(GNUSUPPORT),no)
$(error GNUstep development libraries not found. Install packages providing pkg-config entries 'gnustep-base' and 'gnustep-gui')
endif

APP_NAME = PtouchUtility
PtouchUtility_RESOURCE_FILES = PtouchUtilityInfo.plist
PtouchUtility_OBJC_FILES = src-gui/PtouchUtility.m src/ptouch-render-gnustep.m
PtouchUtility_C_FILES = src/libptouch.c src/ptouch-render.c

# Include directories
ADDITIONAL_INCLUDE_DIRS += -Iinclude

# Library dependencies (GNUstep is required)
ADDITIONAL_GUI_LIBS += $(shell pkg-config --libs libusb-1.0 gnustep-base) -lgnustep-gui
ADDITIONAL_CPPFLAGS += $(shell pkg-config --cflags libusb-1.0 gnustep-base) -DUSING_CMAKE=0



# Ensure tool links against gnustep-gui which may not provide a pkg-config entry on some systems
ptouch_utility_LDFLAGS += -lgnustep-gui
ptouch-utility_LDFLAGS += -lgnustep-gui
# Include directories
ADDITIONAL_INCLUDE_DIRS += -Iinclude

# Library dependencies
ADDITIONAL_GUI_LIBS += $(shell pkg-config --libs libusb-1.0 gnustep-base gnustep-gui 2>/dev/null)
ADDITIONAL_CPPFLAGS += $(shell pkg-config --cflags libusb-1.0 gnustep-base gnustep-gui 2>/dev/null) -DUSING_CMAKE=0

include $(GNUSTEP_MAKEFILES)/application.make

# Command-line tool: ptouch-utility
TOOL_NAME = ptouch-utility
# gnustep-make expects instance variables named for the tool; some systems
# use the hyphenated name (ptouch-utility) whereas others use underscores.
# Define both forms to be safe.
ptouch_utility_C_FILES = src/ptouch-utility.c src/libptouch.c src/ptouch-render.c
ptouch_utility_OBJC_FILES = src/ptouch-render-gnustep.m
ptouch_utility_LDFLAGS += $(shell pkg-config --libs libusb-1.0 gnustep-base gnustep-gui)
ptouch_utility_CFLAGS += $(shell pkg-config --cflags libusb-1.0 gnustep-base gnustep-gui)

ptouch-utility_C_FILES = $(ptouch_utility_C_FILES)
ptouch-utility_OBJC_FILES = $(ptouch_utility_OBJC_FILES)
ptouch-utility_LDFLAGS = $(ptouch_utility_LDFLAGS)
ptouch-utility_CFLAGS = $(ptouch_utility_CFLAGS)

include $(GNUSTEP_MAKEFILES)/tool.make

# Small test utility to exercise rendering
TOOL_NAME = render-test
render_test_C_FILES = src/libptouch.c src/ptouch-render.c
render_test_OBJC_FILES = src/render_test.m src/ptouch-render-gnustep.m
render-test_C_FILES = $(render_test_C_FILES)
render-test_OBJC_FILES = $(render_test_OBJC_FILES)
render_test_LDFLAGS += -lgnustep-gui
render_test_LDFLAGS += -lusb-1.0
render-test_LDFLAGS = $(render_test_LDFLAGS)
render_test_CFLAGS = $(render_test_CFLAGS)

# Workaround: gnustep-make sometimes does not create object directories for
# tools whose names contain a hyphen.  Ensure the subdirectories exist so
# compilation of render-test (and any other hyphenated tools) succeeds.
# This runs when the Makefile is parsed, before any build steps.
$(shell mkdir -p obj/render-test.obj/src)

include $(GNUSTEP_MAKEFILES)/tool.make

# Status monitoring utility to observe printer status bytes and report diffs
TOOL_NAME = status-monitor
status_monitor_C_FILES = src/libptouch.c src/status-monitor.c
status-monitor_C_FILES = $(status_monitor_C_FILES)
status_monitor_LDFLAGS += -lusb-1.0
status-monitor_LDFLAGS = $(status_monitor_LDFLAGS)
status-monitor_CFLAGS = $(status_monitor_CFLAGS)

# Workaround for hyphenated tool names as explained above
$(shell mkdir -p obj/status-monitor.obj/src)

include $(GNUSTEP_MAKEFILES)/tool.make

# Local install hook: install udev rules on Linux and devd rule on FreeBSD
install:: install-local
install-local:
	@if [ -d /etc/udev/rules.d ]; then \
		install -m 644 udev/20-usb-ptouch-permissions.rules /etc/udev/rules.d/; \
		if command -v udevadm >/dev/null 2>&1; then udevadm control --reload-rules >/dev/null 2>&1 || true; fi; \
	fi
	@if [ "`uname -s`" = "FreeBSD" ]; then \
		install -m 644 udev/20-usb-ptouch-devd.conf /usr/local/etc/devd/ptouch.conf; \
		if command -v service >/dev/null 2>&1; then service devd restart >/dev/null 2>&1 || true; fi; \
	fi

