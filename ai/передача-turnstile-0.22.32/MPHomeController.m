#import "MPHomeController.h"
#import "MPTilesPageView.h"
#import "MPTileView.h"                      // mpIconImage/mpLayerDiag (сплэш, дамп слоёв)
#import "MPAppListPageView.h"
#import "MetroWidgets/MPLiveWidgetsPageView.h"
#import "MPMetroStyle.h"
#import "MPAppDataSource.h"
#import "MPAnimationConstants.h"
#import "../MetroLockScreen/MPLockScreen.h" // MPLockScreenNotCovering (гонка раннего анлока)
#import "MetroWidgets/MPLiveTileScheduler.h"
#import <objc/runtime.h>

// Приватный класс SpringBoard (только проверка блокировки для Home-фолбэка)
@interface SBAwayController : NSObject
+ (id)sharedAwayController;
- (BOOL)isLocked;
@end

// Поиск контейнера для лаунчера. Класс SBScreenView ищется только по ИМЕНИ (строковое сравнение),
// никаких сообщений приватным классам не отправляется. Дублирует MPFindScreenView из Tweak.xm,
// потому что та функция static и из этого файла недоступна.
static UIView *MPHCFindHostView(void) {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        for (UIView *v in w.subviews) {
            if ([NSStringFromClass([v class]) isEqualToString:@"SBScreenView"]) return v;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

// ---- Turnstile (переход при запуске/закрытии приложений; параметры в MPAnimationConstants.h) ----

static NSString * const MPTurnstileKeyTurnOut = @"mpTurnstileOut";
static NSString * const MPTurnstileKeyFadeOut = @"mpTurnstileOutFade";
static NSString * const MPTurnstileKeyTurnIn  = @"mpTurnstileIn";
static NSString * const MPTurnstileKeyFadeIn  = @"mpTurnstileInFade";

// Reduce Motion: на iOS 6 тумблера нет, но ключ читаем честно (см. MPLiveTileView)
static BOOL MPTurnstileMotionAllowed(void) {
    static BOOL value = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id v = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("ReduceMotionEnabled"),
                                                           CFSTR("com.apple.Accessibility")));
        value = !([v isKindOfClass:[NSNumber class]] && [(NSNumber *)v boolValue]);
    });
    return value;
}

static void MPTurnstileRemoveAnims(UIView *v) {
    [v.layer removeAnimationForKey:MPTurnstileKeyTurnOut];
    [v.layer removeAnimationForKey:MPTurnstileKeyFadeOut];
    [v.layer removeAnimationForKey:MPTurnstileKeyTurnIn];
    [v.layer removeAnimationForKey:MPTurnstileKeyFadeIn];
}

static MPHomeController *MPHCLauncher = nil;              // зарегистрирован в MPEnsureLauncher

NSString * const MPTurnstileInDidFinishNotification = @"mpTurnstileInDidFinish";

// Приватные классы SpringBoard для сторожа неудачного запуска (iOS 6.1, селекторы
// сверены с бинарником — тот же путь, что у свитчера многозадачности в Tweak.xm)
@interface SBApplicationController : NSObject
+ (id)sharedInstance;
- (id)applicationWithDisplayIdentifier:(NSString *)identifier;
@end
@interface SBApplication : NSObject
- (BOOL)isRunning;
@end
// SBAppWindow наследует UIWindow и отвечает на isFrontmost (iOS 6.1, сверено с бинарником)
@interface UIWindow (MPFrontmost)
- (BOOL)isFrontmost;
@end

// Живо ли приложение (для сторожа неудачного запуска): SBApplicationController + isRunning
static BOOL MPHAppIsRunning(NSString *bundleID) {
    if (bundleID.length == 0) return NO;
    @try {
        Class cls = objc_getClass("SBApplicationController");
        id ctrl = (cls != nil && [cls respondsToSelector:@selector(sharedInstance)]) ? [(id)cls sharedInstance] : nil;
        id app = (ctrl != nil && [ctrl respondsToSelector:@selector(applicationWithDisplayIdentifier:)])
            ? [ctrl applicationWithDisplayIdentifier:bundleID] : nil;
        return app != nil && [app respondsToSelector:@selector(isRunning)] && [app isRunning];
    } @catch (NSException *e) {
        return NO;
    }
}

// Лаунчер (то есть SpringBoard) сейчас на переднем плане? Наша вьюха живёт в своём
// окне (SBAppWindow); когда поднимается приложение, его окно становится frontmost.
// Селектор isFrontmost сверён с iOS 6.1; при отсутствии — фолбэк на keyWindow.
static BOOL MPHLauncherIsFrontmost(UIView *v) {
    if (v.window == nil) return NO;
    if ([v.window respondsToSelector:@selector(isFrontmost)]) return [v.window isFrontmost];
    id key = [UIApplication sharedApplication].keyWindow;
    return key == nil || key == v.window;
}

@interface MPHomeController () <UIScrollViewDelegate>
@end

@implementation MPHomeController {
    UIScrollView     *_pager;
    MPLiveWidgetsPageView *_widgetsPage;   // страница 0: живые плитки (свайп вправо)
    MPTilesPageView  *_tilesPage;          // страница 1: плитки приложений (стартовая)
    MPAppListPageView *_listPage;          // страница 2: алфавитный список

    BOOL _visible;
    BOOL _contentScheduled;
    BOOL _contentLoaded;
    NSInteger _loadAttempts;

    NSArray *_appsForList;        // свежий список для страницы приложений
    BOOL     _listNeedsReload;    // список изменился, пока его страница была не видна

    BOOL _animatingOpen;          // идёт Turnstile-выезд (повторные тапы игнорируем)
    BOOL _pendingReturn;          // приложение запущено, ждём закрытия окна (Turnstile-въезд)
    NSInteger _turnstileGen;      // поколение перехода: show/hide инвалидируют запланированные блоки
    BOOL _enterInFlight;          // идёт Turnstile-въезд (флипы в это время не стартуют)
    BOOL _deferEnterForLockscreen;// анлок: въезд ждёт сигнала скрытия локскрина
    NSArray *_featherViews;       // элементы feather-стаггера (для идемпотентной уборки)
    BOOL _waitingPose;            // поза ожидания запуска: корень виден (чёрный), контент спрятан
    UIView *_launchSplash;        // WP-сплэш запуска в хост-окне (цвет плитки + иконка + имя)
    UIColor *_pendingSplashColor; // данные сплэша тапнутой плитки (запоминаются на тапе):
    UIImage *_pendingSplashIcon;  // одна панель живёт и в хост-окне, и копией в окне приложения
    NSString *_pendingSplashName;
    UIView *_windowSplash;        // копия сплэша в окне приложения (накрывает zoom и Default.png)
    NSInteger _windowSplashGen;   // поколение снятия сплэша окна (переносится новым контентом)
    BOOL _launchInFlight;         // запуск в ходу: сплэш можно клеить к окну приложения
    BOOL _earlyEntryPlaying;      // ранний feather-въезд под окном приложения играет
    CGFloat _entryStartAngle;     // стартовый угол feather-въезда: −50° (анлок), +50° (возврат из приложения)
    NSTimeInterval _unlockCoverT; // когда корень стал чёрной поверхностью при анлоке (диаг разрыва)

    // Свайп-анлок: прогрев до слайда и въезд по прогрессу слайда (см. prepareUnlockEntry)
    BOOL _unlockPrepared;         // прогрев сыграл: фон + старт-позы feather отрисованы
    BOOL _unlockEntryStarted;     // въезд уже стартовал по прогрессу слайда (двойной запуск запрещён)
    CADisplayLink *_unlockFrameLink; // одноразовая метка первого кадра после прогрева
    NSInteger _unlockSession;     // сессия анлока: +1 на каждом prepare, сброс флагов — только здесь
    NSInteger _turnstileInCount;  // вызовов playTurnstileIn в текущей сессии (должен быть ровно 1)
    CADisplayLink *_unlockTileProbeLink; // замер «отпускание → первая видимая плитка»
    UIView *_unlockTileProbe;     // плитка первой строки, за alpha которой следим
    NSTimeInterval _unlockTileProbeT0;
    NSTimeInterval _unlockReleaseT; // момент отпускания (t=0 замера плитки)

    // Замер FPS перехода (данные для решения о стаггере по строкам)
    CADisplayLink *_fpsLink;
    NSTimeInterval _fpsT0, _fpsLast, _fpsSum, _fpsMax;
    NSInteger _fpsCount, _fpsOver20;
}

+ (MPHomeController *)sharedController { return MPHCLauncher; }
+ (void)setSharedController:(MPHomeController *)c { MPHCLauncher = c; }

// Идёт переход/ожидание возврата: выезд, въезд, прогрев анлока или приложение
// на переднем плане. Живые плитки сверяются перед флипом (бюджет A4 + чистота
// перехода; флип посреди прогрева затёр бы стартовые позы feather).
+ (BOOL)metroTransitionActive {
    MPHomeController *c = MPHCLauncher;
    return c != nil && (c->_pendingReturn || c->_animatingOpen || c->_enterInFlight
                        || c->_unlockPrepared || c->_unlockEntryStarted);
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        // Только подписка — никакого UIKit в init.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appsChanged:)
                                                     name:MPAppsChangedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(mpLockscreenDidHide)
                                                     name:MPMetroLockscreenDidHideNotification
                                                   object:nil];
        MPLog(@"контроллер создан");
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Вьюха

