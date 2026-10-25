#import <UIKit/UIKit.h>

// Metro-лаунчер: полноэкранная вьюха поверх родного рабочего стола.
// Две страницы в paging-скролле: 0 — плитки, 1 — алфавитный список.
// Приватные API SpringBoard здесь не вызываются (блокировку экрана учитывает интеграционный код в Tweak.xm).
@interface MPHomeController : UIViewController

- (void)installLauncherView;         // добавить self.view в SBScreenView (+ кнопка «M» на родном столе)
- (void)showMetroAnimated:(BOOL)a;   // показать + bringToFront (fade 0.25 c при animated)
- (void)hideMetroAnimated:(BOOL)a;   // спрятать — родной стол виден
- (BOOL)isMetroVisible;

// Кнопка Home: выйти из режима редактирования плиток (с сохранением раскладки)
- (void)homeButtonPressed;

// Кнопка «M» (24×24, полупрозрачная, правый верх) на родном столе. Добавляется один раз.
- (void)addMetroToggleButtonToView:(UIView *)nativeView;

@end
