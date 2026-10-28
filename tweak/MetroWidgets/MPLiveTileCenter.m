#import "MPLiveTileCenter.h"
#import "MPLiveTileView.h"
#import "MPLiveTileScheduler.h"
#import "MPLiveTileRegistry.h"
#import "MPTileClock.h"
#import "MPTileBattery.h"
#import "MPTileNowPlaying.h"
#import "MPTileTestCounter.h"
#import "MPTileTestStates.h"
#import "MetroLauncher/MPLayoutModel.h"
#import "MetroLauncher/MPAppDataSource.h"
#import "MetroLauncher/MPMetroStyle.h"
#import "MetroPhoneCommon.h"
#import <objc/runtime.h>

NSString * const MPLiveWidgetsChangedNotification = @"MPLiveWidgetsChangedNotification";

// Ключ настройки одного виджета: liveTile.<tileID>.<suffix>
static NSString *MPTileKey(NSString *tileID, NSString *suffix) {
    return [NSString stringWithFormat:@"%@%@.%@", MPKeyLiveTilePrefix, tileID, suffix];
}

// Чтение CFPreferences без кэша: живые плитки читают настройки редко
// (старт, смена конфига), и им нужна мгновенная свежесть после тумблера.
static id MPPrefValue(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)key, CFSTR(MP_PREFS_DOMAIN)));
}

static BOOL MPPrefBool(NSString *key, BOOL def) {
    id v = MPPrefValue(key);
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v boolValue];
    return def;
}

// Видна ли вьюха пользователю: вся цепочка надстроек не спрятана и не прозрачна,
// у цепочки есть окно, и вьюха попадает в кадр окна (отсекает невидимую страницу
// пейджера и плитки вне видимой части скролла).
static BOOL MPLiveViewIsVisible(UIView *v) {
    for (UIView *u = v; u != nil; u = u.superview) {
        if (u.hidden || u.alpha < 0.01f) return NO;
        if (u.window == nil) return NO;   // цепочка не доходит ни до одного окна
    }
    CGRect r = [v convertRect:v.bounds toView:v.window];
    return CGRectIntersectsRect(r, v.window.bounds);
}

// displayStatus-уведомление состояние не передаёт — читаем системный plist
static BOOL MPLiveDisplayIsOn(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.apple.iokit.hid.displayStatus.plist"];
    id v = [d isKindOfClass:[NSDictionary class]] ? [d objectForKey:@"DisplayStatus"] : nil;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v boolValue];
    return YES;   // файл не читается — считаем экран включённым
}

static void MPLiveDisplayChangedCB(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    BOOL on = MPLiveDisplayIsOn();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[MPLiveTileScheduler sharedScheduler] setDisplayOn:on];
    });
}

static void MPLivePrefsChangedCB(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[MPLiveTileCenter sharedCenter] reloadConfig];
    });
}

@implementation MPLiveTileCenter {
    NSHashTable *_views;      // MPLiveTileView, слабые ссылки; чистится сама при dealloc
    BOOL _started;
    BOOL _dead;               // ошибка инициализации — молча не работаем, без повторов
}

