export THEOS
export TARGET = iphone:clang:15.6:15.0

# Kế thừa scheme từ Makefile gốc (rootless | roothide), chặn rootful.
include ../common-scheme.mk

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SiriBridgePrefs
SiriBridgePrefs_FILES = SBRootListController.m SBPrefsUI.m ../Sources/SBPaths.m
ADDITIONAL_CFLAGS = -Wno-unguarded-availability-new -Wno-nullability-completeness
SiriBridgePrefs_CFLAGS = -fobjc-arc -I../Sources -Wno-deprecated-declarations
SiriBridgePrefs_FRAMEWORKS = UIKit AVFoundation
SiriBridgePrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
SiriBridgePrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
