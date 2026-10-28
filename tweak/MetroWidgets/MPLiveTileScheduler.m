#import "MPLiveTileScheduler.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

static const NSTimeInterval MPLiveTickInterval    = 1.0;
static const NSTimeInterval MPLiveWatchdogTimeout = 15.0;   // сторож ответа провайдера
static const NSTimeInterval MPLiveMaxBackoff      = 600.0;  // предел бэкоффа (10 мин)
static const NSInteger      MPLiveBackoffShiftCap = 4;      // интервал × 2^4 максимум

// Состояние одного зарегистрированного виджета. Живёт в словаре планировщика,
// трогается только с главного потока.
@interface MPLiveTileRun : NSObject
@property (nonatomic, copy)   NSString *tileID;
@property (nonatomic, strong) id<MPLiveTileProvider> provider;
@property (nonatomic, assign) MPLiveTileSize size;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, copy)   BOOL (^visibleBlock)(void);
@property (nonatomic, copy)   void (^applyBlock)(MPLiveTileContent *);
@property (nonatomic, assign) CFAbsoluteTime nextDue;
@property (nonatomic, assign) CFAbsoluteTime lastSuccess;   // 0 — успешных обновлений ещё не было
@property (nonatomic, assign) NSInteger failureStreak;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, assign) NSInteger generation;          // отсекает поздние ответы провайдера
@end

@implementation MPLiveTileRun
@end

@implementation MPLiveTileScheduler {
    dispatch_source_t   _tick;          // 1 с, главный поток; ссылку держим — иначе источник умрёт
    BOOL                _tickSuspended;
    BOOL                _displayOn;
    NSMutableDictionary *_runs;         // tileID → MPLiveTileRun
    dispatch_queue_t    _fetchQueue;    // серийная фоновая: тяжёлое — вне главного потока
}

+ (MPLiveTileScheduler *)sharedScheduler {
    static MPLiveTileScheduler *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[self alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _runs = [[NSMutableDictionary alloc] init];
        _displayOn = YES;
    }
    return self;
}

- (void)start {
    if (_tick != nil) return;
    _tickSuspended = NO;
    dispatch_source_t tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                    dispatch_get_main_queue());
    // первый тик через 2 с, дальше раз в секунду с полным leeway: точность не нужна,
    // а редкие пробуждения процессора на iPhone 4 заметны
    dispatch_source_set_timer(tick,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
        (int64_t)(MPLiveTickInterval * NSEC_PER_SEC),
        (int64_t)(MPLiveTickInterval * NSEC_PER_SEC));
    dispatch_source_set_event_handler(tick, ^{ [self tick]; });
    _tick = tick;
    dispatch_resume(tick);

    _fetchQueue = dispatch_queue_create("ru.ash.metrophone.livetiles", DISPATCH_QUEUE_SERIAL);
    MPLog(@"живые плитки: планировщик запущен");
}

#pragma mark - Регистрация

- (void)registerTile:(NSString *)tileID
            provider:(id<MPLiveTileProvider>)provider
                size:(MPLiveTileSize)size
            interval:(NSTimeInterval)interval
       visibleBlock:(BOOL (^)(void))visibleBlock
          applyBlock:(void (^)(MPLiveTileContent *))applyBlock {
    MPLiveTileRun *run = [[MPLiveTileRun alloc] init];
    run.tileID = tileID;
    run.provider = provider;
    run.size = size;
    run.interval = MAX(interval, 1.0);
    run.visibleBlock = visibleBlock;
    run.applyBlock = applyBlock;
    run.nextDue = CFAbsoluteTimeGetCurrent() + 1.0;   // первое обновление — почти сразу
    [_runs setObject:run forKey:tileID];
}

- (void)unregisterTile:(NSString *)tileID {
    MPLiveTileRun *run = [_runs objectForKey:tileID];
    if (run == nil) return;
    run.generation++;   // поздний ответ провайдера не применится к вьюхам
    [_runs removeObjectForKey:tileID];
}

- (void)unregisterAll {
    for (NSString *tileID in [_runs allKeys]) [self unregisterTile:tileID];
}

