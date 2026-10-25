// MPSettingsTheme — настройки, метрики и однократная настройка UIAppearance
// для переоформления приложения «Настройки» (com.apple.Preferences) в стиль WP 8.1.

#import <UIKit/UIKit.h>
#import "../MetroLauncher/MPMetroStyle.h"

@interface MPSettingsTheme : NSObject

// Kill-switch: ключ settingsRestyle (домен ru.ash.metrophone), по умолчанию YES.
+ (BOOL)restyleEnabled;

// Режим диагностики: ключ settingsDebug (по умолчанию NO) — лог классов ячеек.
+ (BOOL)debugEnabled;

// Классы контроллеров, которые НЕ переоформляем (экран остаётся штатным)
+ (NSArray *)excludedControllerClasses;
+ (BOOL)isControllerExcluded:(UIViewController *)controller;

// Однократная настройка UIAppearance для процесса Preferences.
// Вызывать только лениво (после запуска приложения), никогда не из %ctor.
+ (void)setupAppearanceOnce;

// Плоская подсветка нажатия (белый α 0.12)
+ (UIView *)flatSelectionBackground;

// Прямой стайлинг ЕДИНИЦЫ навбара (appearance не доезжает до созданных баров):
// чёрный фон, скрытый заголовок
+ (void)styleNavigationBar:(UINavigationBar *)bar;

// Фон всех окон процесса — чёрный (убирает белую полосу под статус-баром)
+ (void)styleWindows;

// Ползунок в WP-стиле (тонкий трек + плоский белый бегунок)
+ (void)styleSlider:(UISlider *)slider;

@end
