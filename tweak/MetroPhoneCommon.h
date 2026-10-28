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
static NSString * const MPKeyAccent         = @"accent";          // имя цвета из палитры WP (до 0.6.11)
static NSString * const MPKeyAccentHex      = @"accentHex";       // HEX из сетки «Цвета» (WP 8.1), напр. «1BA1E2»
static NSString * const MPKeyMultitask      = @"multitaskEnabled";// свой свитчер по двойному Home
static NSString * const MPKeyLockscreen     = @"lockscreenEnabled";// локскрин в стиле WP 8.1
static NSString * const MPKeyWPIcons        = @"wpIcons";         // WP-иконки для системных приложений
static NSString * const MPKeyFillSideIcons  = @"fillSideIcons";   // иконки без темы — на всю плитку

// Живые плитки (виджеты). Главный тумблер + ключи на виджет:
// liveTile.<tileID>.enabled (BOOL, по умолчанию YES) и liveTile.<tileID>.size
// (NSInteger: 0 = 1×1, 1 = 2×1, 2 = 2×2).
static NSString * const MPKeyLiveTiles      = @"liveTilesEnabled";
static NSString * const MPKeyLiveTilePrefix = @"liveTile.";

// Darwin-уведомление «настройки живых плиток изменились» (Настройки → SpringBoard)
#define MP_LIVETILES_CHANGED_NOTIFICATION "ru.ash.metrophone.livetiles-changed"

// Папка для сторонних виджетов на устройстве (рядом с icons). Пока пустая:
// когда-нибудь сюда будут падать бандлы/dylib сторонних виджетов, и загрузчик
// в MPLiveTileRegistry будет их подхватывать (см. scanExternalWidgetsDirectory:).
#define MP_WIDGETS_DIR "/var/mobile/Library/Application Support/MetroPhone/Widgets"

// Папка для сторонних дизайнов приложений (рядом с Widgets). Будущее: дизайн
// приложения = группа Logos-хуков + init с проверкой bundleID (образец —
// AppDesigns/Settings/); диспетчер встанет в %ctor ветки «чужое приложение».
#define MP_APPDESIGNS_DIR "/var/mobile/Library/Application Support/MetroPhone/AppDesigns"

// Darwin-уведомление после смены акцента (страница «Цвета» → твики)
#define MP_ACCENT_CHANGED_NOTIFICATION "ru.ash.metrophone.accent-changed"

// Darwin-уведомление «тема иконок изменилась» (пикер, тумблеры → все твики)
#define MP_ICONS_CHANGED_NOTIFICATION "ru.ash.metrophone.icons-changed"

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
