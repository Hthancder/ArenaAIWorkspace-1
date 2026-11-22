include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SiriXPreferences

SiriXPreferences_FILES = \
	SXRootListController.m \
	SXLogViewController.m \
	SXPromptController.m \
	SXChatTestController.m \
	SXHistoryController.m \
	SXStatsController.m \
	SXMemoryController.m \
	SXToolsController.m \
	SXHeadersController.m \
	../Sources/SXLog.m \
	../Sources/SXStore.m \
	../Sources/SXPrefs.m \
	../Sources/SXPrefsShared.m \
	../Sources/SXHeaders.m \
	../Sources/SXHTTP.m \
	../Sources/SXLLM.m \
	../Sources/SXStream.m \
	../Sources/SXMarkdown.m \
	../Sources/SXTools.m \
	../Sources/SXToolkit.m \
	../Sources/SXToolCatalog.m \
	SXProviderConfigController.m \
	SXModelPickerController.m \
	SXUISupport.m \
	SXDiagnosticsController.m \
	SXAPIChoiceController.m \
	SXChoiceRow.m \
	SXNavigationSupport.m \
	UIViewController+SXBack.m \
	../Sources/SXUpdate.m

SiriXPreferences_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
	-I$(THEOS_PROJECT_DIR)/include \
	-I../Sources \
	-DSX_SCHEME=\"$(THEOS_PACKAGE_SCHEME)\"
SiriXPreferences_FRAMEWORKS = UIKit Foundation SystemConfiguration UserNotifications
SiriXPreferences_PRIVATE_FRAMEWORKS = Preferences
SiriXPreferences_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
