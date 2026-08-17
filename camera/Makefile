include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrismCamCamera

PrismCamCamera_FILES = Tweak.xm PCCameraProcessor.m ../shared/PCShared.m
PrismCamCamera_CFLAGS = -fobjc-arc -I../shared
PrismCamCamera_FRAMEWORKS = Foundation CoreImage CoreMedia CoreVideo ImageIO
PrismCamCamera_LIBRARIES = substrate roothide

include $(THEOS_MAKE_PATH)/tweak.mk

