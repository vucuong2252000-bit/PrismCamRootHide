include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PrismCam

PrismCam_FILES = main.m PCAppDelegate.m PCViewController.m ../shared/PCShared.m
PrismCam_CFLAGS = -fobjc-arc -I../shared
PrismCam_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers
PrismCam_LIBRARIES = roothide
PrismCam_CODESIGN_FLAGS = -SPrismCam.entitlements

include $(THEOS_MAKE_PATH)/application.mk
