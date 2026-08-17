include $(THEOS)/makefiles/common.mk

TOOL_NAME = PrismCamStreamd

PrismCamStreamd_FILES = main.m PCFrameDaemon.m ../shared/PCShared.m
PrismCamStreamd_CFLAGS = -fobjc-arc -I../shared
PrismCamStreamd_FRAMEWORKS = Foundation AVFoundation CoreImage CoreMedia CoreVideo ImageIO
PrismCamStreamd_LIBRARIES = roothide
PrismCamStreamd_INSTALL_PATH = /usr/libexec
PrismCamStreamd_CODESIGN_FLAGS = -SPrismCamStreamd.entitlements

include $(THEOS_MAKE_PATH)/tool.mk

