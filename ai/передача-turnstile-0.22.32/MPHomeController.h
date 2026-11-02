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

// Turnstile-переход при запуске приложения из плитки (0.22.32): launch зовётся
// СРАЗУ (спавн перекрывается анимацией), Start уезжает влево одним слоем,
// навстречу подъезжает WP-сплэш (цвет плитки + иконка + имя), а копия сплэша
// клеится в окно приложения, накрывая системный zoom и белый Default.png.
// pressedTile — тапнутая плитка (данные сплэша). bundleID — что запускаем (по
// нему сторож ловит неудачный запуск); nil — сторож не действует (виджеты с
// URL-целями, которые не свернуть к bundleID).
// YES — анимация сыграла (или это повторный тап в процессе выезда: он проглатывается),
//       запускать самим НЕ нужно;
// NO  — анимации не будет (твик выключен, Reduce Motion, нет иконки) — запускайте сразу.
- (BOOL)playAppOpenAnimationForBundleID:(NSString *)bundleID
                            pressedTile:(UIView *)pressedTile
                                 launch:(void (^)(void))launch;

// Въезд лаунчера доиграл до identity. Постится один раз на въезд; слушатели
// (Tweak.xm) вешают сюда отложенную работу — прогрев кэша приложений.
extern NSString * const MPTurnstileInDidFinishNotification;

// Окно приложения скрылось (возврат на стол): если ранний feather-въезд уже
// играет под окном — только фиксация (поднять лаунчер), иначе обычный въезд.
// Зовётся из хука SBAppWindow и из Home-фолбэка в Tweak.xm.
- (void)appWindowDidHide;

// Возврат из приложения (Home-фолбэк): ранний feather-въезд под окном приложения
// стартует сразу; опрос frontmost внутри только фиксирует факт ухода окна.
- (void)scheduleReturnFromApp;

// От хука SBAppWindow setHidden: — окно приложения показалось (hidden=NO: клеим
// копию сплэша запуска) или скрылось (hidden=YES: фиксация/въезд). На iOS 6
// setHidden:YES при закрытии приложения может НЕ вызываться — тогда возврат ведёт
// Home-фолбэк (scheduleReturnFromApp).
- (void)noteAppWindowHidden:(BOOL)hidden forWindow:(UIWindow *)window;

// От хука SBAppWindow didAddSubview/layoutSubviews: поднять копию сплэша над
// новым контентом окна приложения и отсрочить её снятие (контент готов эвристикой).
- (void)noteAppWindowLayout:(UIWindow *)window;

// Home-фолбэк: лаунчер спрятан (приложение поверх), не залочено, переход наш —
// можно играть въезд по нажатию Home
- (BOOL)wantsReturnFromApp;

// Единственный экземпляр лаунчера (создаётся в MPEnsureLauncher из Tweak.xm).
// До регистрации вернёт nil — посылка nil это просто старое поведение без анимации.
+ (MPHomeController *)sharedController;
+ (void)setSharedController:(MPHomeController *)c;

@end

// Свайп-анлок (зовёт MPLockScreen.m): лаунчер показывается ПОД окном локскрина
// заранее, чтобы слайд и Turnstile перекрывались без «ямы».
// prepareUnlockEntry — при НАЧАЛЕ вертикального драга: фон + старт-позы feather
//   отрисовываются заранее (первый кадр ловится display link);
// startUnlockEntry — по прогрессу слайда (~35 % пути): играет Turnstile-въезд
//   от прогретых старт-поз; повторный вызов игнорирует;
// cancelUnlockEntry — разблокировка не прошла: прогретый лаунчер прячется
//   мгновенно, старт-позы снимаются.
void MPHomePrepareUnlockEntry(void);
void MPHomeStartUnlockEntry(void);
void MPHomeCancelUnlockEntry(void);