- (void)loadView {
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    // Вью на весь экран (чёрный фон закрывает и область под статус-баром),
    // а содержимое страниц отступает на applicationFrame.origin.y.
    CGFloat top = [MPMetroStyle statusBarInset];

    UIView *root = [[UIView alloc] initWithFrame:bounds];
    root.backgroundColor = [UIColor blackColor];
    self.view = root;

    _pager = [[UIScrollView alloc] initWithFrame:bounds];
    _pager.backgroundColor = [UIColor blackColor];
    _pager.pagingEnabled = YES;
    _pager.delegate = self;                     // чтобы прятать клавиатуру при свайпе к плиткам
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.showsVerticalScrollIndicator = NO;
    _pager.directionalLockEnabled = YES;
    _pager.delaysContentTouches = NO;      // касания сразу уходят страницам
    // Три страницы: [виджеты][плитки][список]; стартуем на плитках (середина)
    _pager.contentSize = CGSizeMake(w * 3.0f, h);
    _pager.contentOffset = CGPointMake(w, 0);
    [root addSubview:_pager];

    _widgetsPage = [[MPLiveWidgetsPageView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    _widgetsPage.topInset = top;
    [_pager addSubview:_widgetsPage];

    _tilesPage = [[MPTilesPageView alloc] initWithFrame:CGRectMake(w, 0, w, h)];
    _tilesPage.topInset = top;
    __weak MPHomeController *weakSelf = self;
    _tilesPage.editingChangedBlock = ^(BOOL editing) {
        MPHomeController *c = weakSelf;
        if (c != nil) c->_pager.scrollEnabled = !editing;      // в правке свайп между страницами выключен
    };
    [_pager addSubview:_tilesPage];

    _listPage = [[MPAppListPageView alloc] initWithFrame:CGRectMake(w * 2.0f, 0, w, h)];
    _listPage.topInset = top;
    [_pager addSubview:_listPage];
}

#pragma mark - Установка

- (void)installLauncherView {
    UIView *v = self.view;
    if (v.superview != nil) return;
    // Главное окно берём из хука SBWallpaperView (в iOS 6.1 sharedApplication.windows
    // пуст, а класса SBScreenView не существует) — см. MPSharedHostWindow.
    UIView *host = MPSharedHostWindow();
    if (host == nil) host = MPHCFindHostView();
    if (host == nil) {
        UIWindow *key = [UIApplication sharedApplication].keyWindow;
        MPLog(@"установка: окно не захвачено (keyWindow=%d, окон=%d) — повтор через 15 с",
              key != nil, (int)[UIApplication sharedApplication].windows.count);
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(installLauncherView) object:nil];
        [self performSelector:@selector(installLauncherView) withObject:nil afterDelay:15.0];
        return;
    }
    v.alpha = 0.0f;
    v.hidden = YES;
    [host addSubview:v];
    // Шарнир Turnstile — левый край: anchorPoint двигаем один раз, кадр компенсируем
    // (сместится position слоя). На фреймы/лэйауты остального кода не влияет.
    CGRect f = v.frame;
    v.layer.anchorPoint = CGPointMake(0.0f, 0.5f);
    v.frame = f;
    MPLog(@"вьюха установлена в %@", NSStringFromClass([host class]));
}


#pragma mark - Показ / скрытие

- (BOOL)isMetroVisible { return _visible; }

- (void)showMetroAnimated:(BOOL)animated {
    [MPMetroStyle reloadPreferences];
    if (![MPMetroStyle isEnabled]) {          // твик выключен в настройках
        [self hideMetroAnimated:NO];
        return;
    }
    MPLog(@"показать Metro (animated=%d)", animated ? 1 : 0);

    UIView *v = self.view;
    [self mpLaunchSplashHide];                  // на случай show/hide посреди позы ожидания
    if (v.superview == nil) [self installLauncherView];
    if (v.superview == nil) return;

    _visible = YES;
    [v.superview bringSubviewToFront:v];

    // Ручной показ сбрасывает любой недоигранный Turnstile (разблокировка посреди перехода).
    // Исключение — лок при открытом приложении: _pendingReturn сохраняем, иначе после
    // анлока возврат из приложения по Home потеряет въезд (Start мелькнёт без анимации).
    BOOL appWasOpen = _pendingReturn;
    _turnstileGen++;
    _animatingOpen = NO;
    _enterInFlight = NO;
    _earlyEntryPlaying = NO;                   // ранний въезд мог играть под окном
    _launchInFlight = NO;
    if (!appWasOpen) _pendingReturn = NO;
    if (!appWasOpen) {                         // из позы ожидания (приложение открыто) контент не возвращаем
        _waitingPose = NO;
        _pager.hidden = NO;
    }
    MPTurnstileRemoveAnims(v);
    [self mpFeatherCleanup];            // недоигранный feather — шарниры/остаточные трансформы
    v.layer.transform = CATransform3DIdentity;

    if (_contentLoaded) {
        [self applyStyleToPages];
        [self flushListIfVisible];      // список мог измениться, пока страница была не видна
    } else {
        [self scheduleContentLoad];
    }

    [[MPLiveTileScheduler sharedScheduler] setAnimPaused:NO];   // плитки снова живут

    if (animated && [MPMetroStyle isEnabled] && MPTurnstileMotionAllowed()) {
        if (_deferEnterForLockscreen) {
            if (_unlockPrepared) {
                // Прогрев (начало драга) уже поставил лаунчер под локскрином: фон и
                // старт-позы feather отрисованы. Чёрная поверхность и mpFeatherCleanup
                // здесь ПОЛЬЗУ затрут бы контент — плитки мигнули бы «нормальным Start»
                MPLog(@"анлок: прогретый лаунчер уже на месте — поверхность не ставим");
                _unlockCoverT = CACurrentMediaTime();
                return;                 // въезд придёт по прогрессу слайда
            }
            // Анлок: до сигнала скрытия локскрина корень обязан быть чёрной
            // НЕПРОЗРАЧНОЙ поверхностью. Журнал 0.22.22: между lockstate и скрытием
            // локскрина ~0.6 с, всё это время root hidden=1 — мелькает родная сетка
            // иконок. Без флага _waitingPose: _pendingReturn здесь нет, распознавание
            // состояний (wantsReturnFromApp/hide/show) не задето; контент вернёт въезд.
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            v.layer.transform = CATransform3DIdentity;
            v.alpha = 1.0f;
            v.hidden = NO;
            _pager.hidden = YES;
            v.userInteractionEnabled = NO;
            [CATransaction commit];
            _unlockCoverT = CACurrentMediaTime();
            MPLog(@"диаг анлок: корень — чёрная поверхность, стол закрыт t=%.3f", _unlockCoverT);
            return;                     // въезд придёт сигналом скрытия локскрина
        }
        [self playTurnstileIn];                 // разблокировка: лаунчер въезжает из-за левого края
    } else {
        _deferEnterForLockscreen = NO;          // неанимированный показ — флаг не нужен
        _waitingPose = NO;
        _pager.hidden = NO;                     // из позы ожидания (если была) — вернуть контент
        v.alpha = 1.0f;
        v.hidden = NO;
    }
}

// Анлок: подготовить показ сразу (lockstate), но въезд — только когда локскрин
// реально скрылся (MPLockscreenDidHide из MLSHideNow). Иначе въезд игрался под
// локскрином и зритель его не видел (замер 0.22.14: анимация закончилась за 0.4 с
// ДО скрытия локскрина). Предел ожидания сигнала — MPAnimLockscreenWaitCap.
- (void)showMetroAfterLockscreen {
    if (_unlockEntryStarted) {
        // Въезд уже играет по прогрессу слайда: очередь не ставим, а showMetroAnimated
        // не зовём вовсе — ветка «чёрной поверхности» перезаписала бы контент
        MPLog(@"анлок: въезд уже играет по прогрессу слайда — очередь не ставим");
        return;
    }
    _deferEnterForLockscreen = YES;             // showMetroAnimated не станет играть въезд сам
    [self showMetroAnimated:YES];
    if (_pendingReturn) {                       // приложение на переднем плане — лаунчер не мигает
        _deferEnterForLockscreen = NO;
        MPLog(@"анлок: приложение открыто — лаунчер остаётся в позе ожидания");
        return;
    }
    if (!MPTurnstileMotionAllowed()) {
        _deferEnterForLockscreen = NO;
        return;
    }
    // Гонка раннего анлока: локскрин запрашивает нативную разблокировку в начале
    // слайда и мог скрыться с досылкой сигнала ЕЩЁ ДО того, как мы встали в
    // очередь (lockstate доходит асинхронно). Повтора сигнала не будет — если
    // локскрин уже не накрывает, въезжаем немедленно, не дожидаясь потолка.
    if (MPLockScreenNotCovering()) {
        _deferEnterForLockscreen = NO;
        MPLog(@"анлок: локскрин уже скрыт — въезд сразу (стол был закрыт %.0f мс)",
              self->_unlockCoverT > 0 ? (CACurrentMediaTime() - self->_unlockCoverT) * 1000.0 : -1.0);
        [self startUnlockEntry];  // единственный вход в въезд: ставит флаг сессии
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimLockscreenWaitCap * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self->_deferEnterForLockscreen) return;
        self->_deferEnterForLockscreen = NO;
        if (self->_unlockEntryStarted) return;  // въезд уже играет по прогрессу слайда
        if (MPLockScreenCoversNative()) {       // локскрин снова виден — анлок не состоялся
            MPLog(@"анлок: локскрин снова накрывает экран — въезд по пределу отменён");
            return;
        }
        if (self->_pendingReturn) return;       // приложение открылось/открыто — въезд не нужен
        MPLog(@"анлок: сигнал скрытия локскрина не пришёл за %.1f с — въезжаем по пределу (стол был закрыт %.0f мс)",
              (double)MPAnimLockscreenWaitCap,
              self->_unlockCoverT > 0 ? (CACurrentMediaTime() - self->_unlockCoverT) * 1000.0 : -1.0);
        [self startUnlockEntry];  // единственный вход в въезд: гейтится флагом сессии
    });
}