+ (MPLiveTileCenter *)sharedCenter {
    static MPLiveTileCenter *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (BOOL)isRunning { return _started && !_dead; }

#pragma mark - Старт

// Встроенные плитки: один класс + одна строка регистрации. Новая плитка
// добавляется только здесь.
- (void)registerBuiltIns {
    [MPLiveTileRegistry registerClass:[MPTileClock class]];
    [MPLiveTileRegistry registerClass:[MPTileBattery class]];
    // Now Playing держится на частном классе iOS 6 — регистрируем, только если он есть
    if ([MPTileNowPlaying isAvailable]) {
        [MPLiveTileRegistry registerClass:[MPTileNowPlaying class]];
    }
    // ТЕСТОВЫЕ плитки: включены по умолчанию ради проверки фреймворка на устройстве.
    // Перед релизом убрать здесь и строки из LiveTiles.plist + футера размеров.
    [MPLiveTileRegistry registerClass:[MPTileTestCounter class]];
    [MPLiveTileRegistry registerClass:[MPTileTestStates class]];
}

// Приведение системы к текущему состоянию главного тумблера: используется
// и на старте, и при смене настроек — иначе виджеты, выключенные при старте
// SpringBoard, не ожили бы без респринга.
- (void)applyRunningState {
    if (![self isMasterOn]) {
        [[MPLiveTileScheduler sharedScheduler] setDisplayOn:NO];   // тик больше не нужен
        [[MPLiveTileScheduler sharedScheduler] unregisterAll];
        return;
    }
    if (_views == nil) _views = [NSHashTable weakObjectsHashTable];
    [[MPLiveTileScheduler sharedScheduler] setDisplayOn:MPLiveDisplayIsOn()];
    [[MPLiveTileScheduler sharedScheduler] start];   // повторный вызов — no-op
    [self scheduleAllTiles];
}

- (void)start {
    if (_started) return;
    _started = YES;
    @try {
        if (objc_getClass("SBIconView") == nil) return;   // только SpringBoard
        // плитки регистрируются всегда — состав реестра не зависит от тумблера
        [self registerBuiltIns];
        // сторонние виджеты из MP_WIDGETS_DIR (пока только скан с записью в журнал)
        [MPLiveTileRegistry scanExternalWidgetsDirectory:@MP_WIDGETS_DIR];
        if ([[MPLiveTileRegistry allProviders] count] == 0) {
            MPLog(@"живые плитки: ни одной плитки не зарегистрировано");
            return;
        }

        [self applyRunningState];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            &MPLivePrefsChangedCB, CFSTR(MP_LIVETILES_CHANGED_NOTIFICATION), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            &MPLiveDisplayChangedCB, CFSTR("com.apple.iokit.hid.displayStatus"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        MPLog(@"живые плитки: старт, виджетов %lu",
              (unsigned long)[[self enabledWidgetIDs] count]);
    } @catch (NSException *e) {
        _dead = YES;   // молча отключаемся: ни повторов, ни влияния на SpringBoard
        MPLog(@"!! живые плитки отключены: %@ (%@)", e.name, e.reason);
    }
}

#pragma mark - Конфигурация

- (BOOL)isMasterOn {
    return MPPrefBool(MPKeyLiveTiles, YES);
}

- (BOOL)isTileEnabled:(NSString *)tileID {
    return MPPrefBool(MPTileKey(tileID, @"enabled"), YES);
}

- (MPLiveTileSize)sizeForTileID:(NSString *)tileID {
    NSInteger stored = -1;
    id v = MPPrefValue(MPTileKey(tileID, @"size"));
    if ([v isKindOfClass:[NSNumber class]]) stored = [(NSNumber *)v integerValue];

    if ([MPLiveTileRegistry tileID:tileID supportsSize:(MPLiveTileSize)stored]) {
        return (MPLiveTileSize)stored;
    }
    id<MPLiveTileProvider> p = [MPLiveTileRegistry providerForID:tileID];
    if (p != nil && [[p class] respondsToSelector:@selector(defaultSize)]) {
        MPLiveTileSize def = (MPLiveTileSize)[(id)[p class] defaultSize];
        if ([MPLiveTileRegistry tileID:tileID supportsSize:def]) return def;
    }
    return MPLiveTileSizeCell;
}

- (NSArray *)enabledWidgetIDs {
    if (![self isMasterOn]) return @[];
    NSMutableArray *ids = [NSMutableArray array];
    for (id<MPLiveTileProvider> p in [MPLiveTileRegistry allProviders]) {
        if ([self isTileEnabled:[p tileID]]) [ids addObject:[p tileID]];
    }
    return [ids copy];
}

- (NSArray *)homeWidgets {
    NSMutableArray *out = [NSMutableArray array];
    MPLayoutModel *model = [MPLayoutModel sharedModel];
    for (NSString *tileID in [self enabledWidgetIDs]) {
        if ([model isBundleIDExcluded:tileID]) continue;   // откреплён со стартового
        [out addObject:@{ @"id": tileID,
                          @"size": [NSNumber numberWithInteger:(NSInteger)[self sizeForTileID:tileID]] }];
    }
    return [out copy];
}

#pragma mark - Планирование

- (void)scheduleAllTiles {
    MPLiveTileScheduler *sched = [MPLiveTileScheduler sharedScheduler];
    [sched unregisterAll];
    for (id<MPLiveTileProvider> p in [MPLiveTileRegistry allProviders]) {
        NSString *tileID = [p tileID];
        if (![self isTileEnabled:tileID]) continue;
        MPLiveTileSize size = [self sizeForTileID:tileID];
        NSTimeInterval interval = [p refreshIntervalForSize:size];
        __weak MPLiveTileCenter *weakSelf = self;
        [sched registerTile:tileID
                   provider:p
                       size:size
                   interval:interval
               visibleBlock:^BOOL {
                   MPLiveTileCenter *c = weakSelf;
                   return (c != nil && ![c isDead]) && [c hasVisibleViewForTileID:tileID];
               }
                 applyBlock:^(MPLiveTileContent *content) {
                     MPLiveTileCenter *c = weakSelf;
                     if (c != nil) [c applyContent:content tileID:tileID];
                 }];
    }
}

#pragma mark - Вьюхи

- (void)registerView:(MPLiveTileView *)view {
    if (_views == nil || view == nil) return;
    [_views addObject:view];
}

- (BOOL)isDead { return _dead; }

- (BOOL)hasVisibleViewForTileID:(NSString *)tileID {
    if (_views == nil) return NO;
    for (MPLiveTileView *v in [_views allObjects]) {
        if (![v isKindOfClass:[MPLiveTileView class]]) continue;
        if (![v.tileID isEqualToString:tileID]) continue;
        if (MPLiveViewIsVisible(v)) return YES;
    }
    return NO;
}

- (void)applyContent:(MPLiveTileContent *)content tileID:(NSString *)tileID {
    if (_views == nil) return;
    id<MPLiveTileProvider> provider = [MPLiveTileRegistry providerForID:tileID];
    for (MPLiveTileView *v in [_views allObjects]) {
        if (![v isKindOfClass:[MPLiveTileView class]]) continue;
        if (![v.tileID isEqualToString:tileID]) continue;
        if (content == nil) [v markStale];
        else [v applyContent:content provider:provider];
    }
}

#pragma mark - Действия

- (void)launchTileView:(MPLiveTileView *)view {
    if (!_started || _dead) return;
    @try {
        // провайдер может обработать тап сам (Now Playing запускает текущий плеер)
        id<MPLiveTileProvider> p = [MPLiveTileRegistry providerForID:view.tileID];
        if (p != nil && [p respondsToSelector:@selector(handleTap)] && [p handleTap]) return;

        NSString *target = view.launchTarget;
        if (target.length == 0) return;
        if ([target hasPrefix:@"prefs:"]) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:target]];
        } else {
            [[MPAppDataSource sharedDataSource] launchAppWithBundleID:target];
        }
    } @catch (NSException *e) {
        MPLog(@"!! запуск из виджета: %@ (%@)", e.name, e.reason);
    }
}

