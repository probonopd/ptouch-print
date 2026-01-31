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
