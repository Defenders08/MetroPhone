TARGET := iphone:clang:10.3:6.0
ARCHS := armv7 armv7s

include $(THEOS)/makefiles/common.mk

# Отключаем Clang-модули — SDK 10.3 содержит устаревшие module.map (см. главный Makefile)
MODULESFLAGS :=

BUNDLE_NAME = MetroPhonePrefs

MetroPhonePrefs_FILES = MPRootListController.m
MetroPhonePrefs_FRAMEWORKS = UIKit CoreGraphics
MetroPhonePrefs_PRIVATE_FRAMEWORKS = Preferences
MetroPhonePrefs_INSTALL_PATH = /Library/PreferenceBundles
MetroPhonePrefs_LDFLAGS = -lgcc_s.1
MetroPhonePrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/bundle.mk
