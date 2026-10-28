TARGET := iphone:clang:10.3:6.0
ARCHS := armv7 armv7s

# Релиз-режим всегда: -Os + strip (см. главный Makefile)
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

# Отключаем Clang-модули — SDK 10.3 содержит устаревшие module.map (см. главный Makefile)
MODULESFLAGS :=

BUNDLE_NAME = MetroPhonePrefs

MetroPhonePrefs_FILES = MPRootListController.m MPColorsListController.m MPColorsGridView.m MPLiveTilesListController.m MPLiveTileSizeView.m
MetroPhonePrefs_FRAMEWORKS = UIKit CoreGraphics CoreText
MetroPhonePrefs_PRIVATE_FRAMEWORKS = Preferences
MetroPhonePrefs_INSTALL_PATH = /Library/PreferenceBundles
MetroPhonePrefs_LDFLAGS = -lgcc_s.1
MetroPhonePrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

# 7.5: ресурсы бандла обязаны быть 644 — иначе «Настройки» (работают под mobile)
# не читают Root.plist и страница MetroPhone открывается пустой
before-all::
	chmod 644 Resources/*

include $(THEOS_MAKE_PATH)/bundle.mk
