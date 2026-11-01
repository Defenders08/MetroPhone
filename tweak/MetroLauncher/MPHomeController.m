#import "MPHomeController.h"
#import "MPTilesPageView.h"
#import "MPTileView.h"                      // mpIconImage/mpLayerDiag (сплэш, дамп слоёв)
#import "MPAppListPageView.h"
#import "MetroWidgets/MPLiveWidgetsPageView.h"
#import "MPMetroStyle.h"
#import "MPAppDataSource.h"
#import "MPAnimationConstants.h"
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
    UIView *_launchSplash;        // загрузочный экран в позе ожидания (иконка приложения)
    NSTimeInterval _unlockCoverT; // когда корень стал чёрной поверхностью при анлоке (диаг разрыва)

    // Замер FPS перехода (данные для решения о стаггере по строкам)
    CADisplayLink *_fpsLink;
    NSTimeInterval _fpsT0, _fpsLast, _fpsSum, _fpsMax;
    NSInteger _fpsCount;
}

+ (MPHomeController *)sharedController { return MPHCLauncher; }
+ (void)setSharedController:(MPHomeController *)c { MPHCLauncher = c; }

// Идёт переход/ожидание возврата: выезд, въезд или приложение на переднем плане.
// Живые плитки сверяются перед флипом (бюджет A4 + чистота перехода).
+ (BOOL)metroTransitionActive {
    MPHomeController *c = MPHCLauncher;
    return c != nil && (c->_pendingReturn || c->_animatingOpen || c->_enterInFlight);
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimLockscreenWaitCap * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self->_deferEnterForLockscreen) return;
        self->_deferEnterForLockscreen = NO;
        if (self->_pendingReturn) return;       // приложение открылось/открыто — въезд не нужен
        MPLog(@"анлок: сигнал скрытия локскрина не пришёл за %.1f с — въезжаем по пределу (стол был закрыт %.0f мс)",
              (double)MPAnimLockscreenWaitCap,
              self->_unlockCoverT > 0 ? (CACurrentMediaTime() - self->_unlockCoverT) * 1000.0 : -1.0);
        [self playTurnstileIn];
    });
}

// Локскрин скрылся (любой путь через MLSHideNow): очередь на въезд исполнена
- (void)mpLockscreenDidHide {
    if (!_deferEnterForLockscreen) return;
    _deferEnterForLockscreen = NO;
    if (_pendingReturn) {
        MPLog(@"анлок: локскрин скрыт, приложение на переднем плане — лаунчер ждёт в позе");
        return;
    }
    MPLog(@"анлок: локскрин скрыт → въезд лаунчера (стол был закрыт %.0f мс)",
          _unlockCoverT > 0 ? (CACurrentMediaTime() - _unlockCoverT) * 1000.0 : -1.0);
    [self playTurnstileIn];
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
    _deferEnterForLockscreen = NO;
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

// ДИАГНОСТИКА (временная, снимается после разбора): состояние корня и всех
// страниц пейджера — класс/hidden/alpha/frame. Цель — понять, что за экран
// мелькает между выездом лаунчера и окном приложения.
- (void)mpDumpPagerViews:(NSString *)tag {
    UIView *v = self.view;
    MPLog(@"диаг[%@] root=%@ hidden=%d alpha=%.2f frame=%@ identity=%d",
          tag, NSStringFromClass(v.class), v.hidden, v.alpha,
          NSStringFromCGRect(v.frame), CATransform3DEqualToTransform(v.layer.transform, CATransform3DIdentity));
    MPLog(@"диаг[%@] root.superview=%@ окно=%@", tag,
          v.superview ? NSStringFromClass(v.superview.class) : @"nil",
          v.window ? NSStringFromClass(v.window.class) : @"nil");
    if (_pager == nil) return;
    MPLog(@"диаг[%@] pager offset=%@ страница=%ld", tag,
          NSStringFromCGPoint(_pager.contentOffset), (long)[self metroCurrentPage]);
    for (UIView *sib in _pager.subviews) {
        MPLog(@"диаг[%@]   %@ hidden=%d alpha=%.2f frame=%@",
              tag, NSStringFromClass(sib.class), sib.hidden, sib.alpha, NSStringFromCGRect(sib.frame));
    }
}

// ДИАГНОСТИКА (временная): дамп всех плиток обеих страниц перед въездом — охота
// на «белые плитки». По строке видно: белый ли ФОН (пустой контент/стиль) или
// белая ИКОНКА fill-режима (битый PNG темы); у живых плиток — состояние и контент.
static void MPHCollectTiles(UIView *root, NSMutableArray *outTiles) {
    if ([root isKindOfClass:[MPTileView class]]) { [outTiles addObject:root]; return; }
    for (UIView *s in root.subviews) MPHCollectTiles(s, outTiles);
}

- (void)mpDumpTileLayers:(NSString *)tag {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [[MPMetroStyle tileColor] getRed:&r green:&g blue:&b alpha:&a];
    MPLog(@"диаг[%@] tileColor=(%.2f,%.2f,%.2f,%.2f)", tag, r, g, b, a);
    NSMutableArray *tiles = [NSMutableArray array];
    MPHCollectTiles(_tilesPage, tiles);
    MPHCollectTiles(_widgetsPage, tiles);
    for (MPTileView *t in tiles) MPLog(@"диаг[%@] плитка %@", tag, [t mpLayerDiag]);
}

#pragma mark - Замер FPS перехода (CADisplayLink; данные для решения о стаггере)

- (void)mpFpsStart {
    if (_fpsLink != nil) return;                 // переход в переходе — мерим одним замером
    _fpsCount = 0; _fpsSum = 0; _fpsMax = 0;
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
    }
    _fpsCount++;
}

