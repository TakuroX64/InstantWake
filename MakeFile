TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = InstantWake
InstantWake_FILES = Tweak.x
InstantWake_CFLAGS = -fobjc-arc
InstantWake_FRAMEWORKS = UIKit CoreFoundation
InstantWake_PRIVATE_FRAMEWORKS = IOKit

include $(THEOS_MAKE_PATH)/tweak.mk