// Локскрин скрылся (любой путь через MLSHideNow): очередь на въезд исполнена
- (void)mpLockscreenDidHide {
    if (!_deferEnterForLockscreen) return;
    _deferEnterForLockscreen = NO;
    if (_unlockEntryStarted) {
        // Въезд стартовал по прогрессу слайда — сигнал лишь подтверждает время
        MPLog(@"анлок: локскрин скрыт — въезд уже играет (стартовал по прогрессу)");
        return;
    }
    if (MPLockScreenCoversNative()) {
        // Наш экран снова виден: анлок не состоялся (пружина/код) — въезжать нельзя
        MPLog(@"анлок: локскрин снова накрывает экран — въезд по сигналу отменён");
        return;
    }
    if (_pendingReturn) {
        MPLog(@"анлок: локскрин скрыт, приложение на переднем плане — лаунчер ждёт в позе");
        return;
    }
    MPLog(@"анлок: локскрин скрыт → въезд лаунчера (стол был закрыт %.0f мс)",
          _unlockCoverT > 0 ? (CACurrentMediaTime() - _unlockCoverT) * 1000.0 : -1.0);
    [self startUnlockEntry];  // единственный вход в въезд: гейтится флагом сессии
}

- (void)hideMetroAnimated:(BOOL)animated {
    MPLog(@"спрятать Metro (animated=%d)", animated ? 1 : 0);
    [self mpLaunchSplashHide];                  // лок при запуске: сплэш не переживёт локскрин
    _visible = NO;
    [_tilesPage exitEditingIfNeeded];          // правка завершается с сохранением
    [_listPage dismissKeyboard];
    [[MPLiveTileScheduler sharedScheduler] setAnimPaused:YES];  // переход — плитки стоят

    UIView *v = self.view;
    if (v.superview == nil) return;
    // Блокировка важнее анимации: инвалидируем запланированные переходы и снимаем остатки
    _turnstileGen++;
    _animatingOpen = NO;
    _enterInFlight = NO;
    _earlyEntryPlaying = NO;                   // ранний въезд мог играть под окном
    _launchInFlight = NO;
    _deferEnterForLockscreen = NO;
    _unlockPrepared = NO;
    _unlockEntryStarted = NO;
    MPTurnstileRemoveAnims(v);
    [self mpFeatherCleanup];            // недоигранный feather — шарниры/остаточные трансформы
    v.layer.transform = CATransform3DIdentity;
    if (_waitingPose) {
        // приложение поверх (поза ожидания запуска) — прятать нечего; поза сохраняется
        // вместе с _pendingReturn: после анлока приложение остаётся видимым, а возврат
        // по Home играет въезд как обычно
        return;
    }
    _pendingReturn = NO;

    if (animated && [MPMetroStyle isEnabled] && MPTurnstileMotionAllowed()) {
        // блокировка: лаунчер выезжает поворотом, спрятать в конце выезда
        [self playTurnstileOutWithCompletion:^{
            if (!self->_visible) self.view.hidden = YES;   // за время выезда могли показать снова
        } pressedTile:nil];
    } else {
        v.alpha = 0.0f;
        v.hidden = YES;
    }
}

// Свайп к плиткам = уход со страницы списка: клавиатура прячется
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == _pager) [_listPage dismissKeyboard];
}

// Пока страница списка не видна, таблицу не пересобираем: reloadData на скрытой
// странице — это пересоздание всех ячеек и рывок на ровном месте (см. reloadAppsNow).
// Применяем отложенный reload только ПОСЛЕ остановки страницы: посреди доката
// свайпа он раньше давал рывок ровно в момент въезда списка.
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == _pager) {
        [_listPage dismissKeyboard];
        [self flushListIfVisible];
    }
}

// докат не случился (палец остановил свайп) — страница уже стоит
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == _pager && !decelerate) [self flushListIfVisible];
}

// программный докат setContentOffset:animated:
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (scrollView == _pager) [self flushListIfVisible];
}

#pragma mark - Текущая страница

- (NSInteger)metroCurrentPage {
    CGFloat w = _pager.bounds.size.width;
    if (w < 1.0f) return 1;
    CGFloat x = _pager.contentOffset.x;
    NSInteger page = (NSInteger)floorf((x + w / 2.0f) / w);
    if (page < 0) page = 0;
    if (page > 2) page = 2;
    return page;
}

// Отложенный список применяем только когда его страница реально на экране
- (void)flushListIfVisible {
    if (!_listNeedsReload || _appsForList == nil) return;
    if ([self metroCurrentPage] != 2) return;
    _listNeedsReload = NO;
    [_listPage reloadApps:_appsForList];
}

- (void)homeButtonPressed {
    // как «назад» в WP8: Home завершает правку стартового экрана
    [_tilesPage exitEditingIfNeeded];
}

#pragma mark - Turnstile при запуске/закрытии приложений и показе/скрытии лаунчера

// (ДИАГ-дампы mpDumpPagerViews/mpDumpTileLayers сняты 0.22.32: обход дерева вьюх
// на горячем пути тапа/въезда стоил ощутимой доли кадра на A4 — техдолг отчёта
// 0.22.22 закрыт.)

#pragma mark - Замер FPS перехода (CADisplayLink; данные для решения о стаггере)

- (void)mpFpsStart {
    if (_fpsLink != nil) return;                 // переход в переходе — мерим одним замером
    _fpsCount = 0; _fpsOver20 = 0; _fpsSum = 0; _fpsMax = 0;
    _fpsT0 = _fpsLast = CACurrentMediaTime();
    _fpsLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(mpFpsTick)];
    [_fpsLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)mpFpsTick {
    NSTimeInterval now = CACurrentMediaTime();
    double d = (now - _fpsLast) * 1000.0;
    _fpsLast = now;
    if (_fpsCount > 0) {          // первый интервал — сдвиг фазы от старта, не считаем
        _fpsSum += d;
        if (d > _fpsMax) _fpsMax = d;
        if (d > 20.0) _fpsOver20++;
    }
    _fpsCount++;
}

- (void)mpFpsStop:(NSString *)tag {
    if (_fpsLink == nil) return;
    [_fpsLink invalidate];
    _fpsLink = nil;
    if (_fpsCount < 2) return;
    MPLog(@"анлок-хроника: fps[%@]: %ld кадров, >20 мс: %ld, худший %.1f мс, средний %.1f мс",
          tag, (long)_fpsCount, (long)_fpsOver20, _fpsMax, _fpsSum / (_fpsCount - 1));
}

// ---- Feather-стаггер (TurnstileFeather WP8.1): элементы уходят/въезжают по строкам ----

// Шарнир строки: anchorPoint сдвигается левее левого края (CenterOfRotationX = −0.2,
// как в тулките), position компенсируется, чтобы frame не прыгнул.
// Идемпотентен по anchorPoint: «включить» дважды или «выключить» на вьюхе без
// шарнира — no-op, иначе компенсация position уезжает (реальный сдвиг плиток влево)
static void MPFeatherSetHinge(UIView *v, BOOL on) {
    CGSize s = v.bounds.size;
    if (s.width < 1.0f) return;
    if (on && v.layer.anchorPoint.x == MPAnimFeatherHinge) return;    // шарнир уже стоит
    if (!on && v.layer.anchorPoint.x != MPAnimFeatherHinge) return;   // шарнира не было — восстанавливать нечего
    CGPoint p = v.layer.position;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (on) {
        v.layer.anchorPoint = CGPointMake(MPAnimFeatherHinge, 0.5f);
        v.layer.position = CGPointMake(p.x + (MPAnimFeatherHinge - 0.5f) * s.width, p.y);
    } else {
        v.layer.anchorPoint = CGPointMake(0.5f, 0.5f);
        v.layer.position = CGPointMake(p.x + (0.5f - MPAnimFeatherHinge) * s.width, p.y);
    }
    [CATransaction commit];
}

// Строки видимой страницы для feather, сверху вниз. Плиточная страница — строки
// плиток + заголовок (тапнутая плитка — отдельной последней строкой); виджеты и
// список — вся страница одним элементом.
- (NSArray *)mpFeatherRowsWithPressed:(UIView *)pressed {
    NSMutableArray *rows = [NSMutableArray array];
    NSInteger page = [self metroCurrentPage];
    if (page == 1) {
        NSMutableArray *cur = nil;
        CGFloat lastY = 0;
        for (UIView *el in [_tilesPage featherElements]) {
            // Тапнутая плитка в rows НЕ входит: она уходит последней — её анимирует
            // отдельный вызов после цикла строк. Раньше здесь был «deferred»-ряд,
            // добавлявший её в rows, и она анимировалась ДВАЖДЫ: шарнир ставился
            // дважды, уборка возвращала один раз — плитка навсегда уезжала влево
            // на 0.7·ширины (журнал 0.22.23: Настроек 87.75→38.85, Glow Hockey 163→114.35)
            if (el == pressed) continue;
            CGFloat y = el.frame.origin.y;
            if (cur == nil || fabsf(y - lastY) > 4.0f) {
                cur = [NSMutableArray array];
                [rows addObject:cur];
                lastY = y;
            }
            [cur addObject:el];
        }
    } else {
        UIView *pageView = (page == 0) ? (UIView *)_widgetsPage : (UIView *)_listPage;
        [rows addObject:[NSArray arrayWithObject:pageView]];
    }
    return rows;
}

// Выезд одного элемента: поворот 0°→+50° вокруг своего шарнира + фейд в конце,
// старт с задержкой delay (до своего хода — fromValue за счёт kCAFillModeBoth)
- (void)mpFeatherApplyOutReal:(UIView *)el delay:(NSTimeInterval)delay {
    if (el.bounds.size.width < 1.0f) return;
    MPFeatherSetHinge(el, YES);
    NSTimeInterval bt = CACurrentMediaTime() + delay;

    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform"];
    turn.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    turn.toValue   = [NSValue valueWithCATransform3D:MPAnimTurnstileTransform(MPAnimTurnstileOutAngle)];
    turn.duration  = MPAnimTurnstileOutDur;
    turn.beginTime = bt;
    turn.timingFunction = MPAnimEaseIn();
    turn.fillMode  = kCAFillModeBoth;
    turn.removedOnCompletion = NO;

    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values   = @[@1.0, @1.0, @0.0];
    fade.keyTimes = @[@0.0, @0.95, @1.0];
    fade.duration = MPAnimTurnstileOutDur;
    fade.beginTime = bt;
    fade.fillMode  = kCAFillModeBoth;
    fade.removedOnCompletion = NO;

    [el.layer addAnimation:turn forKey:MPTurnstileKeyTurnOut];
    [el.layer addAnimation:fade forKey:MPTurnstileKeyFadeOut];
}