- (void)mpFpsStop:(NSString *)tag {
    if (_fpsLink == nil) return;
    [_fpsLink invalidate];
    _fpsLink = nil;
    if (_fpsCount < 2) return;
    MPLog(@"диаг fps[%@]: %ld кадров, средний %.1f мс, худший %.1f мс (33.3 мс = 30 fps)",
          tag, (long)_fpsCount, _fpsSum / (_fpsCount - 1), _fpsMax);
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

// Въезд одного элемента: поза −80°/alpha 0 до своего хода, затем поворот к 0° с проявлением
- (void)mpFeatherApplyIn:(UIView *)el delay:(NSTimeInterval)delay {
    if (el.bounds.size.width < 1.0f) return;
    MPFeatherSetHinge(el, YES);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    el.layer.transform = MPAnimTurnstileTransform(MPAnimTurnstileInAngle);
    el.layer.opacity = 0.0f;
    [CATransaction commit];
    NSTimeInterval bt = CACurrentMediaTime() + delay;

    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform"];
    turn.fromValue = [NSValue valueWithCATransform3D:MPAnimTurnstileTransform(MPAnimTurnstileInAngle)];
    turn.toValue   = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    turn.duration  = MPAnimTurnstileInDur;
    turn.beginTime = bt;
    turn.timingFunction = MPAnimEaseOut();
    turn.fillMode  = kCAFillModeBoth;
    turn.removedOnCompletion = NO;

    CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeIn.fromValue = @0.0f;
    fadeIn.toValue   = @1.0f;
    fadeIn.duration  = MPAnimTurnstileInDur;
    fadeIn.beginTime = bt;
    fadeIn.timingFunction = MPAnimEaseOut();
    fadeIn.fillMode  = kCAFillModeBoth;
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

// Turnstile-выезд: feather по строкам (0°→+50° + фейд в последних 10 мс каждого
// элемента, корень стоит — под ним чёрный фон); без строк (пустая страница) —
// поворот целым слоем, как раньше. По завершении (проверка по _turnstileGen)
// уборка feather и done.
- (void)playTurnstileOutWithCompletion:(void (^)(void))done pressedTile:(UIView *)pressed {
    UIView *v = self.view;
    _turnstileGen++;
    NSInteger gen = _turnstileGen;
    MPLog(@"turnstile: выезд лаунчера (0°→50°)");

    MPLog(@"диаг turnstileOut t=%.3f gen=%ld hidden=%d alpha=%.2f bounds=%@ superview=%@",
          CACurrentMediaTime(), (long)gen, v.hidden, v.alpha,
          NSStringFromCGRect(v.layer.bounds),
          v.superview ? NSStringFromClass(v.superview.class) : @"nil");
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

// Turnstile-въезд: feather по строкам сверху вниз (−80°→0° с проявлением); без
// строк — поворот целым слоем. Стартовые позы ставятся ДО показа — ни одного
// кадра нормального Start до анимации.
- (void)playTurnstileIn {
    UIView *v = self.view;
    [self mpLaunchSplashHide];                  // сплэш запуска не доживает до въезда
    _turnstileGen++;
    NSInteger gen = _turnstileGen;
    _enterInFlight = YES;
    MPLog(@"turnstile: въезд лаунчера (−80°→0°)");

    MPLog(@"диаг turnstileIn t=%.3f gen=%ld hidden=%d alpha=%.2f superview=%@",
          CACurrentMediaTime(), (long)gen, v.hidden, v.alpha,
          v.superview ? NSStringFromClass(v.superview.class) : @"nil");

    NSTimeInterval tIn0 = CACurrentMediaTime();   // для замера запаздывания completion
    [self mpFpsStart];

    NSArray *rows = [self mpFeatherRowsWithPressed:nil];
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray *row in rows) [all addObjectsFromArray:row];
    [self mpDumpTileLayers:@"въезд-слои"];      // ДИАГНОСТИКА белых плиток (временная)

    NSTimeInterval total = MPAnimTurnstileInDur;
    if (rows.count > 0) {
        // корень сразу виден и неподвижен (фон чёрный)
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.layer.transform = CATransform3DIdentity;
        v.alpha = 1.0f;
        v.hidden = NO;
        v.userInteractionEnabled = YES;
        _pager.hidden = NO;                     // выход из позы ожидания — вернуть контент
        _waitingPose = NO;
        [v.superview bringSubviewToFront:v];
        [CATransaction commit];

        total = MPAnimTurnstileInDur + rows.count * MPAnimFeatherStagger;
        _featherViews = all;
        MPLog(@"диаг feather: въезд %ld строк, %ld элементов, всего %.2f с",
              (long)rows.count, (long)all.count, (double)total);
    } else {
        // фолбэк: стартовая поза целого слоя
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        v.layer.transform = MPAnimTurnstileTransform(MPAnimTurnstileInAngle);
        v.alpha = 0.0f;
        v.hidden = NO;
        v.userInteractionEnabled = YES;
        _pager.hidden = NO;
        _waitingPose = NO;
        [v.superview bringSubviewToFront:v];
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
        // фолбэк: анимация целого слоя
        CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform"];
        turn.fromValue = [NSValue valueWithCATransform3D:MPAnimTurnstileTransform(MPAnimTurnstileInAngle)];
        turn.toValue   = [NSValue valueWithCATransform3D:CATransform3DIdentity];
        turn.duration  = MPAnimTurnstileInDur;
        turn.timingFunction = MPAnimEaseOut();
        turn.fillMode  = kCAFillModeForwards;
        turn.removedOnCompletion = NO;
        CABasicAnimation *fadeIn = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeIn.fromValue = @0.0f;
        fadeIn.toValue   = @1.0f;
        fadeIn.duration  = MPAnimTurnstileInDur;
        fadeIn.timingFunction = MPAnimEaseOut();
        fadeIn.fillMode  = kCAFillModeForwards;
        fadeIn.removedOnCompletion = NO;
        [v.layer addAnimation:turn forKey:MPTurnstileKeyTurnIn];
        [v.layer addAnimation:fadeIn forKey:MPTurnstileKeyFadeIn];
    } else {
        // feather: анимации элементов ВНУТРИ транзакции (иначе completion ранний)
        NSInteger r = 0;
        for (NSArray *row in rows) {
            NSTimeInterval delay = r * MPAnimFeatherStagger;
            for (UIView *el in row) [self mpFeatherApplyIn:el delay:delay];
            r++;
        }
    }
    [CATransaction commit];
}

// Выезд лаунчера перед запуском приложения; после выезда — стартовая поза въезда,
// и только затем launch. pressedTile — тапнутая плитка (уходит последней в feather).
// bundleID — для сторожа неудачного запуска (nil → сторожа нет).
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

    [self mpDumpPagerViews:@"тап"];
    MPLog(@"диаг playAppOpen: играем выезд t=%.3f (bundleID=%@)", CACurrentMediaTime(), bundleID);
    [[MPLiveTileScheduler sharedScheduler] setAnimPaused:YES];  // переход — плитки стоят
    _animatingOpen = YES;
    [self playTurnstileOutWithCompletion:^{
        self->_animatingOpen = NO;
        MPLog(@"turnstile: приложение после выезда; лаунчер в позу ожидания");
        // Поза ожидания: корень ВИДЕН чёрным (пейджер спрятан). Раньше корень был
        // alpha 0 — сквозь него просвечивала РОДНАЯ сетка иконок SpringBoard во
        // время системного zoom запуска и в паузе перед въездом (видео 23:36).
        // Из «+50°» не возвращаемся вовсе — по сигналу закрытия остаётся только
        // запустить въезд, и никакой тайминг сигнала не покажет нормальный Start.
        UIView *vv = self.view;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        vv.layer.transform = CATransform3DIdentity;
        vv.alpha = 1.0f;
        vv.hidden = NO;
        _pager.hidden = YES;                   // чёрная поверхность вместо сетки иконок
        vv.userInteractionEnabled = NO;
        [CATransaction commit];
        _waitingPose = YES;

        [self mpLaunchSplashShowForTile:pressedTile];
        [self mpDumpPagerViews:@"launch"];
        launch();

        // Сторож неудачного запуска. Приложение (bundleID есть): не поднялось и не живо
        // за MPAnimLaunchWatchdog — въезжаем сами (крэш/отказ, пустой экран недопустим).
        // Виджет с URL-целью: страховка через MPAnimWidgetInsurance — если SpringBoard
        // всё ещё frontmost, URL ничего не открыл и лаунчер обязан вернуться.
        NSInteger wgen = self->_turnstileGen;
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
                      bundleID, (double)MPAnimLaunchWatchdog);
            } else {
                MPLog(@"страховка виджета: сработала (%.1f с, SpringBoard frontmost) → въезд",
                      (double)MPAnimWidgetInsurance);
            }
            [self appWindowDidHide];
        });
    } pressedTile:pressedTile];

    // Возврат ведут два сигнала: хук SBAppWindow setHidden:YES (если приходит)
    // и Home-фолбэк в menuButtonDown:. Если запуск сорвался — сторож выше вернёт
    // лаунчер сам; следующий Home на голом столе вернёт его тем же въездом.
    _pendingReturn = YES;
    return YES;
}

