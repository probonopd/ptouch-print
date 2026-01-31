include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = PtouchGUI
PtouchGUI_OBJC_FILES = src-gui/PtouchGUI.m
PtouchGUI_C_FILES = src/libptouch.c src/ptouch-render.c

# Include directories
ADDITIONAL_INCLUDE_DIRS += -Iinclude -Ibuild

# Library dependencies
ADDITIONAL_GUI_LIBS += $(shell pkg-config --libs gdlib libusb-1.0)
ADDITIONAL_CPPFLAGS += $(shell pkg-config --cflags gdlib libusb-1.0) -DUSING_CMAKE=1

include $(GNUSTEP_MAKEFILES)/application.make

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