// Въезд одного элемента — РАБОЧАЯ СХЕМА (проверена сборкой с таймером 0.19 с):
// модель в старт-позе стоит с прогрева; в момент добавления анимаций модель
// переводится в финал, анимации идут сразу (beginTime не трогаем — iOS 6 в этой
// иерархии не играет анимации с beginTime в будущем), Forwards держит финал.
- (void)mpFeatherApplyIn:(UIView *)el delay:(NSTimeInterval)delay {
    if (el.bounds.size.width < 1.0f) return;
    MPFeatherSetHinge(el, YES);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    el.layer.transform = CATransform3DIdentity;
    el.layer.opacity = 1.0f;
    el.layer.speed = 1.0f;      // снять возможную паузу таймлинии
    el.layer.timeOffset = 0.0f;
    el.layer.beginTime = 0.0f;
    [CATransaction commit];
    [el.layer removeAllAnimations]; // висящие анимации (флипы и пр.) — долой

    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform"];
    turn.fromValue = [NSValue valueWithCATransform3D:MPAnimTurnstileTransform(_entryStartAngle)];
    turn.toValue   = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    turn.duration  = MPAnimTurnstileInDur;
    turn.timingFunction = MPAnimEaseOutWP();
    turn.fillMode  = kCAFillModeForwards;
    turn.removedOnCompletion = NO;

    CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeIn.fromValue = @0.0f;
    fadeIn.toValue   = @1.0f;
    fadeIn.duration  = MPAnimTurnstileInDur * 0.3;    // проявление с первых кадров хода
    fadeIn.timingFunction = MPAnimEaseOutWP();
    fadeIn.fillMode  = kCAFillModeForwards;
    fadeIn.removedOnCompletion = NO;

    [el.layer addAnimation:turn forKey:MPTurnstileKeyTurnIn];
    [el.layer addAnimation:fadeIn forKey:MPTurnstileKeyFadeIn];
}

// Полная уборка feather: анимации, шарниры, остаточные transform/opacity.
// Идемпотентна (_featherViews обнуляется) — безопасно звать из show/hide и completion.
- (void)mpFeatherCleanup {
    for (UIView *v in _featherViews) {
        [v.layer removeAnimationForKey:MPTurnstileKeyTurnOut];
        [v.layer removeAnimationForKey:MPTurnstileKeyFadeOut];
        [v.layer removeAnimationForKey:MPTurnstileKeyTurnIn];
        [v.layer removeAnimationForKey:MPTurnstileKeyFadeIn];
        MPFeatherSetHinge(v, NO);
        v.layer.transform = CATransform3DIdentity;
        v.layer.opacity = 1.0f;
    }
    _featherViews = nil;
}

#pragma mark - Свайп-анлок: прогрев лаунчера и въезд по прогрессу слайда

// Стартовая поза feather-элемента БЕЗ анимаций (−50°/alpha 0): до своего
// beginTime плитка НЕ видна (задержка старта 0.10 с у анлока), появление —
// из анимации fadeIn (ramp 0.3→1)
- (void)mpFeatherApplyInStartPose:(UIView *)el {
    if (el.bounds.size.width < 1.0f) return;
    MPFeatherSetHinge(el, YES);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    el.layer.transform = MPAnimTurnstileTransform(MPAnimTurnstileInAngle);
    el.layer.opacity = 0.0f;
    [CATransaction commit];
}

// Первый тик display link после коммита прогрева = кадр ушёл в рендер
- (void)mpUnlockFrameTick {
    MPLog(@"анлок-хроника: первый кадр лаунчера отрисован t=%.3f", CACurrentMediaTime());
    [_unlockFrameLink invalidate];
    _unlockFrameLink = nil;
}

// Прогрев: звать при НАЧАЛЕ вертикального драга на локскрине (до порога анлока).
// Лаунчер показывается ПОД окном локскрина: фон и статусбар на месте, feather-
// элементы — в стартовых позах въезда. Пока локскрин уезжает, в освобождающейся
// области виден фон лаунчера, а при старте turnstile не теряется ни один кадр
// на layout/рендер. Приложение поверх (_pendingReturn) — не прогреваем.
- (void)prepareUnlockEntry {
    if (_unlockEntryStarted) return;          // въезд уже играет — прогрев не нужен
    if (_pendingReturn || ![MPMetroStyle isEnabled]) return;
    UIView *v = self.view;
    if (v.superview == nil) [self installLauncherView];
    if (v.superview == nil) return;

    // Новая сессия анлока: флаг «въезд стартовал» сбрасывается ТОЛЬКО здесь —
    // посреди сессии его никто не трогает, иначе въезд играется дважды
    _unlockSession++;
    _turnstileInCount = 0;
    _unlockPrepared = YES;
    MPLog(@"анлок-хроника: прогрев старт (сессия %ld) t=%.3f", (long)_unlockSession, CACurrentMediaTime());
    [MPMetroStyle reloadPreferences];
    if (!_contentLoaded) {
        // Синхронный прогрев (ТЗ п.3): после respring контент не успевал
        // загрузиться к анлоку — turnstile уходил в фолбэк целого слоя.
        // Тяжело, но это НАЧАЛО драга, а не горячий путь анимации.
        [self loadContent];
    }
    [self applyStyleToPages];
    [self flushListIfVisible];
    [self.view layoutIfNeeded];      // раскладка страниц до слайда — feather-ветка всегда
    [_tilesPage layoutIfNeeded];

    NSArray *rows = [self mpFeatherRowsWithPressed:nil];
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray *row in rows) [all addObjectsFromArray:row];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    v.hidden = NO;
    v.alpha = 1.0f;
    v.layer.transform = CATransform3DIdentity;
    MPTurnstileRemoveAnims(v);
    [v.superview bringSubviewToFront:v];   // над родной сеткой, под окном локскрина
    _visible = YES;
    _waitingPose = NO;
    _pager.hidden = NO;
    [CATransaction commit];

    if (rows.count > 0) {
        _featherViews = all;
        for (UIView *el in all) [self mpFeatherApplyInStartPose:el];
    }
    [[MPLiveTileScheduler sharedScheduler] setAnimPaused:YES]; // флипы не затрут старт-позы

    // Метка первого кадра: один тик display link после коммита
    _unlockFrameLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(mpUnlockFrameTick)];
    [_unlockFrameLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

// Въезд в момент отпускания пальца (t=0, вместе со слайдом): фон уже отрисован
// прогревом, стартовые позы стоят — turnstile поедет от готового кадра.
// Подтверждение анлока на старт не влияет; пасскод и отключённый твик — гейты.
- (void)startUnlockEntry {
    if (_unlockEntryStarted) return;
    if (_enterInFlight) {
        // Въезд уже играет (feather на слоях) — второй старт вернул бы плитки
        // в старт-позы посреди анимации (двойное проигрывание с тёмным кадром)
        MPLog(@"анлок: въезд уже идёт (enterInFlight) — повторный старт пропущен");
        return;
    }
    _unlockEntryStarted = YES;
    _unlockPrepared = NO;                    // прогрев исполнен, cleanup — по completion
    if (_pendingReturn) {
        MPLog(@"анлок: приложение на переднем плане — въезд по прогрессу не нужен");
        return;
    }
    MPLog(@"анлок-хроника: отпускание (turnstile через %.0f мс, сессия %ld) t=%.3f",
          MPAnimUnlockEntryDelay * 1000.0, (long)_unlockSession, CACurrentMediaTime());
    _unlockReleaseT = CACurrentMediaTime();      // t=0 для замера «первая видимая плитка»
    UIView *v = self.view;
    if (![MPMetroStyle isEnabled] || !MPTurnstileMotionAllowed()) {
        // без анимаций: контент уже в старт-позах (если был прогрев) — просто показать
        [self mpFeatherCleanup];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.hidden = NO;
        v.alpha = 1.0f;
        v.layer.transform = CATransform3DIdentity;
        _pager.hidden = NO;
        _waitingPose = NO;
        [CATransaction commit];
        return;
    }
    // РАБОЧАЯ СХЕМА: задержка — dispatch_after на main, затем playTurnstileIn
    // (обычные CABasicAnimation без beginTime — iOS 6 не играет анимации с
    // beginTime в будущем). До срабатывания плитки в старт-позе (alpha 0).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimUnlockEntryDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self->_unlockEntryStarted || self->_pendingReturn) return; // лок/приложение за 0.12 с
        [self playTurnstileIn];
        [self mpUnlockTileProbeStart]; // замер: отпускание → первая видимая плитка
    });
}

// Замер ТЗ: мс от отпускания пальца (t=0 въезда) до alpha>0.2 на плитке первой
// строки. Считывается с presentation-слоя — честный видимый результат.
- (void)mpUnlockTileProbeStart {
    [_unlockTileProbeLink invalidate];
    _unlockTileProbeLink = nil;
    _unlockTileProbe = nil;
    for (UIView *el in _featherViews) { _unlockTileProbe = el; break; } // первый = первая строка
    if (_unlockTileProbe == nil) {
        MPLog(@"анлок-хроника: замер плитки: feather-элементов нет (пустая страница)");
        return;
    }
    _unlockTileProbeT0 = _unlockReleaseT; // мери от отпускания, а не от старта замера
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(mpUnlockTileProbeTick)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    _unlockTileProbeLink = link;
}

