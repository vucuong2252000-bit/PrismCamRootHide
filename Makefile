ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
PACKAGE_VERSION = 0.1.0

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += app daemon camera overlay

include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	chmod 0755 $(THEOS_PROJECT_DIR)/layout/DEBIAN/postinst
	chmod 0755 $(THEOS_PROJECT_DIR)/layout/DEBIAN/prerm