// Лочок для Home-фолбэка: заблокированный телефон переходы не играет
static BOOL MPHCLocked(void) {
    id away = [objc_getClass("SBAwayController") sharedAwayController];
    return away != nil && [away respondsToSelector:@selector(isLocked)] && [away isLocked];
}

// От хука SBAppWindow setHidden:. На iOS 6 при закрытии приложения setHidden:YES
// может не приходить (окно не нашего класса или гасится иначе) — тогда единственный
// сигнал возврата это Home-фолбэк; эта строка в журнале покажет, приходит ли setHidden
- (void)noteAppWindowHidden:(BOOL)hidden {
    if (!_pendingReturn) return;
    MPLog(@"turnstile: SBAppWindow setHidden:%d", hidden ? 1 : 0);
    if (hidden) [self appWindowDidHide];
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

// Окно приложения скрылось: лаунчер въезжает поворотом из-за левого края
- (void)appWindowDidHide {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self appWindowDidHide]; });
        return;
    }
    [self mpLaunchSplashHide];                  // сплэш запуска больше не нужен
    MPLog(@"диаг appWindowDidHide t=%.3f pending=%d visible=%d",
          CACurrentMediaTime(), _pendingReturn, _visible);
    if (!_pendingReturn) return;
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

#pragma mark - Возврат из приложения: въезд по факту ухода окна

