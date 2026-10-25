// MetroPhone — общие константы настроек (используется твиком и бандлом настроек).

#ifndef MetroPhoneCommon_h
#define MetroPhoneCommon_h

// Домен CFPreferences (совпадает с Package: в control)
#define MP_PREFS_DOMAIN "ru.ash.metrophone"

// Ключи настроек
static NSString * const MPKeyEnabled        = @"enabled";         // главный переключатель
static NSString * const MPKeyFlatPanels     = @"flatPanels";      // плоские тёмные панели + шрифт заголовков
static NSString * const MPKeyTiles          = @"squareTiles";     // квадратные плитки
static NSString * const MPKeyTileStyle      = @"tileStyle";       // 0 = тёмные, 1 = акцентные
static NSString * const MPKeyBlackWallpaper = @"blackWallpaper";  // чёрный фон вместо обоев
static NSString * const MPKeyMetroLabels    = @"metroLabels";     // шрифт подписей иконок
static NSString * const MPKeyUppercase      = @"uppercaseLabels"; // ЗАГЛАВНЫЕ буквы
static NSString * const MPKeyAccent         = @"accent";          // имя цвета из палитры WP
static NSString * const MPKeyMultitask      = @"multitaskEnabled";// свой свитчер по двойному Home

// Палитра акцентов Windows Phone: имя → HEX
//   blue    #1BA1E2 (по умолчанию)
//   purple  #A200FF
//   magenta #D80073
//   green   #008A00
//   lime    #A4C400
//   orange  #F09609
//   red     #E51400
//   teal    #00ABA9

#endif /* MetroPhoneCommon_h */
