export PACKAGE_VERSION := 2.4

ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:15.0
GO_EASY_ON_ME := 1

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += AIGate
SUBPROJECTS += WriteNowPrefs

include $(THEOS_MAKE_PATH)/aggregate.mk

TWEAK_NAME := WriteNow

WriteNow_FILES += WriteNow.xm
WriteNow_FILES += WriteNowStub.swift

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
WriteNow_FILES += libroot/dyn.c
endif

WriteNow_CFLAGS += -fobjc-arc
WriteNow_CFLAGS += -fvisibility=hidden
WriteNow_CFLAGS += -I.
WriteNow_CFLAGS += -DPACKAGE_VERSION=\"$(PACKAGE_VERSION)\"

WriteNow_CFLAGS += -Wno-unused-variable
WriteNow_CFLAGS += -Wno-unused-function

WriteNow_LDFLAGS += -Wl,-all_load

WriteNow_LDFLAGS += -FFrameworks/OpenAI.xcframework/ios-arm64_arm64e -framework OpenAI
WriteNow_SWIFTFLAGS += -FFrameworks/OpenAI.xcframework/ios-arm64_arm64e -framework OpenAI

WriteNow_CFLAGS += -FFrameworks/WritingTools.xcframework/ios-arm64_arm64e -framework WritingTools
WriteNow_LDFLAGS += -FFrameworks/WritingTools.xcframework/ios-arm64_arm64e -framework WritingTools
WriteNow_SWIFTFLAGS += -FFrameworks/WritingTools.xcframework/ios-arm64_arm64e -framework WritingTools

WriteNow_LDFLAGS += -FFrameworks/WritingToolsLocalizable.xcframework/ios-arm64_arm64e -framework WritingToolsLocalizable
WriteNow_SWIFTFLAGS += -FFrameworks/WritingToolsLocalizable.xcframework/ios-arm64_arm64e -framework WritingToolsLocalizable

WriteNow_CFLAGS += -FFrameworks/WritingToolsInjector.xcframework/ios-arm64_arm64e -framework WritingToolsInjector
WriteNow_LDFLAGS += -FFrameworks/WritingToolsInjector.xcframework/ios-arm64_arm64e -framework WritingToolsInjector
WriteNow_SWIFTFLAGS += -FFrameworks/WritingToolsInjector.xcframework/ios-arm64_arm64e -framework WritingToolsInjector

WriteNow_LDFLAGS += -FFrameworks/ColorfulX.xcframework/ios-arm64_arm64e -framework ColorfulX
WriteNow_SWIFTFLAGS += -FFrameworks/ColorfulX.xcframework/ios-arm64_arm64e -framework ColorfulX

WriteNow_LDFLAGS += -FFrameworks/ColorVector.xcframework/ios-arm64_arm64e -framework ColorVector
WriteNow_SWIFTFLAGS += -FFrameworks/ColorVector.xcframework/ios-arm64_arm64e -framework ColorVector

WriteNow_LDFLAGS += -FFrameworks/SpringInterpolation.xcframework/ios-arm64_arm64e -framework SpringInterpolation
WriteNow_SWIFTFLAGS += -FFrameworks/SpringInterpolation.xcframework/ios-arm64_arm64e -framework SpringInterpolation

WriteNow_LDFLAGS += -FFrameworks/MSDisplayLink.xcframework/ios-arm64_arm64e -framework MSDisplayLink
WriteNow_SWIFTFLAGS += -FFrameworks/MSDisplayLink.xcframework/ios-arm64_arm64e -framework MSDisplayLink

include $(THEOS_MAKE_PATH)/tweak.mk

export DEBUG
before-all::
	devkit/print-version.sh
	devkit/standardize-entitlements.sh
	devkit/build-spm.sh

export THEOS_OBJ_DIR
export THEOS_STAGING_DIR
before-package::
	$(ECHO_NOTHING)ldid -SAIGate/AIGate/AIGatePrivileged.entitlements $(THEOS_STAGING_DIR)/Applications/AIGate.app$(ECHO_END)

clean::
	$(ECHO_NOTHING)rm -rf Frameworks/WritingTools.xcframework || true$(ECHO_END)
	$(ECHO_NOTHING)rm -rf Frameworks/WritingToolsLocalizable.xcframework || true$(ECHO_END)
	$(ECHO_NOTHING)rm -rf Frameworks/WritingToolsInjector.xcframework || true$(ECHO_END)

ifeq ($(THEOS_PACKAGE_SCHEME), rootless)
stage::
	plutil -replace Program -string $(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/AIGate.app/AIGate $(THEOS_STAGING_DIR)/Library/LaunchDaemons/wiki.qaq.writenowservices.plist
endif
