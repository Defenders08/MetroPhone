#import <UIKit/UIKit.h>

// WP-тема иконок: встроенная коллекция (icons/ + glyphs/ из deb) и
// пользовательские переопределения (metrophone-icons.plist + UserIcons/).
//
// Формат «выбора» — строка с префиксом:
//   "wp:<Слаг>"    → /Library/Application Support/MetroPhone/icons/<Слаг>.png
//   "glyph:<имя>"  → /Library/Application Support/MetroPhone/glyphs/<имя>.png
//   "user:<файл>"  → /var/mobile/Library/MetroPhone/UserIcons/<файл>
// Встроенный маппинг (icons/map.plist) и пользовательский выбор используют
// один формат; в пользовательском он же возвращается из списков для пикера.
@interface MPIconTheme : NSObject

// Итоговая иконка по цепочке: пользовательский выбор → встроенный маппинг → nil.
// isFill (если не NULL) — рисовать ли иконку на всю плитку: YES для user-иконок
// и для приложений без темы при включённом fillSideIcons, NO для wp/glyph.
+ (UIImage *)iconForBundleID:(NSString *)bundleID fill:(BOOL *)isFill;

+ (NSString *)customChoiceForBundleID:(NSString *)bundleID;   // nil, если не задан
+ (void)setCustomChoice:(NSString *)choice forBundleID:(NSString *)bundleID;
+ (void)removeCustomChoiceForBundleID:(NSString *)bundleID;
+ (BOOL)hasCustomChoiceForBundleID:(NSString *)bundleID;

// Списки вариантов для пикера: NSArray<NSString> в формате выбора выше
+ (NSArray *)builtinChoices;   // "wp:..." + "glyph:..."
+ (NSArray *)userChoices;      // "user:..."

+ (UIImage *)imageForChoice:(NSString *)choice;

+ (NSString *)userIconsDirectory;

// Сброс кэшей этой темы + Darwin-событие MP_ICONS_CHANGED_NOTIFICATION
// (SpringBoard по нему сносит кэш плиток и перезагружает иконки).
+ (void)notifyIconsChanged;

@end
