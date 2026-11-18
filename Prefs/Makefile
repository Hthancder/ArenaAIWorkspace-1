include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SiriXPreferences

SiriXPreferences_FILES = \
	SXRootListController.m \
	SXLogViewController.m \
	SXPromptController.m \
	../Sources/SXLog.m \
	../Sources/SXPrefs.m \
	../Sources/SXLLM.m \
	../Sources/SXTools.m

SiriXPreferences_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
	-I$(THEOS_PROJECT_DIR)/include \
	-I../Sources \
	-DSX_SCHEME=\"$(THEOS_PACKAGE_SCHEME)\"
SiriXPreferences_FRAMEWORKS = UIKit Foundation
SiriXPreferences_PRIVATE_FRAMEWORKS = Preferences
SiriXPreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