// Домашний фолбэк прежней версии играл въезд через фиксированные 0.45 с — журнал
// и видео показали двойную экспозицию: Start проступал поверх ещё гаснущего окна
// приложения (setHidden: на iOS 6 молчит, реальный момент ухода никто не мерил).
// Теперь опрашиваем frontmost: окно приложения сверху → SpringBoard не frontmost;
// ушло → frontmost вернулся. Раньше ушло — раньше въезд; не уходит — въезд по пределу.
- (void)scheduleReturnFromApp {
    NSInteger gen = _turnstileGen;
    MPLog(@"диаг возврат: следим за окном приложения (шаг %.0f мс, предел %.1f с) t=%.3f",
          MPAnimReturnPollInterval * 1000.0, (double)MPAnimReturnPollCap, CACurrentMediaTime());
    [self mpReturnPollTickGen:gen t0:CACurrentMediaTime()];
}

- (void)mpReturnPollTickGen:(NSInteger)gen t0:(NSTimeInterval)t0 {
    if (gen != _turnstileGen) {                 // show/hide/новый запуск — не наш переход
        MPLog(@"диаг возврат: опрос прерван (gen изменился %ld != %ld)",
              (long)gen, (long)_turnstileGen);
        return;
    }
    if (!_pendingReturn) {                      // setHidden: или другой путь уже свели переход
        MPLog(@"диаг возврат: опрос прерван (возврат уже сыгран)");
        return;
    }
    if (MPHLauncherIsFrontmost(self.view)) {
        MPLog(@"диаг возврат: окно приложения реально ушло через %.0f мс",
              (CACurrentMediaTime() - t0) * 1000.0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimReturnGrace * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self->_pendingReturn && gen == self->_turnstileGen) [self appWindowDidHide];
        });
        return;
    }
    if (CACurrentMediaTime() - t0 >= MPAnimReturnPollCap) {
        MPLog(@"диаг возврат: окно не ушло за %.1f с → въезд по пределу",
              (double)MPAnimReturnPollCap);
        [self appWindowDidHide];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPAnimReturnPollInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self mpReturnPollTickGen:gen t0:t0]; });
}

