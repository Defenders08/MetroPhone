#import <UIKit/UIKit.h>

// Полноэкранный выбор иконки в стиле WP 8.1: сетка встроенных WP-иконок
// и пользовательских PNG из UserIcons/. Тап по варианту — применить сразу
// (перезагрузка плиток по MPAppsChanged, кэш плиток SpringBoard сносит
// слушатель MP_ICONS_CHANGED_NOTIFICATION в Tweak.xm).
@interface MPIconPickerView : UIView
+ (void)showFromView:(UIView *)parent forBundleID:(NSString *)bundleID appName:(NSString *)appName;
@end