- (void)setDisplayOn:(BOOL)on {
    if (_displayOn == on) return;
    _displayOn = on;
    if (_tick == nil) return;
    // пауза без пробуждений: пока экран погашен, тик не срабатывает вовсе
    if (!on && !_tickSuspended) { dispatch_suspend(_tick); _tickSuspended = YES; }
    if (on && _tickSuspended)  { dispatch_resume(_tick);  _tickSuspended = NO; }
}

#pragma mark - Тик (главный поток)

- (void)tick {
    if (!_displayOn || _runs.count == 0) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (MPLiveTileRun *run in [_runs allValues]) {
        if (run.inFlight || now < run.nextDue) continue;
        // невидимый виджет не обновляется: nextDue остаётся в прошлом, и при
        // возврате видимости обновление происходит немедленно
        if (run.visibleBlock == nil || !run.visibleBlock()) continue;
        // данные просрочены (планировщик был на паузе) — приглушить показанное
        if (run.lastSuccess > 0 && now - run.lastSuccess > 2.0 * run.interval && run.applyBlock != nil) {
            run.applyBlock(nil);
        }
        [self launchFetchForRun:run];
    }
}

#pragma mark - Получение данных (фоновая очередь)

- (void)launchFetchForRun:(MPLiveTileRun *)run {
    run.inFlight = YES;
    NSInteger generation = ++run.generation;
    MPLiveTileRun *captured = run;
    dispatch_queue_t fetchQueue = _fetchQueue;

    dispatch_async(fetchQueue, ^{
        @autoreleasepool {
            @try {
                [captured.provider loadContentForSize:captured.size
                                           completion:^(MPLiveTileContent *content) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self finishRun:captured generation:generation content:content invalidate:NO];
                    });
                }];
            } @catch (NSException *e) {
                MPLog(@"!! живая плитка %@: %@", captured.tileID, e.reason ?: e.name);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishRun:captured generation:generation
                            content:[MPLiveTileScheduler errorContent] invalidate:YES];
                });
            }
            // сторож: молчание дольше MPLiveWatchdogTimeout — ошибка; поздний
            // ответ (если всё же придёт) будет отброшен по поколению.
            // Зависший блок на серийной очереди задержит остальные плитки —
            // сторож хотя бы покажет ошибку и включит бэкофф.
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MPLiveWatchdogTimeout * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [self watchdogRun:captured generation:generation];
                });
        }
    });
}

- (void)watchdogRun:(MPLiveTileRun *)run generation:(NSInteger)generation {
    if (!run.inFlight || run.generation != generation) return;
    run.generation++;
    MPLog(@"живая плитка %@: нет ответа за %.0f с", run.tileID, MPLiveWatchdogTimeout);
    [self finishRun:run generation:generation
            content:[MPLiveTileScheduler errorContent] invalidate:NO];
}

- (void)finishRun:(MPLiveTileRun *)run generation:(NSInteger)generation
          content:(MPLiveTileContent *)content invalidate:(BOOL)invalidate {
    if (run.generation != generation || !run.inFlight) return;   // поздний/чужой ответ
    if (invalidate) run.generation++;
    run.inFlight = NO;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL ok = (content != nil) && (content.state == MPLiveTileStateReady ||
                                   content.state == MPLiveTileStateEmpty);
    if (ok) {
        run.lastSuccess = now;
        run.failureStreak = 0;
        run.nextDue = now + run.interval;
    } else {
        run.failureStreak++;
        NSTimeInterval backoff = MIN(run.interval * (1 << MIN(run.failureStreak, MPLiveBackoffShiftCap)),
                                     MPLiveMaxBackoff);
        run.nextDue = now + backoff;
        MPLog(@"живая плитка %@: сбой %ld, повтор через %.0f с",
              run.tileID, (long)run.failureStreak, backoff);
    }
    if (run.applyBlock != nil) run.applyBlock(content);
}

+ (MPLiveTileContent *)errorContent {
    MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
    c.state = MPLiveTileStateError;
    return c;
}

@end
