include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PrismCamOverlay

PrismCamOverlay_FILES = Tweak.xm ../shared/PCShared.m
PrismCamOverlay_CFLAGS = -fobjc-arc -I../shared
PrismCamOverlay_FRAMEWORKS = UIKit Foundation
PrismCamOverlay_LIBRARIES = substrate roothide

include $(THEOS_MAKE_PATH)/tweak.mk

