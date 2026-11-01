#import <UIKit/UIKit.h>

// Metro-лаунчер: полноэкранная вьюха поверх родного рабочего стола.
// Две страницы в paging-скролле: 0 — плитки, 1 — алфавитный список.
// Приватные API SpringBoard здесь не вызываются (блокировку экрана учитывает интеграционный код в Tweak.xm).
@interface MPHomeController : UIViewController

- (void)installLauncherView;         // добавить self.view в SBScreenView (+ кнопка «M» на родном столе)
- (void)showMetroAnimated:(BOOL)a;   // показать + bringToFront (fade 0.25 c при animated)
- (void)hideMetroAnimated:(BOOL)a;   // спрятать — родной стол виден
- (void)showMetroAfterLockscreen;    // анлок: подготовить показ, въезд — по скрытию локскрина
- (BOOL)isMetroVisible;

// Идёт ли переход/ожидание возврата (выезд, въезд, приложение на переднем плане).
// Живые плитки не флипают в этом состоянии (вопрос бюджета A4 и чистоты перехода).
+ (BOOL)metroTransitionActive;

// Кнопка Home: выйти из режима редактирования плиток (с сохранением раскладки)
- (void)homeButtonPressed;

// Переприменить цвета страниц (плитки/список) и кнопки «M» — вызывается извне
// при смене акцентного цвета (Darwin-уведомление из Настроек)
- (void)applyStyleToPages;

// Turnstile (WP-переход) при запуске приложения из плитки: лаунчер выезжает поворотом
// вокруг левого края (0°→+50°, 0.25 с) со feather-стаггером по строкам (WP8.1),
// после выезда лаунчер ставится в стартовую позу въезда (−80°, alpha 0) и ТОЛЬКО
// ТОГДА вызывается launch. pressedTile — тапнутая плитка (уходит последней).
// bundleID — что запускаем (по нему сторож ловит неудачный запуск); nil — сторож
// не действует (виджеты с URL-целями, которые не свернуть к bundleID).
// YES — анимация сыграла (или это повторный тап в процессе выезда: он проглатывается),
//       запускать самим НЕ нужно;
// NO  — анимации не будет (твик выключен, Reduce Motion, нет иконки) — запускайте сразу.
- (BOOL)playAppOpenAnimationForBundleID:(NSString *)bundleID
                            pressedTile:(UIView *)pressedTile
                                 launch:(void (^)(void))launch;

// Въезд лаунчера доиграл до identity. Постится один раз на въезд; слушатели
// (Tweak.xm) вешают сюда отложенную работу — прогрев кэша приложений.
extern NSString * const MPTurnstileInDidFinishNotification;

// Окно приложения скрылось (возврат на стол): лаунчер въезжает Turnstile-ом
// (−80°→0°, 0.35 с). Зовётся из хука SBAppWindow и из Home-фолбэка в Tweak.xm.
- (void)appWindowDidHide;

// Возврат из приложения: следим за окном приложения (frontmost-опрос) и играем
// въезд в момент, когда оно РЕАЛЬНО ушло, — не по константе 0.45 с. Зовётся из
// Home-фолбэка в Tweak.xm вместо прежнего dispatch_after.
- (void)scheduleReturnFromApp;

// Диагностика от хука SBAppWindow setHidden: — если приложение реально открылось
// (hidden=NO) или закрылось (hidden=YES) в процессе нашего перехода. На iOS 6
// setHidden: при закрытии приложения может НЕ вызываться — тогда возврат ведёт
// Home-фолбэк (wantsReturnFromApp в menuButtonDown:).
- (void)noteAppWindowHidden:(BOOL)hidden;

// Home-фолбэк: лаунчер спрятан (приложение поверх), не залочено, переход наш —
// можно играть въезд по нажатию Home
- (BOOL)wantsReturnFromApp;

// Единственный экземпляр лаунчера (создаётся в MPEnsureLauncher из Tweak.xm).
// До регистрации вернёт nil — посылка nil это просто старое поведение без анимации.
+ (MPHomeController *)sharedController;
+ (void)setSharedController:(MPHomeController *)c;

@end