- (void)mpUnlockTileProbeTick {
    if (_unlockTileProbe == nil) return;
    CALayer *pres = _unlockTileProbe.layer.presentationLayer;
    NSTimeInterval now = CACurrentMediaTime();
    if (pres != nil && pres.opacity > 0.2) {
        MPLog(@"анлок-хроника: первая видимая плитка через %.0f мс от отпускания",
              (now - _unlockTileProbeT0) * 1000.0);
        [_unlockTileProbeLink invalidate];
        _unlockTileProbeLink = nil;
        _unlockTileProbe = nil;
        return;
    }
    if (now - _unlockTileProbeT0 > 1.0) { // плитка так и не проявилась — фиксируем провал
        MPLog(@"анлок-хроника: замер плитки: alpha>0.2 не достигнута за 1.0 с");
        [_unlockTileProbeLink invalidate];
        _unlockTileProbeLink = nil;
        _unlockTileProbe = nil;
    }
}

// Провал анлока (разблокировка не прошла, экран вернулся пружиной): прогретый/
// стартовавший лаунчер прячем мгновенно и снимаем старт-позы
- (void)cancelUnlockEntry {
    if (!_unlockPrepared && !_unlockEntryStarted) return;
    MPLog(@"анлок: отмена — разблокировка не прошла, прогретый лаунчер прячется");
    [_unlockTileProbeLink invalidate];
    _unlockTileProbeLink = nil;
    _unlockTileProbe = nil;
    _unlockPrepared = NO;
    _unlockEntryStarted = NO;
    _turnstileGen++;
    UIView *v = self.view;
    MPTurnstileRemoveAnims(v);
    [self mpFeatherCleanup];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    v.hidden = YES;
    v.alpha = 1.0f;
    v.layer.transform = CATransform3DIdentity;
    [CATransaction commit];
    _visible = NO;
}

// Turnstile-выезд: feather по строкам (0°→+50° + фейд в последних 10 мс каждого
// элемента, корень стоит — под ним чёрный фон); без строк (пустая страница) —
// поворот целым слоем, как раньше. По завершении (проверка по _turnstileGen)
// уборка feather и done.
- (void)playTurnstileOutWithCompletion:(void (^)(void))done pressedTile:(UIView *)pressed {
    UIView *v = self.view;
    _turnstileGen++;
    NSInteger gen = _turnstileGen;
    MPLog(@"turnstile: feather-выезд (0°→50°) t=%.3f", CACurrentMediaTime());
    NSTimeInterval t0 = CACurrentMediaTime();   // для замера запаздывания completion
    [self mpFpsStart];

    NSArray *rows = [self mpFeatherRowsWithPressed:pressed];
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray *row in rows) [all addObjectsFromArray:row];
    if (pressed != nil && ![all containsObject:pressed]) [all addObject:pressed];

    NSTimeInterval total = MPAnimTurnstileOutDur;
    if (rows.count > 0) {
        total = MPAnimTurnstileOutDur + (rows.count + (pressed != nil ? 1 : 0)) * MPAnimFeatherStagger;
        _featherViews = all;
        MPLog(@"диаг feather: выезд %ld строк, %ld элементов, всего %.2f с",
              (long)rows.count, (long)all.count, (double)total);
    }

    // ВАЖНО: анимации добавляются ВНУТРИ транзакции completion — пустая транзакция
    // срабатывает при коммите и обрезает переход (поймано журналом дважды)
    [CATransaction begin];
    [CATransaction setAnimationDuration:total];
    [CATransaction setCompletionBlock:^{
        [self mpFpsStop:@"выезд"];
        if (gen != self->_turnstileGen) {
            MPLog(@"диаг turnstileOut completion ОТСЕЧЁН (gen %ld != %ld)",
                  (long)gen, (long)self->_turnstileGen);
            [self mpFeatherCleanup];       // show/hide могли не успеть — убираем сами
            return;
        }
        MPLog(@"диаг turnstileOut completion сработал t=%.3f (запаздывание %.0f мс)",
              CACurrentMediaTime(),
              (CACurrentMediaTime() - t0 - total) * 1000.0);
        [self mpFeatherCleanup];
        UIView *vv = self.view;
        MPTurnstileRemoveAnims(vv);
        vv.layer.transform = CATransform3DIdentity;
        vv.alpha = 1.0f;
        if (done) done();
    }];
    if (rows.count == 0) {
        // фолбэк: поворот целым слоем (страница пуста или не собрана)
        CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform"];
        turn.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        turn.toValue   = [NSValue valueWithCATransform3D:MPAnimTurnstileTransform(MPAnimTurnstileOutAngle)];
        turn.duration  = MPAnimTurnstileOutDur;
        turn.timingFunction = MPAnimEaseIn();
        turn.fillMode  = kCAFillModeForwards;
        turn.removedOnCompletion = NO;
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values   = @[@1.0, @1.0, @0.0];
        fade.keyTimes = @[@0.0, @0.95, @1.0];
        fade.duration = MPAnimTurnstileOutDur;
        fade.fillMode  = kCAFillModeForwards;
        fade.removedOnCompletion = NO;
        [v.layer addAnimation:turn forKey:MPTurnstileKeyTurnOut];
        [v.layer addAnimation:fade forKey:MPTurnstileKeyFadeOut];
    } else {
        // feather: элементы уходят по строкам, тапнутая — последней
        NSInteger r = 0;
        BOOL pressedInRows = NO;
        for (NSArray *row in rows) {
            NSTimeInterval delay = r * MPAnimFeatherStagger;
            if ([row containsObject:pressed]) pressedInRows = YES;   // страховка от двойного шарнира
            for (UIView *el in row) [self mpFeatherApplyOutReal:el delay:delay];
            r++;
        }
        if (pressed != nil && !pressedInRows) [self mpFeatherApplyOutReal:pressed delay:r * MPAnimFeatherStagger];
    }
    [CATransaction commit];
}

// Turnstile-въезд: feather по строкам сверху вниз с проявлением; без строк —
// поворот целым слоем. Стартовые позы ставятся ДО показа — ни одного кадра
// нормального Start до анимации. Угол: −50° у анлока (из-за левого края),
// +50° при возврате из приложения (с противоположной стороны, по спеку).
- (void)playTurnstileIn {
    [self playTurnstileInFromAngle:MPAnimTurnstileInAngle];
}

- (void)playTurnstileInFromAngle:(CGFloat)startAngle {
    _entryStartAngle = startAngle;
    UIView *v = self.view;
    [self mpLaunchSplashHide];                  // сплэш запуска не доживает до въезда
    _turnstileGen++;
    NSInteger gen = _turnstileGen;
    _enterInFlight = YES;
    _turnstileInCount++;
    BOOL animsAlready = NO;
    for (UIView *el in _featherViews) {
        if ([el.layer animationKeys].count > 0) { animsAlready = YES; break; }
    }
    // Каждый вызов — под номер и флаги: двойное проигрывание видно сразу
    MPLog(@"turnstile: въезд #%ld (сессия %ld, inFlight=%d, анимации=%d)%@ t=%.3f",
          (long)_turnstileInCount, (long)_unlockSession, _enterInFlight ? 1 : 0,
          animsAlready ? 1 : 0,
          _earlyEntryPlaying ? @" РАННИЙ (под окном)" : @"", CACurrentMediaTime());

    NSTimeInterval tIn0 = CACurrentMediaTime();   // для замера запаздывания completion
    [self mpFpsStart];

    NSArray *rows = [self mpFeatherRowsWithPressed:nil];
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray *row in rows) [all addObjectsFromArray:row];

    NSTimeInterval total = MPAnimTurnstileInDur;
    if (rows.count > 0) {
        // корень сразу виден и неподвижен (фон чёрный). РАННИЙ въезд (под окном
        // приложения): z-порядок не трогаем — подниматься будем по факту ухода окна
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.layer.transform = CATransform3DIdentity;
        v.alpha = 1.0f;
        v.hidden = NO;
        v.userInteractionEnabled = YES;
        _pager.hidden = NO;                     // выход из позы ожидания — вернуть контент
        _waitingPose = NO;
        if (!_earlyEntryPlaying) [v.superview bringSubviewToFront:v];
        [CATransaction commit];

        total = MPAnimTurnstileInDur + rows.count * MPAnimFeatherStagger;
        _featherViews = all;
        MPLog(@"диаг feather: въезд %ld строк, %ld элементов, всего %.2f с",
              (long)rows.count, (long)all.count, (double)total);
    } else {
        // фолбэк: модель целого слоя сразу в финальной позе (держит from-анимация)
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.layer.transform = CATransform3DIdentity;
        v.alpha = 1.0f;
        v.hidden = NO;
        v.userInteractionEnabled = YES;
        _pager.hidden = NO;
        _waitingPose = NO;
        if (!_earlyEntryPlaying) [v.superview bringSubviewToFront:v];
        [CATransaction commit];
    }

    // ВАЖНО: анимации добавляются ВНУТРИ транзакции completion — пустая транзакция
    // срабатывает при коммите и обрезает переход (поймано журналом дважды)
    [CATransaction begin];
    [CATransaction setAnimationDuration:total];
    [CATransaction setCompletionBlock:^{
        [self mpFpsStop:@"въезд"];
        self->_enterInFlight = NO;
        [[MPLiveTileScheduler sharedScheduler] setAnimPaused:NO];   // плитки снова живут
        if (gen != self->_turnstileGen) {
            MPLog(@"диаг turnstileIn completion ОТСЕЧЁН (gen %ld != %ld)",
                  (long)gen, (long)self->_turnstileGen);
            [self mpFeatherCleanup];       // show/hide могли не успеть — убираем сами
            return;        // show/hide уже всё сбросили
        }
        MPLog(@"диаг turnstileIn completion сработал t=%.3f (запаздывание %.0f мс)",
              CACurrentMediaTime(),
              (CACurrentMediaTime() - tIn0 - total) * 1000.0);
        [self mpFeatherCleanup];
        UIView *vv = self.view;
        [vv.layer removeAnimationForKey:MPTurnstileKeyTurnIn];
        [vv.layer removeAnimationForKey:MPTurnstileKeyFadeIn];
        vv.layer.transform = CATransform3DIdentity;
        vv.alpha = 1.0f;
        [[NSNotificationCenter defaultCenter] postNotificationName:MPTurnstileInDidFinishNotification
                                                            object:self];
    }];
    if (rows.count == 0) {
        // фолбэк: видимый въезд целого слоя — alpha 0→1 + лёгкий scale 0.94→1
        CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeIn.fromValue = @0.0f;
        fadeIn.toValue   = @1.0f;
        fadeIn.duration  = MPAnimTurnstileInDur;
        fadeIn.timingFunction = MPAnimEaseOutWP();
        fadeIn.fillMode  = kCAFillModeForwards;
        fadeIn.removedOnCompletion = NO;
        CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scale.fromValue = @0.94f;
        scale.toValue   = @1.0f;
        scale.duration  = MPAnimTurnstileInDur;
        scale.timingFunction = MPAnimEaseOutWP();
        scale.fillMode  = kCAFillModeForwards;
        scale.removedOnCompletion = NO;
        [v.layer addAnimation:fadeIn forKey:MPTurnstileKeyFadeIn];
        [v.layer addAnimation:scale forKey:MPTurnstileKeyTurnIn];
    } else {
        // feather: анимации элементов ВНУТРИ транзакции (иначе completion ранний).
        // Строки сверху вниз, внутри строки — слева направо (5 мс на плитку);
        // задержка старта (0.10 с у анлока) — через beginTime, не через таймеры
        NSInteger r = 0;
        for (NSArray *row in rows) {
            NSTimeInterval delay = r * MPAnimFeatherStagger;
            NSArray *sorted = [row sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
                CGFloat xa = a.frame.origin.x, xb = b.frame.origin.x;
                return (xa < xb) ? NSOrderedAscending : ((xa > xb) ? NSOrderedDescending : NSOrderedSame);
            }];
            NSInteger j = 0;
            for (UIView *el in sorted) {
                [self mpFeatherApplyIn:el delay:delay + j * MPAnimFeatherIntraStagger];
                j++;
            }
            r++;
        }
    }
    [CATransaction commit];
}