- (void)setSize:(MPLiveTileSize)size forTileID:(NSString *)tileID {
    @try {
        CFPreferencesSetAppValue((CFStringRef)MPTileKey(tileID, @"size"),
                                 (__bridge CFPropertyListRef)[NSNumber numberWithInteger:(NSInteger)size],
                                 CFSTR(MP_PREFS_DOMAIN));
        CFPreferencesAppSynchronize(CFSTR(MP_PREFS_DOMAIN));
        [self scheduleAllTiles];   // интервал обновления зависит от размера
        [[NSNotificationCenter defaultCenter] postNotificationName:MPLiveWidgetsChangedNotification
                                                            object:nil];
    } @catch (NSException *e) {
        MPLog(@"!! размер виджета %@: %@ (%@)", tileID, e.name, e.reason);
    }
}

- (void)setPinnedToHome:(BOOL)pinned forTileID:(NSString *)tileID {
    @try {
        MPLayoutModel *model = [MPLayoutModel sharedModel];
        if (pinned) {
            [model pinBundleID:tileID];
            // pinBundleID дописывает в конец, а виджеты живут в начале раскладки —
            // передвигаем свежезакреплённый элемент в голову
            NSInteger idx = (NSInteger)[[model items] indexOfObjectPassingTest:
                ^BOOL(MPTileItem *it, NSUInteger i, BOOL *stop) {
                    *stop = NO;
                    return it.isWidget && [it.bundleID isEqualToString:tileID];
                }];
            if (idx > 0) [model moveItemFromIndex:idx toIndex:0];
        } else {
            [model excludeBundleID:tileID];
        }
        [model save];
        [[NSNotificationCenter defaultCenter] postNotificationName:MPLiveWidgetsChangedNotification
                                                            object:nil];
    } @catch (NSException *e) {
        MPLog(@"!! закрепление %@: %@ (%@)", tileID, e.name, e.reason);
    }
}

- (void)reloadConfig {
    if (!_started || _dead) return;
    @try {
        [self applyRunningState];
        // страницы сами пересоберут виджеты (в т.ч. уберут при выключении)
        [[NSNotificationCenter defaultCenter] postNotificationName:MPLiveWidgetsChangedNotification
                                                            object:nil];
        MPLog(@"живые плитки: конфиг перечитан (вкл=%d)", (int)[self isMasterOn]);
    } @catch (NSException *e) {
        MPLog(@"!! перечитывание конфига: %@ (%@)", e.name, e.reason);
    }
}

@end