#pragma mark - Загрузочный экран в позе ожидания («чёрная яма»)

// Между выездом лаунчера и показом окна приложения ~0.9 с системного спавна —
// на глаз это чёрная яма. В позе ожидания показываем иконку приложения по центру
// с лёгким scale/fade (константы MPAnimLaunchSplash*); экран убирается в начале
// въезда и в show/hide — поза ожидания остаётся согласованной (_waitingPose не
// трогаем: сплэш — просто подслой чёрного корня).
- (void)mpLaunchSplashShowForTile:(UIView *)pressedTile {
    if (!MPAnimLaunchSplashEnabled) return;
    [self mpLaunchSplashHide];
    if (![pressedTile isKindOfClass:[MPTileView class]]) return;   // виджет без иконки — чёрная поза
    UIImage *icon = [(MPTileView *)pressedTile mpIconImage];
    if (icon == nil) return;
    UIView *v = self.view;
    UIView *splash = [[UIView alloc] initWithFrame:v.bounds];
    splash.backgroundColor = [UIColor clearColor];  // фон уже чёрный — сам корень
    splash.userInteractionEnabled = NO;
    splash.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIImageView *iv = [[UIImageView alloc] initWithImage:icon];
    CGFloat side = MPAnimLaunchSplashSize;
    iv.frame = CGRectMake((v.bounds.size.width - side) / 2.0f,
                          (v.bounds.size.height - side) / 2.0f, side, side);
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.alpha = 0.0f;
    iv.transform = CGAffineTransformMakeScale(MPAnimLaunchSplashScaleFrom, MPAnimLaunchSplashScaleFrom);
    [splash addSubview:iv];
    [v addSubview:splash];
    _launchSplash = splash;
    [UIView animateWithDuration:MPAnimLaunchSplashFadeIn
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         iv.alpha = 1.0f;
                         iv.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];
    MPLog(@"диаг сплэш: иконка показана в позе ожидания t=%.3f", CACurrentMediaTime());
}

// Идемпотентно: из playTurnstileIn, appWindowDidHide, show/hide — где бы переход
// ни закончился, сплэш не переживёт позу ожидания
- (void)mpLaunchSplashHide {
    UIView *s = _launchSplash;
    if (s == nil) return;
    _launchSplash = nil;
    [s removeFromSuperview];
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