// Выезд лаунчера при запуске приложения (0.22.32): launch зовётся СРАЗУ (спавн
// ~0.9 с идёт параллельно анимации, а не после неё), Start уезжает влево одним
// слоем, навстречу подъезжает WP-сплэш. pressedTile — тапнутая плитка (данные
// сплэша: цвет/иконка/имя). bundleID — для сторожа неудачного запуска (nil → сторожа нет).
- (BOOL)playAppOpenAnimationForBundleID:(NSString *)bundleID
                            pressedTile:(UIView *)pressedTile
                                 launch:(void (^)(void))launch {
    if (launch == nil) { MPLog(@"диаг playAppOpen: отказ launch=nil"); return NO; }
    if (_animatingOpen) { MPLog(@"диаг playAppOpen: повторный тап ГЛОТАЕТСЯ (_animatingOpen)"); return YES; }
    if (!_visible || ![MPMetroStyle isEnabled]) {
        MPLog(@"диаг playAppOpen: отказ visible=%d вкл=%d", _visible, [MPMetroStyle isEnabled]);
        return NO;
    }
    if (!MPTurnstileMotionAllowed()) {
        MPLog(@"диаг playAppOpen: отказ ReduceMotion");
        return NO;
    }

    UIView *v = self.view;
    if (v.superview == nil || v.hidden) {
        MPLog(@"диаг playAppOpen: отказ superview=%@ hidden=%d",
              v.superview ? NSStringFromClass(v.superview.class) : @"nil", v.hidden);
        return NO;
    }

    MPLog(@"playAppOpen: %@ выезд t=%.3f", bundleID.length > 0 ? bundleID : @"виджет", CACurrentMediaTime());
    [[MPLiveTileScheduler sharedScheduler] setAnimPaused:YES];  // переход — плитки стоят
    _animatingOpen = YES;
    _launchInFlight = YES;
    [self mpSplashRememberForTile:pressedTile];

    // Запуск ПЕРВЫМ делом: системный спавн (~0.9 с) перекрывается анимацией выезда.
    _pendingReturn = YES;
    launch();
    // Сторож неудачного запуска от t=0. Приложение: не поднялось и не живо за
    // MPAnimLaunchWatchdog — въезжаем сами (крэш/отказ, пустой экран недопустим).
    // Виджет с URL-целью: страховка MPAnimWidgetInsurance — если SpringBoard всё
    // ещё frontmost, URL ничего не открыл и лаунчер обязан вернуться.
    NSInteger wgen = _turnstileGen;
    NSTimeInterval wait = (bundleID.length > 0) ? MPAnimLaunchWatchdog : MPAnimWidgetInsurance;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (wgen != self->_turnstileGen) {
            // въезд уже играется/сыгран, был show/hide или новый запуск — не наше
            MPLog(@"диаг сторож: пропущен (gen изменился %ld != %ld)",
                  (long)wgen, (long)self->_turnstileGen);
            return;
        }
        if (!self->_pendingReturn) return;           // окно закрылось штатно
        if (!MPHLauncherIsFrontmost(self.view)) return;  // окно приложения уже показалось
        if (bundleID.length > 0) {
            if (MPHAppIsRunning(bundleID)) {         // приложение живо — ждём возврат
                MPLog(@"диаг сторож: %@ живо, сторож стоит вниз", bundleID);
                return;
            }
            MPLog(@"диаг сторож: %@ не поднялось за %.1f с → принудительный въезд",
                  bundleID, (double)wait);
        } else {
            MPLog(@"страховка виджета: сработала (%.1f с, SpringBoard frontmost) → въезд",
                  (double)wait);
        }
        self->_launchInFlight = NO;
        [self appWindowDidHide];
    });

    void (^waitingPose)(void) = ^{
        // Поза ожидания: корень ВИДЕН чёрным (пейджер спрятан). Раньше корень был
        // alpha 0 — сквозь него просвечивала РОДНАЯ сетка иконок SpringBoard во
        // время системного zoom запуска. Сплэш уже накрывает экран; из позы
        // ожидания выход только по сигналу закрытия окна приложения.
        UIView *vv = self.view;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        vv.layer.transform = CATransform3DIdentity;
        vv.alpha = 1.0f;
        vv.hidden = NO;
        _pager.hidden = YES;                   // чёрная поверхность вместо сетки иконок
        vv.userInteractionEnabled = NO;
        [CATransaction commit];
        self->_waitingPose = YES;
        self->_animatingOpen = NO;
    };

    // Turnstile по спеку: Start закрывается дверью (0°→+50°, петля слева), затем
    // окно приложения раскрывается из −80° (в своём процессе). Паузы между ними нет:
    // у тёплого запуска окно уже живо — Darwin-сигнал раскроет его сразу после
    // выезда Start; у холодного спавна паузу закрывает сплэш в позе ожидания.
    [self playStartFoldOutWithCompletion:^{
        waitingPose();
        MPHomePostDarwin(CFSTR("ru.ash.metrophone.appopen"));   // тёплому окну — unfold
        [self mpSplashUntilAppWindow];                          // сплэш только для холодного спавна
    }];
    return YES;
}

// Darwin-сигнал всем процессам (приложение слушает appopen/appclose и поворачивает
// своё окно — из SpringBoard окно чужого процесса не достать)
void MPHomePostDarwin(CFStringRef name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         name, NULL, NULL, YES);
}

// Fold-out Start (0.22.32): целый слой 0°→+50°, петля — левый край экрана
// (anchorPoint корня (0,0.5) выставлен при установке), фейд в последних кадрах.
// Одна дверь вместо feather-рядов — «хаотично схлопывающиеся плитки» убраны.
- (void)playStartFoldOutWithCompletion:(void (^)(void))done {
    UIView *v = self.view;
    _turnstileGen++;
    NSInteger gen = _turnstileGen;
    MPLog(@"turnstile: fold-out Start (0°→+50°) t=%.3f", CACurrentMediaTime());
    [self mpFpsStart];

    // ВАЖНО: анимации добавляются ВНУТРИ транзакции completion — пустая транзакция
    // срабатывает при коммите и обрезает переход (поймано журналом дважды)
    [CATransaction begin];
    [CATransaction setAnimationDuration:MPAnimStartFoldDur];
    [CATransaction setCompletionBlock:^{
        [self mpFpsStop:@"выезд-дверь"];
        if (gen != self->_turnstileGen) return;   // show/hide/лок сами всё почистят
        MPTurnstileRemoveAnims(self.view);
        if (done) done();
    }];
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform"];
    turn.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    turn.toValue   = [NSValue valueWithCATransform3D:MPAnimTurnstileTransform(MPAnimTurnstileOutAngle)];
    turn.duration  = MPAnimStartFoldDur;
    turn.timingFunction = MPAnimEaseIn();
    turn.fillMode  = kCAFillModeForwards;
    turn.removedOnCompletion = NO;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values   = @[@1.0, @1.0, @0.0];
    fade.keyTimes = @[@0.0, @0.9, @1.0];
    fade.duration = MPAnimStartFoldDur;
    fade.fillMode  = kCAFillModeForwards;
    fade.removedOnCompletion = NO;
    [v.layer addAnimation:turn forKey:MPTurnstileKeyTurnOut];
    [v.layer addAnimation:fade forKey:MPTurnstileKeyFadeOut];
    [CATransaction commit];
}

