export THEOS
export ARCHS = arm64
export TARGET = iphone:clang:15.6:15.0
export THEOS_PACKAGE_SCHEME = rootless

PACKAGE_VERSION = 0.1.0
export PACKAGE_VERSION

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SiriBridge
SiriBridge_FILES = Sources/Tweak.x \
                   Sources/SBConfig.m \
                   Sources/SBCapture.m \
                   Sources/SBHistory.m \
                   Sources/SBLLM.m \
                   Sources/SBTTS.m \
                   Sources/SBTools.m \
                   Sources/SBEngine.m \
                   Sources/SBDeliver.m
ADDITIONAL_CFLAGS = -Wno-unguarded-availability-new -Wno-nullability-completeness -Wno-nullability -Wno-documentation
SiriBridge_CFLAGS = -fobjc-arc -I Sources -Wno-deprecated-declarations -Wno-unused-function
SiriBridge_FRAMEWORKS = Foundation UIKit AVFoundation MediaPlayer EventKit Contacts CoreFoundation
# Cho phép các symbol của Siri/SpringBoard (không link được) — hook runtime resolve
SiriBridge_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS)/makefiles/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS)/makefiles/aggregate.mk

# Tắt bước ký mặc định nếu máy build không có ldid (Linux/zig)
TARGET_CODESIGN ?= ldid

after-install::
	install.exec "killall -9 SpringBoard || true"
