include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SiriXPreferences

SiriXPreferences_FILES = \
	SXRootListController.m \
	SXPreferenceListController.m \
	SXLogViewController.m \
	SXPromptController.m \
	SXChatTestController.m \
	SXHistoryController.m \
	SXStatsController.m \
	../Sources/SXLog.m \
	../Sources/SXStore.m \
	../Sources/SXPrefs.m \
	../Sources/SXLLM.m \
	../Sources/SXStream.m \
	../Sources/SXMarkdown.m \
	../Sources/SXTools.m \
	../Sources/SXNetwork.m \
	../Sources/SXConfigIO.m \
	../Sources/SXProviders.m \
	../Sources/SXMediaFormat.m \
	../Sources/SXTTS.m \
	SXProviderConfigController.m \
	SXMediaController.m

SiriXPreferences_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
	-I$(THEOS_PROJECT_DIR)/include \
	-I../Sources \
	-DSX_SCHEME=\"$(THEOS_PACKAGE_SCHEME)\"
SiriXPreferences_FRAMEWORKS = UIKit Foundation CoreGraphics AVFoundation SystemConfiguration UniformTypeIdentifiers
SiriXPreferences_PRIVATE_FRAMEWORKS = Preferences
SiriXPreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