// Сплэш в позе ожидания — только для холодного спавна: если окно приложения уже
// показалось (тёплый запуск), панель не нужна вовсе. Иначе показываем и снимаем
// по факту появления окна (опрос frontmost); предел — сторож запуска.
- (void)mpSplashUntilAppWindow {
    if (MPHLauncherIsFrontmost(self.view)) return;   // окно уже тут — чистый turnstile
    [self mpLaunchSplashShowForTileAnimated:NO];
    [self mpSplashWindowPollGen:_turnstileGen t0:CACurrentMediaTime()];
}

- (void)mpSplashWindowPollGen:(NSInteger)gen t0:(NSTimeInterval)t0 {
    if (gen != _turnstileGen) return;                // show/hide/въезд сами сняли сплэш
    if (MPHLauncherIsFrontmost(self.view)) {
        MPLog(@"сплэш: окно показалось через %.0f мс — панель снята",
              (CACurrentMediaTime() - t0) * 1000.0);
        [self mpLaunchSplashHide];
        return;
    }
    if (CACurrentMediaTime() - t0 >= MPAnimLaunchWatchdog) {
        [self mpLaunchSplashHide];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimSplashWindowPoll * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self mpSplashWindowPollGen:gen t0:t0]; });
}

// Лочок для Home-фолбэка: заблокированный телефон переходы не играет
static BOOL MPHCLocked(void) {
    id away = [objc_getClass("SBAwayController") sharedAwayController];
    return away != nil && [away respondsToSelector:@selector(isLocked)] && [away isLocked];
}

// От хука SBAppWindow setHidden:. На iOS 6 при закрытии приложения setHidden:YES
// может не приходить (окно не нашего класса или гасится иначе) — тогда возврат
// ведёт Home-фолбэк с ранним въездом. hidden=NO — окно приложения показалось:
// клеим копию сплэша (если запуск ещё в ходу и сплэша там ещё нет).
- (void)noteAppWindowHidden:(BOOL)hidden forWindow:(UIWindow *)w {
    if (!_pendingReturn && _windowSplash == nil) return;
    MPLog(@"turnstile: SBAppWindow setHidden:%d", hidden ? 1 : 0);
    if (hidden) {
        [self appWindowDidHide];
    } else {
        [self mpWindowSplashAttachToWindow:w];
    }
}

// Home-фолбэк: можно ли по нажатию Home вернуть лаунчер Turnstile-въездом
- (BOOL)wantsReturnFromApp {
    BOOL want = YES;
    if (!_pendingReturn || _animatingOpen) want = NO;
    UIView *v = self.view;
    // поза ожидания = корень виден чёрным, пейджер спрятан (см. запуск)
    if (v.superview == nil || !_waitingPose) want = NO;
    if (MPHCLocked() || ![MPMetroStyle isEnabled] || !MPTurnstileMotionAllowed()) want = NO;
    MPLog(@"диаг wantsReturn=%d pending=%d animOpen=%d visible=%d waiting=%d",
          want, _pendingReturn, _animatingOpen, _visible, _waitingPose);
    return want;
}

// Окно приложения скрылось: лаунчер въезжает. Если ранний feather-въезд уже
// играет под окном — только поднять лаунчер на фронт (въезд доигрывает сам).
- (void)appWindowDidHide {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self appWindowDidHide]; });
        return;
    }
    _launchInFlight = NO;
    [self mpLaunchSplashHide];                  // сплэш запуска больше не нужен
    MPLog(@"диаг appWindowDidHide t=%.3f pending=%d visible=%d early=%d",
          CACurrentMediaTime(), _pendingReturn, _visible, _earlyEntryPlaying);
    if (!_pendingReturn) return;
    if (_earlyEntryPlaying) {
        [self mpReturnCommitEarlyEntry];
        return;
    }
    _pendingReturn = NO;
    if (!_visible || ![MPMetroStyle isEnabled]) return; // блокировка/выключение — show/hide сами разберутся
    if (!MPTurnstileMotionAllowed()) {
        // Reduce Motion: без анимации — сразу нормальное состояние из позы ожидания
        UIView *vv = self.view;
        MPTurnstileRemoveAnims(vv);
        [self mpFeatherCleanup];
        vv.layer.transform = CATransform3DIdentity;
        vv.alpha = 1.0f;
        vv.hidden = NO;
        _pager.hidden = NO;
        _waitingPose = NO;
        vv.userInteractionEnabled = YES;
        return;
    }
    [self playTurnstileIn];
}

#pragma mark - Возврат из приложения: ранний feather-въезд под окном

// Домашний фолбэк (0.22.32): feather-въезд стартует СРАЗУ, пока окно приложения
// ещё на экране. Лаунчер остаётся ПОД окном (playTurnstileIn не поднимает его на
// фронт) — двойная экспозиция «Start поверх гаснущего приложения» невозможна
// физически. Когда окно реально уйдёт (обычно 0.1–0.3 с), въезд уже в разгаре —
// переход непрерывный, без чёрного провала. Прежняя схема («опрос → потом въезд»)
// давала: окно исчезло → чёрная поза ожидания → 60 мс грейса → 0.5 с въезда.
- (void)scheduleReturnFromApp {
    if (_earlyEntryPlaying) return;           // въезд уже играет по прошлому Home
    _earlyEntryPlaying = YES;
    MPLog(@"возврат: ранний feather-въезд под окном t=%.3f", CACurrentMediaTime());
    // Окно приложения складывается в −80° само (Darwin-сигнал в его процесс),
    // плитки стартуют сразу же — паузы нет, один непрерывный поворот
    MPHomePostDarwin(CFSTR("ru.ash.metrophone.appclose"));
    [self playTurnstileInFromAngle:MPAnimTurnstileOutAngle];   // с противоположной стороны (+50°)
    NSInteger gen = _turnstileGen;            // ПОСЛЕ playTurnstileIn (он растит поколение)
    [self mpReturnPollTickGen:gen t0:CACurrentMediaTime()];
}

// Окно реально ушло: ранний въезд подтверждён — поднять лаунчер на фронт и свести
// переход. Въезд при этом продолжает доигрывать (или уже доиграл).
- (void)mpReturnCommitEarlyEntry {
    _earlyEntryPlaying = NO;
    _pendingReturn = NO;
    UIView *v = self.view;
    if (v.superview != nil) [v.superview bringSubviewToFront:v];
    MPLog(@"возврат: окно ушло — лаунчер поднят (въезд%s доигрывает)",
          _enterInFlight ? "" : " уже");
}

// Окно не ушло за MPAnimReturnPollCap (Home не сработал / SpringBoard лагает):
// тихий откат под окном — зритель ничего не видит. Возвращаем позу ожидания,
// снимаем feather; _pendingReturn сохраняем. Окно всё же уйдёт → setHidden: или
// продолженный опрос сведут переход обычным въездом по факту.
- (void)mpReturnRollbackEarlyEntry {
    if (!_earlyEntryPlaying) return;
    _earlyEntryPlaying = NO;
    _turnstileGen++;                          // отсечь completion игравшего въезда
    _enterInFlight = NO;
    [self mpFeatherCleanup];                  // шарниры/анимации/старт-позы — долой
    UIView *v = self.view;
    MPTurnstileRemoveAnims(v);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    v.layer.transform = CATransform3DIdentity;
    v.alpha = 1.0f;
    v.hidden = NO;
    _pager.hidden = YES;                      // обратно в позу ожидания
    v.userInteractionEnabled = NO;
    [CATransaction commit];
    _waitingPose = YES;
    MPLog(@"возврат: окно не ушло за %.1f с — откат в позу ожидания",
          (double)MPAnimReturnPollCap);
}

- (void)mpReturnPollTickGen:(NSInteger)gen t0:(NSTimeInterval)t0 {
    if (gen != _turnstileGen) {                 // show/hide/новый запуск — не наш переход
        _earlyEntryPlaying = NO;
        MPLog(@"диаг возврат: опрос прерван (gen изменился %ld != %ld)",
              (long)gen, (long)_turnstileGen);
        return;
    }
    if (!_pendingReturn) {                      // setHidden: или другой путь уже свёл переход
        _earlyEntryPlaying = NO;
        return;
    }
    if (MPHLauncherIsFrontmost(self.view)) {
        MPLog(@"диаг возврат: окно приложения реально ушло через %.0f мс",
              (CACurrentMediaTime() - t0) * 1000.0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimReturnGrace * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self->_pendingReturn && gen == self->_turnstileGen) [self mpReturnCommitEarlyEntry];
        });
        return;
    }
    if (CACurrentMediaTime() - t0 >= MPAnimReturnPollCap) {
        [self mpReturnRollbackEarlyEntry];
        // Окно может уйти и позже — следим ещё один цикл; setHidden: остаётся
        // запасным сигналом. Затем тишина: бесконечный опрос на A4 не нужен.
        NSInteger rgen = _turnstileGen;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimReturnPollCap * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self->_pendingReturn || rgen != self->_turnstileGen) return;
            if (MPHLauncherIsFrontmost(self.view)) [self mpReturnCommitEarlyEntry];
        });
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimReturnPollInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self mpReturnPollTickGen:gen t0:t0]; });
}

#pragma mark - WP-сплэш запуска (панель в хост-окне + копия в окне приложения)

// Между тапом и первым кадром приложения — спавн (~0.9 с) и системный zoom с
// белым Default.png. Вместо «чёрной ямы» показываем WP-сплэш: фон = цвет плитки,
// иконка + название по центру. Панель одна и та же: оригинал живёт в хост-окне
// (закрывает паузу спавна), копия клеится в окно приложения (накрывает zoom и
// Default.png с первого кадра) и снимается, когда контент окна готов.

// Запомнить данные сплэша тапнутой плитки (зовётся на тапе, ДО запуска анимаций)
- (void)mpSplashRememberForTile:(UIView *)pressedTile {
    _pendingSplashColor = [pressedTile isKindOfClass:[UIView class]] && pressedTile.backgroundColor
                          ? pressedTile.backgroundColor : [MPMetroStyle tileColor];
    _pendingSplashIcon = ([pressedTile isKindOfClass:[MPTileView class]])
                         ? [(MPTileView *)pressedTile mpIconImage] : nil;
    _pendingSplashName = nil;
    if ([pressedTile isKindOfClass:[MPTileView class]]) {
        NSString *bid = [(MPTileView *)pressedTile bundleID];
        if (bid.length > 0) {
            MPAppEntry *entry = [[MPAppDataSource sharedDataSource] appWithBundleID:bid];
            _pendingSplashName = entry.displayName;
        }
    }
}

