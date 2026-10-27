# MetroPhone — тема Windows Phone для iOS 6
# SDK 10.3 — последний с armv7/armv7s-библиотеками; минимальная версия системы — 6.0.
TARGET := iphone:clang:10.3:6.0
ARCHS := armv7 armv7s

include $(THEOS)/makefiles/common.mk

# SDK 10.3 использует устаревшие module.map, которые новый clang считает ошибкой:
# собираем классическими текстовыми включениями, без Clang-модулей.
MODULESFLAGS :=

TWEAK_NAME = MetroPhone
MetroPhone_FILES = Tweak.xm MetroLauncher/MPAppDataSource.m MetroLauncher/MPHomeController.m MetroLauncher/MPTilesPageView.m MetroLauncher/MPTileView.m MetroLauncher/MPLayoutModel.m MetroLauncher/MPTileEditor.m MetroLauncher/MPAppListPageView.m MetroLauncher/MPMetroStyle.m MetroLauncher/MPMultitaskView.m MetroLockScreen/MPLockScreenView.m MetroLockScreen/MPLockScreen.m MetroSettings/MPSettingsHooks.xm MetroSettings/MPSettingsTheme.m MetroSettings/MPSettingsHeaderView.m MetroSettings/MPSettingsCellStyler.m MetroSettings/MPSettingsToggle.m
MetroPhone_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreText
# libSystem в SDK больше не переэкспортирует libgcc_s (SjLj-unwind для armv7) — линкуем явно
MetroPhone_LDFLAGS = -lgcc_s.1
MetroPhone_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += metrophoneprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
