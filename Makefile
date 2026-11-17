export THEOS

# Chọn scheme (rootless | roothide). Rootful bị chặn cứng trong file này.
include common-scheme.mk

export TARGET = iphone:clang:15.6:15.0

PACKAGE_VERSION = 0.1.0
export PACKAGE_VERSION

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SiriBridge
SiriBridge_FILES = Sources/Tweak.x \
                   Sources/SBPaths.m \
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
# Symbol của Siri/SpringBoard không link được lúc build — resolve ở runtime
SiriBridge_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS)/makefiles/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS)/makefiles/aggregate.mk

# Linux/zig: dùng shim tools/bin/ldid (no-op) trừ khi có ldid thật.
TARGET_CODESIGN = $(or $(shell command -v ldid 2>/dev/null),$(CURDIR)/tools/bin/ldid)

after-install::
	install.exec "killall -9 SpringBoard || true"