// Собрать панель-сплэш по запомненным данным (фрейм передаётся сразу — контент
// раскладывается от известных размеров)
- (UIView *)mpSplashPanelWithFrame:(CGRect)f {
    UIView *panel = [[UIView alloc] initWithFrame:f];
    panel.backgroundColor = _pendingSplashColor ?: [UIColor blackColor];
    panel.userInteractionEnabled = NO;
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    CGFloat h = f.size.height;
    CGFloat side = MPAnimSplashIconSize;
    CGFloat iconY = h / 2.0f - side - MPAnimSplashNameGap / 2.0f;
    if (_pendingSplashIcon != nil) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:_pendingSplashIcon];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.frame = CGRectMake((f.size.width - side) / 2.0f, iconY, side, side);
        iv.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [panel addSubview:iv];
    }
    if (_pendingSplashName.length > 0) {
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectZero];
        lb.text = _pendingSplashName;
        lb.font = [MPMetroStyle lightFont:MPAnimSplashNameSize];
        lb.textColor = [UIColor whiteColor];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.backgroundColor = [UIColor clearColor];
        lb.frame = CGRectMake(0.0f, iconY + side + MPAnimSplashNameGap,
                              f.size.width, MPAnimSplashNameSize + 8.0f);
        lb.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin
                            | UIViewAutoresizingFlexibleBottomMargin;
        [panel addSubview:lb];
    }
    return panel;
}

// Показ панели в хост-окне позы ожидания (feather-стиль, MPAnimOpenStyleSlide=NO:
// без слайда, панель возникает поверх чёрного корня)
- (void)mpLaunchSplashShowForTileAnimated:(BOOL)animated {
    [self mpLaunchSplashHide];
    UIView *v = self.view;
    if (v.superview == nil) return;
    UIView *splash = [self mpSplashPanelWithFrame:v.superview.bounds];
    [v.superview addSubview:splash];
    [v.superview bringSubviewToFront:splash];
    _launchSplash = splash;
    if (animated) {
        splash.alpha = 0.0f;
        [UIView animateWithDuration:MPAnimSplashFadeOut animations:^{ splash.alpha = 1.0f; }];
    }
    MPLog(@"сплэш: панель показана в хост-окне t=%.3f", CACurrentMediaTime());
}

// Убрать панель из хост-окна (и копию из окна приложения). Идемпотентно: из
// playTurnstileIn, appWindowDidHide, show/hide — где бы переход ни закончился,
// сплэш не переживёт позу ожидания. Фейд 0.12 с: при сторож-въезде панель не
// исчезает рваным кадром перед въезжающими плитками.
- (void)mpLaunchSplashHide {
    [self mpWindowSplashRemove];
    UIView *s = _launchSplash;
    if (s == nil) return;
    _launchSplash = nil;
    if (s.superview == nil) return;
    [UIView animateWithDuration:0.12
                     animations:^{ s.alpha = 0.0f; }
                     completion:^(BOOL finished) { [s removeFromSuperview]; }];
}

#pragma mark - Копия сплэша в окне приложения (накрытие zoom и Default.png)

// Приклеить копию сплэша верхним сабвью окна приложения (зовётся из хука
// SBAppWindow, аналог MPLockScreenRaise). Условия: запуск в ходу, окно не наше
// хост-окно, телефон не залочен (в окно локскрина сплэш не клеится).
- (void)mpWindowSplashAttachToWindow:(UIWindow *)w {
    if (!_launchInFlight || _windowSplash != nil) return;
    if (w == nil || w == MPSharedHostWindow()) return;
    if (MPHCLocked()) return;
    MPLog(@"сплэш: клея копию в окно %@ t=%.3f", NSStringFromClass(w.class), CACurrentMediaTime());
    UIView *panel = [self mpSplashPanelWithFrame:w.bounds];
    panel.frame = w.bounds;
    [w addSubview:panel];
    [w bringSubviewToFront:panel];
    _windowSplash = panel;
    _windowSplashGen++;                       // новое поколение снятия

    // Жёсткий предел: даже если контент так и не «устаканился», сплэш обязан уйти
    NSInteger capGen = _windowSplashGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimSplashCap * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (capGen == self->_windowSplashGen) [self mpWindowSplashRemove];
    });
}

// Хук зовёт на каждом didAddSubview/layoutSubviews окна приложения: поднять копию
// наверх (новые сабвью добавляются поверх) и отсрочить снятие, если в окне появился
// полноразмерный контент (каждое добавление откладывает снятие на MPAnimSplashHold).
// Окно нативных приложений живёт в ЧУЖОМ процессе — туда этот хук не достаёт,
// их накрывает сплэш из Tweak.xm (makeKeyAndVisible).
- (void)noteAppWindowLayout:(UIWindow *)w {
    if (_windowSplash == nil || _windowSplash.window != w) return;
    [w bringSubviewToFront:_windowSplash];
    CGSize ws = w.bounds.size;
    for (UIView *s in w.subviews) {
        if (s == _windowSplash) continue;
        if (s.frame.size.width >= ws.width * 0.9f && s.frame.size.height >= ws.height * 0.9f) {
            _windowSplashGen++;               // свежий контент — отсрочить снятие
            break;
        }
    }
    NSInteger gen = _windowSplashGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimSplashHold * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gen == self->_windowSplashGen) [self mpWindowSplashRemove];
    });
}

// Снять копию из окна приложения (идемпотентно): фейд, потом удалить
- (void)mpWindowSplashRemove {
    UIView *p = _windowSplash;
    if (p == nil) return;
    _windowSplash = nil;
    _windowSplashGen++;
    _launchInFlight = NO;                     // первый кадр приложения показан — запуск состоялся
    if (p.superview == nil) return;
    [UIView animateWithDuration:MPAnimSplashFadeOut
                     animations:^{ p.alpha = 0.0f; }
                     completion:^(BOOL finished) { [p removeFromSuperview]; }];
    MPLog(@"сплэш: копия снята с окна приложения t=%.3f", CACurrentMediaTime());
}

#pragma mark - Ленивая загрузка содержимого

// Содержимое не грузится на старте SpringBoard: сначала пауза, затем сборка плиток пачками.
- (void)scheduleContentLoad {
    if (_contentLoaded || _contentScheduled) return;
    _contentScheduled = YES;
    [self performSelector:@selector(loadContent) withObject:nil afterDelay:0.3];
}

- (void)loadContent {
    _contentScheduled = NO;
    if (_contentLoaded) return;

    // датасорс умеет читать иконки только внутри SpringBoard — в чужом
    // UIKit-процессе лаунчер должен молчать
    if (NSClassFromString(@"SBIconView") == nil) return;

    NSArray *apps = [[MPAppDataSource sharedDataSource] allApps];
    if (apps.count == 0) {
        // Модель иконок SpringBoard ещё не готова — повторяем (не затирая раскладку пустым списком).
        if (_loadAttempts++ < 20) {
            MPLog(@"список приложений пуст, повтор %ld", (long)_loadAttempts);
            _contentScheduled = YES;
            [self performSelector:@selector(loadContent) withObject:nil afterDelay:1.0];
        } else {
            MPLog(@"ОШИБКА: список приложений так и не появился");
        }
        return;
    }
    _contentLoaded = YES;
    [self view];                                // гарантируем, что вьюха и страницы созданы
    [self applyStyleToPages];
    // iOS 6 мог сбросить стартовый offset при первом лэйауте — стартуем на плитках
    _pager.contentOffset = CGPointMake(_pager.bounds.size.width, 0.0f);
    _appsForList = apps;
    [_listPage reloadApps:apps];
    [_tilesPage ensureLoadedWithApps:apps];
    [_widgetsPage ensureLoaded];
    MPLog(@"содержимое загружено, приложений: %lu", (unsigned long)apps.count);
}

- (void)applyStyleToPages {
    [_widgetsPage applyStyle];
    [_tilesPage applyStyle];
    [_listPage applyStyle];
}

#pragma mark - Изменение списка / бейджей

- (void)appsChanged:(NSNotification *)n {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self appsChanged:n]; });
        return;
    }
    if (!_contentLoaded) return;
    // noteBadgeDidChange сыплется пачками — склеиваем в одно обновление.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadAppsNow) object:nil];
    [self performSelector:@selector(reloadAppsNow) withObject:nil afterDelay:0.4];
}

- (void)reloadAppsNow {
    if (!_contentLoaded) return;
    NSArray *apps = [[MPAppDataSource sharedDataSource] allApps];
    _appsForList = apps;
    if ([self metroCurrentPage] == 2) {          // 2 = страница списка (0 виджеты, 1 плитки)
        _listNeedsReload = NO;
        [_listPage reloadApps:apps];
    } else {
        // Страница списка скрыта: запоминаем свежий список и пересоберём таблицу,
        // только когда пользователь свайпнет к ней (scrollViewDidScroll:).
        _listNeedsReload = YES;
    }
    [_tilesPage syncWithApps:apps];
}

@end

#pragma mark - C-обёртки для локскрина (свайп-анлок)

// До регистрации лаунчера sharedController = nil — посылки nil безвредны
void MPHomePrepareUnlockEntry(void) {
    [[MPHomeController sharedController] prepareUnlockEntry];
}

void MPHomeStartUnlockEntry(void) {
    [[MPHomeController sharedController] startUnlockEntry];
}

void MPHomeCancelUnlockEntry(void) {
    [[MPHomeController sharedController] cancelUnlockEntry];
}
