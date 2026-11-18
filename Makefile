export THEOS_PACKAGE_SCHEME ?= rootless

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SiriX

SiriX_FILES = \
	Sources/Tweak.x \
	Sources/SXLog.m \
	Sources/SXPrefs.m \
	Sources/SXTools.m \
	Sources/SXLLM.m \
	Sources/SXIntercept.m

SiriX_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
	-I$(THEOS_PROJECT_DIR)/include \
	-DSX_SCHEME=\"$(THEOS_PACKAGE_SCHEME)\"
SiriX_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
