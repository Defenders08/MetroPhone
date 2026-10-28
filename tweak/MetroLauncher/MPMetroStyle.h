#import <UIKit/UIKit.h>
#import "MPLayoutModel.h" // MPTileSize

#ifdef __cplusplus
extern "C" {
#endif
// Журнал твика: /var/mobile/Library/Preferences/metrophone.log (+ syslog).
void MPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// Главное окно SpringBoard: sharedApplication.windows в iOS 6 возвращает пусто,
// окно запоминается из хука SBWallpaperView (см. Tweak.xm).
void MPSetHostWindow(UIWindow *window);
UIWindow *MPSharedHostWindow(void);
#ifdef __cplusplus
}
#endif

// ---- Метрики сетки (раздел 4.2) ----
#define MPMetroGap       6.0f   // отступ по краям и между плитками
// Колонок в сетке нет в #define: плотность переключается настройкой (ключ smallTiles),
// число колонок возвращает [MPMetroStyle columns] — 4 или 6.

// Единая точка стиля Metro: акценты, цвета, шрифты (кэш), метрики.
// ВАЖНО: ничего из UIKit не вызывается до applicationDidFinishLaunching — всё лениво.
@interface MPMetroStyle : NSObject

// Настройки темы (CFPreferences, домен ru.ash.metrophone). Дёшево, вызывать при каждом показе.
+ (void)reloadPreferences;
+ (BOOL)isEnabled;                 // ключ enabled (по умолчанию YES)
+ (NSInteger)tileStyle;            // 0 = тёмные плитки, 1 = акцентные

+ (UIColor *)accentColor;
+ (UIColor *)tileColor;            // зависит от tileStyle
+ (UIColor *)badgeColor;           // #E51400
+ (UIColor *)placeholderColor;     // фон заглушки иконки

+ (BOOL)uppercaseLabels;           // ключ uppercaseLabels (подписи плиток и панелей)
+ (NSInteger)columns;              // колонок сетки: 4; с ключом smallTiles — 6 (мелкие плитки)

// Шрифты — только через кэш
+ (UIFont *)thinFont:(CGFloat)size;
+ (UIFont *)lightFont:(CGFloat)size;
+ (UIFont *)regularFont:(CGFloat)size;
+ (UIFont *)mediumFont:(CGFloat)size;

+ (CGFloat)cellForContainerWidth:(CGFloat)width;   // cell = (width − (cols−1)·gap) / cols
+ (CGSize)tilePixelSize:(MPTileSize)size containerWidth:(CGFloat)width; // Small/Medium/Wide по формулам WP8
+ (CGFloat)statusBarInset;         // верхний отступ под статус-бар (applicationFrame.origin.y)

@end
