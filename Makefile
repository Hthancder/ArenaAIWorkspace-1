export THEOS_PACKAGE_SCHEME ?= rootless

ARCHS = arm64 arm64e
# SDK 15.6 từ theos/sdks (SDK "patched" có private-framework tbds — Xcode stock không có)
TARGET = iphone:clang:15.6:15.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SiriX

SiriX_FILES = \
	Sources/Tweak.x \
	Sources/SXLog.m \
	Sources/SXStore.m \
	Sources/SXPrefs.m \
	Sources/SXHeaders.m \
	Sources/SXTools.m \
	Sources/SXToolkit.m \
	Sources/SXToolCatalog.m \
	Sources/SXLLM.m \
	Sources/SXIntercept.m \
	Sources/SXStream.m \
	Sources/SXMarkdown.m \
	Sources/SXDisplayPolicy.m

SiriX_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
	-I$(THEOS_PROJECT_DIR)/include \
	-DSX_SCHEME=\"$(THEOS_PACKAGE_SCHEME)\"
SiriX_FRAMEWORKS = UIKit Foundation SystemConfiguration

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
