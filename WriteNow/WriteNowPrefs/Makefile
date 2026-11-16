ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES := Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := WriteNowPrefs

WriteNowPrefs_FILES += $(wildcard *.mm)
WriteNowPrefs_FILES += $(wildcard *.swift)

WriteNowPrefs_FILES += ../AIGate/AIGate/Editor/AddEndpointView.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Editor/CommonProvider.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Editor/EndpointButton.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Editor/TestTextView.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Editor/WriteNowRootView.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Extension/Color+Accent.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Extension/GateSessionDelegate.mm
WriteNowPrefs_FILES += ../AIGate/AIGate/Extension/WriteNowAppModel+Ext.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Loader/Configuration.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Loader/Configuration+Endpoint.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Service/Client/AIGateClient.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Service/Client/AIGateConfiguration.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Storage/GlobalStorage.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Storage/Persist.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Storage/PersistProvider.swift
WriteNowPrefs_FILES += ../AIGate/AIGate/Storage/PublishedPersist.swift

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
WriteNowPrefs_FILES += ../libroot/dyn.c
endif

WriteNowPrefs_CFLAGS += -fobjc-arc
WriteNowPrefs_CFLAGS += -I..
WriteNowPrefs_CFLAGS += -I../AIGate/AIGate/Extension
WriteNowPrefs_CFLAGS += -DPACKAGE_VERSION=\"$(PACKAGE_VERSION)\"

WriteNowPrefs_LDFLAGS += -F../Frameworks



WriteNowPrefs_LDFLAGS += -FLibrary

WriteNowPrefs_LDFLAGS += -FLibrary/SwiftUIIntrospect.xcframework/ios-arm64_arm64e -framework SwiftUIIntrospect
WriteNowPrefs_SWIFTFLAGS += -FLibrary/SwiftUIIntrospect.xcframework/ios-arm64_arm64e -framework SwiftUIIntrospect

WriteNowPrefs_FRAMEWORKS += CoreTelephony
WriteNowPrefs_FRAMEWORKS += UIKit
WriteNowPrefs_PRIVATE_FRAMEWORKS += Preferences

WriteNowPrefs_SWIFT_BRIDGING_HEADER += WriteNowPrefs-Bridging-Header.h
WriteNowPrefs_INSTALL_PATH += /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

before-all::
	devkit/copy-resources.sh
