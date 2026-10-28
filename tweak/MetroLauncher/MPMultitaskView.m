#import "MPMultitaskView.h"
#import "MPMetroStyle.h"
#import "MPAppDataSource.h"
#import "MPTileView.h"   // MPIconLoader — общий серийный загрузчик иконок

// Метрики под iPhone 4 (320×480), по скрину WP8.1:
// карточка 2:3 (как снимок экрана 320×480), соседние карточки выглядывают
// из-за краёв экрана в покое и полностью въезжают при листании.
static const CGFloat MPPageW      = 260.0;  // шаг страниц (карточка + зазор)
static const CGFloat MPCardW      = 248.0;  // ширина карточки
static const CGFloat MPCardH      = 372.0;  // высота карточки (2:3)
static const CGFloat MPPagerTop   = 34.0;   // отступ сверху
static const CGFloat MPPagerH     = 420.0;  // карточка + строка «иконка + имя»
static const CGFloat MPPagerInset = 30.0;   // (320 − 260) / 2 — центрирование страницы

static UIImage *MPSnapshotForBundleID(NSString *bid); // реализация ниже по файлу

// Снимки экранов читаются с диска строго по одному и не на главном потоке:
// пачка из десяти карточек раньше означала десятки обращений к файловой системе
// и декодирований вьюх прямо во время открытия свитчера.
static dispatch_queue_t MPSnapshotQueue(void) {
    static dispatch_queue_t q = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("ru.ash.metrophone.snapshots", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

// Декодированные и уменьшенные до карточки снимки: повторное открытие свитчера
// не перечитывает диск и не декодирует PNG заново. NSCache сам эвиктирует
// под давлением памяти.
static NSCache *MPSnapshotMemCache(void) {
    static NSCache *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 10;           // по карточке на запущенное приложение
    });
    return cache;
}

// Чтение PNG — это ленивый UIImage: реальное декодирование 640×960 случилось бы
// на главном потоке в момент появления карточки (десятки мс на A4). Здесь же
// сразу уменьшаем до размера карточки ×2 (ретина): минус ~40 % памяти и ни одного
// масштабирования в рантайме. Соотношение сторон сохраняем — кроп карточки
// (AspectFill) остаётся тем же пиксель-в-пиксель.
static UIImage *MPDecodeAndFit(UIImage *img) {
    if (img == nil) return nil;
    CGFloat srcW = img.size.width * img.scale, srcH = img.size.height * img.scale;
    CGFloat dstW = MPCardW * 2.0, dstH = MPCardH * 2.0;
    CGFloat k = MIN(dstW / srcW, dstH / srcH);
    if (k <= 0.0 || k >= 1.0) return img;    // уменьшать нечего — отдаём как есть
    CGSize dst = CGSizeMake(floorf(srcW * k), floorf(srcH * k));
    UIGraphicsBeginImageContextWithOptions(dst, NO, 1.0);
    [img drawInRect:CGRectMake(0.0, 0.0, dst.width, dst.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: img;
}

#pragma mark - Карточка приложения

// Карточка: касание — запуск. Свайпы (вниз — закрытие, в стороны — листание)
// обрабатывает один pan-жест на всей вьюхе свитчера, поэтому карточка
// не ставит своих распознавателей и не мешает листанию «по себе».
@interface MPCard : UIView
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, weak) UIView *page;                 // страница-контейнер в скролле
@property (nonatomic, weak) UIImageView *snapView;        // текущий снимок (замена вместо наслоения)
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, assign, getter=isClosing) BOOL closing;
@end

@implementation MPCard

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor whiteColor];
        self.clipsToBounds = YES;

        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    if (!self.isClosing && self.onTap != nil) self.onTap();
}

// уплыть вниз и раствориться (вызывает свитчер при закрытии приложения)
- (void)flyOffDown {
    [UIView animateWithDuration:0.3 delay:0
        options:UIViewAnimationOptionCurveEaseIn
        animations:^{
            self.transform = CGAffineTransformMakeTranslation(0, 560.0);
            self.alpha = 0.0;
        }
        completion:nil];
}

@end

#pragma mark - Свитчер

// Режим текущего жеста: не определён / листание / закрытие карточки / игнор
typedef NS_ENUM(NSInteger, MPPanMode) {
    MPPanModeNone = 0,
    MPPanModePage,
    MPPanModeClose,
    MPPanModeIgnore,
};

// Методы, вызываемые до своего определения (clang требует видимых объявлений)
@interface MPMultitaskView ()
- (void)refreshExistingSnapshots;
- (void)loadSnapshotIntoCard:(MPCard *)card bundleID:(NSString *)bid;
@end

@implementation MPMultitaskView {
    UIScrollView    *_pager;
    NSMutableArray  *_pages;        // UIView — страницы-контейнеры
    NSMutableArray  *_cards;        // MPCard — параллельно _pages
    UILabel         *_emptyLabel;
    NSInteger       _centeredIndex; // номер страницы по центру
    BOOL            _open;

    MPPanMode       _panMode;       // распознавание жеста одним pan на всю вьюху
    CGFloat         _panStartOffset;
    MPCard          *_panCard;      // карточка, которую тащим вниз
    NSArray         *_lastAppIDs;   // список прошлого открытия: не меняемый — пересборка не нужна
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [MPMetroStyle accentColor];
        self.hidden = YES;

        CGFloat w = frame.size.width;
        // скролл на ВСЮ ширину экрана: соседние карточки выглядывают по краям
        // и не обрезаются при листании. Собственный скроллинг отключён —
        // offset'ом управляет наш pan-жест (paging-магия iOS 6 с узким скроллом
        // обрезала соседей по границам скролла).
        _pager = [[UIScrollView alloc] initWithFrame:CGRectMake(0, MPPagerTop, w, MPPagerH)];
        _pager.pagingEnabled = NO;
        _pager.scrollEnabled = NO;
        _pager.showsHorizontalScrollIndicator = NO;
        _pager.showsVerticalScrollIndicator = NO;
        _pager.clipsToBounds = NO;
        _pager.backgroundColor = nil;
        [self addSubview:_pager];

        // единый жест: горизонталь — листание, вертикаль вниз — закрытие
        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleRootPan:)];
        [self addGestureRecognizer:pan];

        _pages = [[NSMutableArray alloc] init];
        _cards = [[NSMutableArray alloc] init];
    }
    return self;
}

- (BOOL)isOpen { return _open; }

#pragma mark Геометрия страниц

// страница index по центру экрана ↔ contentOffset
- (CGFloat)offsetForIndex:(NSInteger)index {
    return index * MPPageW - MPPagerInset;
}

- (NSInteger)indexForOffset:(CGFloat)offset {
    if (_pages.count == 0) return 0;
    NSInteger idx = (NSInteger)lround((offset + MPPagerInset) / MPPageW);
    NSInteger maxIdx = (NSInteger)_pages.count - 1;
    if (idx < 0) idx = 0;
    if (idx > maxIdx) idx = maxIdx;
    return idx;
}

- (MPCard *)cardForPageIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_cards.count) return nil;
    return _cards[index];
}

#pragma mark Показ / закрытие

- (void)openAnimated:(BOOL)animated withAppIDs:(NSArray *)appIDs {
    @try {
        [MPMetroStyle reloadPreferences];
        self.backgroundColor = [MPMetroStyle accentColor];
        MPLog(@"свитчер: открытие, приложений %lu", (unsigned long)appIDs.count);
        [self rebuildWithAppIDs:appIDs];

        _open = YES;
        self.hidden = NO;
        [self.superview bringSubviewToFront:self];

        if (animated) {
            self.alpha = 0.0;
            [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1.0; }];
            // карточки въезжают снизу «ступеньками», как в WP8.1
            for (NSUInteger i = 0; i < _pages.count; i++) {
                UIView *page = _pages[i];
                page.transform = CGAffineTransformMakeTranslation(0, 30.0);
                page.alpha = 0.0;
                [UIView animateWithDuration:0.32 delay:0.04 * i
                    options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                    animations:^{
                        page.transform = CGAffineTransformIdentity;
                        page.alpha = 1.0;
                    }
                    completion:nil];
            }
        } else {
            self.alpha = 1.0;
        }
        MPLog(@"свитчер: открыт");
    } @catch (NSException *e) {
        // свитчер не должен уметь ронять SpringBoard
        MPLog(@"!! открытие свитчера: %@ (%@)", e.name, e.reason);
        _open = NO;
        self.hidden = YES;
    }
}

- (void)closeAnimated:(BOOL)animated {
    _open = NO;
    if (!animated) {
        self.hidden = YES;
        self.alpha = 1.0;
        return;
    }
    __weak MPMultitaskView *weakSelf = self;
    [UIView animateWithDuration:0.2
        animations:^{ self.alpha = 0.0; }
        completion:^(BOOL finished) {
            MPMultitaskView *strongSelf = weakSelf;
            if (strongSelf == nil || strongSelf->_open) return;
            strongSelf.hidden = YES;
            strongSelf.alpha = 1.0;
        }];
}

#pragma mark Сборка страниц

- (void)rebuildWithAppIDs:(NSArray *)appIDs {
    // Список не менялся с прошлого открытия — страницы уже собраны. Пересборка
    // (десятки вьюх и замеров текста до первого кадра на A4) не нужна: достаточно
    // обновить снимки, дисковый кэш с проверкой mtime делает это дешёвым.
    if (_pages.count > 0 && [appIDs isEqualToArray:_lastAppIDs]) {
        _centeredIndex = 0;
        [_pager setContentOffset:CGPointMake([self offsetForIndex:0], 0) animated:NO];
        [self refreshExistingSnapshots];
        return;
    }
    _lastAppIDs = [appIDs copy];
    for (UIView *v in _pager.subviews) [v removeFromSuperview];
    [_pages removeAllObjects];
    [_cards removeAllObjects];
    [_emptyLabel removeFromSuperview];
    _emptyLabel = nil;
    _centeredIndex = 0;
    [_pager setContentOffset:CGPointMake([self offsetForIndex:0], 0) animated:NO];

    for (NSUInteger i = 0; i < appIDs.count; i++) {
        @try {
            MPCard *card = nil;
            UIView *page = [self buildPageForBundleID:appIDs[i] index:i card:&card];
            if (page != nil && card != nil) {
                page.frame = CGRectMake(i * MPPageW, 0, MPPageW, MPPagerH);
                [_pager addSubview:page];
                [_pages addObject:page];
                [_cards addObject:card];
            }
        } @catch (NSException *e) {
            // страница не собралась — пропускаем, свитчер обязан пережить это
            MPLog(@"!! страница %lu (%@): %@ (%@)", (unsigned long)i, appIDs[i], e.name, e.reason);
        }
    }

    _pager.contentSize = CGSizeMake(MAX(_pages.count, 1) * MPPageW, MPPagerH);
    MPLog(@"свитчер: страниц собрано %lu", (unsigned long)_pages.count);

    if (_pages.count == 0 && appIDs.count > 0) {
        // все страницы не собрались — показываем пустое состояние вместо тишины
        appIDs = @[];
    }

    if (appIDs.count == 0) {
        // Metro-пустота: только надпись тонким шрифтом
        _emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 60.0)];
        _emptyLabel.center = CGPointMake(self.bounds.size.width / 2.0,
                                         self.bounds.size.height / 2.0 - 40.0);
        _emptyLabel.text = @"НЕТ ЗАПУЩЕННЫХ ПРИЛОЖЕНИЙ";
        _emptyLabel.font = [MPMetroStyle thinFont:21.0];
        _emptyLabel.textColor = [UIColor whiteColor];
        _emptyLabel.backgroundColor = nil;
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_emptyLabel];
    }
}

- (UIView *)buildPageForBundleID:(NSString *)bid index:(NSUInteger)idx card:(MPCard **)outCard {
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(idx * MPPageW, 0, MPPageW, MPPagerH)];
    page.backgroundColor = nil;

    MPCard *card = [[MPCard alloc] initWithFrame:
                    CGRectMake((MPPageW - MPCardW) / 2.0, 0, MPCardW, MPCardH)];
    card.bundleID = bid;
    card.page = page;
    __weak MPMultitaskView *weakSelf = self;
    __weak MPCard *weakCard = card;
    card.onTap = ^{ [weakSelf activateBundleID:bid card:weakCard]; };
    [page addSubview:card];
    if (outCard != nil) *outCard = card;

    // Содержимое карточки: заглушка с иконкой видна сразу, снимок экрана приходит
    // фоном и ложится сверху. Порядок в WP8.1 тот же — карточка не бывает пустой.
    UIImageView *placeholder = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 72.0, 72.0)];
    placeholder.center = CGPointMake(MPCardW / 2.0, MPCardH / 2.0);
    placeholder.contentMode = UIViewContentModeScaleAspectFill;
    placeholder.clipsToBounds = YES;
    [card addSubview:placeholder];

    NSString *snapBID = [bid copy];
    [self loadSnapshotIntoCard:card bundleID:snapBID];

    // под карточкой: иконка + имя, по центру (как на скрине WP8.1)
    MPAppEntry *entry = [[MPAppDataSource sharedDataSource] appWithBundleID:bid];
    NSString *name = (entry.displayName.length > 0) ? entry.displayName : bid;
    UIFont *font = [MPMetroStyle lightFont:17.0];
    // ВАЖНО: boundingRectWithSize:options:attributes:context: — только iOS 7+,
    // на iOS 6 он даёт unrecognized selector (был причиной сейфмода).
    // Замеряем текст старым sizeWithFont, доступным с iOS 2.
    // sizeWithFont:constrainedToSize: на iOS 6.1 при сборке новым SDK уходит в
    // несуществующий boundingRectWithSize (NSString-вариант только с iOS 7) —
    // меряем одной строкой и ограничиваем вручную
    CGFloat textW = ceilf([name sizeWithFont:font].width);
    if (textW <= 0.0) textW = 40.0;
    if (textW > MPPageW - 48.0) textW = MPPageW - 48.0;
    CGFloat startX = (MPPageW - (28.0 + 8.0 + textW)) / 2.0;
    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(startX, MPCardH + 10.0, 28.0, 28.0)];
    iconView.contentMode = UIViewContentModeScaleAspectFill;
    iconView.clipsToBounds = YES;
    [page addSubview:iconView];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(startX + 36.0, MPCardH + 10.0, textW + 4.0, 28.0)];
    label.font = font;
    label.textColor = [UIColor whiteColor];
    label.backgroundColor = nil;
    label.text = name;
    [page addSubview:label];

    // иконки идут через общий серийный загрузчик (один запрос за раз, кэш в памяти)
    if (entry != nil) {
        __weak UIImageView *weakSmall = iconView;
        __weak UIImageView *weakBig = placeholder;
        [MPIconLoader loadIconForEntry:entry completion:^(UIImage *icon) {
            if (icon == nil) return;
            weakSmall.image = icon;
            weakBig.image = icon;
        }];
    }
    return page;
}

// Снимок карточки: диск → фоновая очередь (чтение + декод + уменьшение) → главный
// поток. Если на диске пусто (обычно приложение на переднем плане) — живой снимок
// у SpringBoard, но когда анимация въезда уже улеглась: systemGestureSnapshotForApp
// рендерит и декодирует синхронно на главном потоке, в момент въезда карточек это
// давало фризы.
- (void)loadSnapshotIntoCard:(MPCard *)card bundleID:(NSString *)bid {
    __weak MPMultitaskView *weakSelf = self;
    __weak MPCard *weakCard = card;
    dispatch_async(MPSnapshotQueue(), ^{
        @autoreleasepool {
            UIImage *snap = MPSnapshotForBundleID(bid);            // только диск
            dispatch_async(dispatch_get_main_queue(), ^{
                MPCard *c = weakCard;
                MPMultitaskView *s = weakSelf;
                if (s == nil || !s.isOpen || c == nil || c.superview == nil || c.isClosing) return;
                if (snap != nil) {
                    if (c.snapView.image != snap) [s installSnapshot:snap onCard:c];
                    return;
                }
                if (c.snapView != nil) return;   // снимок уже стоит — живой не нужен
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    MPCard *cc = weakCard;
                    MPMultitaskView *ss = weakSelf;
                    if (ss == nil || !ss.isOpen || cc == nil || cc.superview == nil || cc.isClosing) return;
                    if (cc.snapView != nil) return;
                    UIImage *live = (ss.livePreviewBlock != nil) ? ss.livePreviewBlock(bid) : nil;
                    if (live != nil) [ss installSnapshot:live onCard:cc];
                });
            });
        }
    });
}

// Обновление снимков у уже собранных страниц (повторное открытие с тем же
// списком приложений)
- (void)refreshExistingSnapshots {
    for (MPCard *card in _cards) {
        if (card.isClosing || card.superview == nil) continue;
        [self loadSnapshotIntoCard:card bundleID:card.bundleID];
    }
}

// Снимок ложится поверх заглушки: иконка остаётся под ним и не мигает.
// Повторная установка заменяет предыдущий снимок, а не наслаивается на него.
- (void)installSnapshot:(UIImage *)snap onCard:(MPCard *)card {
    if (snap == nil || card == nil || card.superview == nil) return;
    if (card.snapView != nil) [card.snapView removeFromSuperview];
    UIImageView *snapView = [[UIImageView alloc] initWithFrame:card.bounds];
    snapView.contentMode = UIViewContentModeScaleAspectFill;
    snapView.clipsToBounds = YES;
    snapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    snapView.image = snap;
    card.snapView = snapView;
    [card addSubview:snapView];
}

// Снимок экрана приложения из системного кэша iOS 6
// (/var/mobile/Library/Caches/Snapshots/<bundle-id>/). Приложение попадает
// туда при уходе в фон; свежий файл выбираем по дате изменения.
// Декодированный результат кэшируется в памяти вместе с путём: повторное
// открытие свитчера не перечитывает диск, пока файл не сменился.
static UIImage *MPSnapshotForBundleID(NSString *bid) {
    if (bid.length == 0) return nil;
    @try {
        NSString *dir = [@"/var/mobile/Library/Caches/Snapshots" stringByAppendingPathComponent:bid];
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
        if (files.count == 0) return nil;

        NSMutableArray *paths = [NSMutableArray array];
        for (NSString *f in files) [paths addObject:[dir stringByAppendingPathComponent:f]];
        [paths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSDictionary *attrA = [fm attributesOfItemAtPath:a error:nil];
            NSDictionary *attrB = [fm attributesOfItemAtPath:b error:nil];
            NSDate *da = attrA[NSFileModificationDate] ?: [NSDate distantPast];
            NSDate *db = attrB[NSFileModificationDate] ?: [NSDate distantPast];
            return [db compare:da]; // свежие первыми
        }];

        NSDictionary *cached = [MPSnapshotMemCache() objectForKey:bid];
        if (cached != nil && [cached[@"path"] isEqualToString:paths[0]]) return cached[@"img"];

        for (NSUInteger i = 0; i < paths.count && i < 3; i++) {
            UIImage *raw = [UIImage imageWithContentsOfFile:paths[i]];
            if (raw == nil) continue;
            UIImage *decoded = MPDecodeAndFit(raw);
            [MPSnapshotMemCache() setObject:@{@"path": paths[0], @"img": decoded}
                                     forKey:bid];
            return decoded;
        }
    } @catch (NSException *e) {
        MPLog(@"!! снимок %@: %@ (%@)", bid, e.name, e.reason);
    }
    return nil;
}

#pragma mark Единый pan-жест: листание + закрытие

- (void)handleRootPan:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self];
    CGPoint v = [p velocityInView:self];

    if (p.state == UIGestureRecognizerStateBegan) {
        // останавливаем докат, если он ещё едет, иначе он будет спорить с пальцем
        [_pager setContentOffset:_pager.contentOffset animated:NO];
        _panMode = MPPanModeNone;
        _panStartOffset = _pager.contentOffset.x;
        _panCard = nil;
    } else if (p.state == UIGestureRecognizerStateChanged) {
        if (_panMode == MPPanModeNone) {
            // намерение определяем один раз, по первым ~12 pt движения
            if (fabsf(t.x) > 12.0 || fabsf(t.y) > 12.0) {
                if (fabsf(t.x) > fabsf(t.y)) {
                    _panMode = MPPanModePage;          // в стороны — листать
                } else if (t.y > 0.0) {
                    _panCard = [self cardForPageIndex:[self indexForOffset:_pager.contentOffset.x]];
                    _panMode = (_panCard != nil && !_panCard.isClosing) ? MPPanModeClose : MPPanModeIgnore;
                } else {
                    _panMode = MPPanModeIgnore;        // свайп вверх — ничего
                }
            }
        }

        if (_panMode == MPPanModePage) {
            CGFloat o = _panStartOffset - t.x;
            CGFloat minO = [self offsetForIndex:0];
            CGFloat maxO = [self offsetForIndex:(NSInteger)_pages.count - 1];
            if (o < minO) o = minO + (o - minO) * 0.35; // резинка на краях
            if (o > maxO) o = maxO + (o - maxO) * 0.35;
            [_pager setContentOffset:CGPointMake(o, 0)];
        } else if (_panMode == MPPanModeClose) {
            // карточка тянется за пальцем, слегка сжимаясь и гаснуя (как в WP8.1)
            CGFloat dy = MAX(t.y, -8.0);
            CGFloat k = MIN(MAX(dy, 0.0) / 260.0, 1.0);
            CGFloat sc = 1.0 - 0.18 * k;
            CGAffineTransform tr = CGAffineTransformMakeTranslation(0, dy);
            _panCard.transform = CGAffineTransformScale(tr, sc, sc);
            _panCard.alpha = 1.0 - 0.75 * k;
        }
    } else if (p.state == UIGestureRecognizerStateEnded ||
               p.state == UIGestureRecognizerStateCancelled) {
        if (_panMode == MPPanModePage) {
            // докат по скорости до ближайшей страницы — нативной анимацией скролла:
            // она обновляет contentOffset по ходу, поэтому новое касание её корректно
            // перехватывает (см. остановку в Began)
            CGFloat projected = _pager.contentOffset.x - v.x * 0.22;
            NSInteger target = [self indexForOffset:projected];
            _centeredIndex = target;
            CGFloat targetOffset = [self offsetForIndex:target];
            [_pager setContentOffset:CGPointMake(targetOffset, 0) animated:YES];
        } else if (_panMode == MPPanModeClose && _panCard != nil) {
            CGFloat dy = MAX(t.y, 0.0);
            BOOL dismiss = (dy > 120.0) || (v.y > 700.0 && dy > 30.0);
            if (dismiss) {
                _panCard.closing = YES;
                [_panCard flyOffDown];
                // гаснет вся страница, чтобы подпись с иконкой не висела отдельно
                UIView *page = _panCard.page;
                [UIView animateWithDuration:0.28
                    animations:^{ page.alpha = 0.0; }];
                [self killCard:_panCard];
            } else {
                [UIView animateWithDuration:0.22 delay:0
                    options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                    animations:^{
                        self->_panCard.transform = CGAffineTransformIdentity;
                        self->_panCard.alpha = 1.0;
                    }
                    completion:nil];
            }
        }
        _panMode = MPPanModeNone;
        _panCard = nil;
    }
}

#pragma mark Действия над карточками

- (void)activateBundleID:(NSString *)bid card:(MPCard *)card {
    if (!_open || card == nil || card.isClosing) return;
    _open = NO; // свитчер уходит — повторные тапы и жесты силы не имеют
    @try {
        // WP-переход «карточка раскрывается в приложение»:
        // 1) прочие страницы гаснут, карточка растёт;
        [UIView animateWithDuration:0.24
            animations:^{
                for (UIView *p in self->_pages) {
                    if (p != card.page) p.alpha = 0.0;
                }
                self->_emptyLabel.alpha = 0.0;
                card.transform = CGAffineTransformMakeScale(1.18, 1.18);
            }
            completion:^(BOOL finished) {
                // 2) фон свитчера тает, и только потом запускается приложение
                [UIView animateWithDuration:0.12
                    animations:^{ self.alpha = 0.0; }
                    completion:^(BOOL innerFinished) {
                        self.hidden = YES;
                        self.alpha = 1.0;
                        card.transform = CGAffineTransformIdentity;
                        if (self.onActivateBlock != nil) self.onActivateBlock(bid);
                    }];
            }];
    } @catch (NSException *e) {
        // страховка: при любой ошибке просто прячем свитчер и запускаем приложение
        MPLog(@"!! переход в %@: %@ (%@)", bid, e.name, e.reason);
        self.hidden = YES;
        self.alpha = 1.0;
        if (self.onActivateBlock != nil) self.onActivateBlock(bid);
    }
}

- (void)killCard:(MPCard *)card {
    @try {
        if (self.onCloseBlock != nil) self.onCloseBlock(card.bundleID); // kill процесса
        // страницу убираем после того, как карточка улетит вниз (0.3 с анимации)
        __weak MPMultitaskView *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.33 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [weakSelf removePageForCard:card];
        });
    } @catch (NSException *e) {
        MPLog(@"!! закрытие карточки %@: %@ (%@)", card.bundleID, e.name, e.reason);
    }
}

- (void)removePageForCard:(MPCard *)card {
    @try {
        UIView *page = card.page;
        if (page == nil) return;
        NSInteger idx = [_pages indexOfObject:page];
        if (idx == NSNotFound) return; // свитчер уже пересобран — карточка устарела

        [_pages removeObjectAtIndex:idx];
        if (idx < (NSInteger)_cards.count) [_cards removeObjectAtIndex:idx];
        [page removeFromSuperview];
        _lastAppIDs = nil;   // страницы изменились — следующее открытие обязано пересобраться
        _pager.contentSize = CGSizeMake(MAX(_pages.count, 1) * MPPageW, MPPagerH);

        if (idx < _centeredIndex) _centeredIndex--;
        if (_centeredIndex > (NSInteger)_pages.count - 1) _centeredIndex = (NSInteger)_pages.count - 1;

        // страницы правее закрытой сдвигаются на её место
        [UIView animateWithDuration:0.24
            animations:^{
                for (NSUInteger i = (NSUInteger)idx; i < self->_pages.count; i++) {
                    UIView *p = self->_pages[i];
                    p.frame = CGRectMake(i * MPPageW, 0, MPPageW, MPPagerH);
                }
            }];

        if (_pages.count == 0) {
            // закрыли последнее приложение — свитчер больше не нужен
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (self->_open && self->_pages.count == 0) [self closeAnimated:YES];
            });
            return;
        }

        // держим центрированную страницу по центру
        [_pager setContentOffset:CGPointMake([self offsetForIndex:_centeredIndex], 0) animated:YES];
    } @catch (NSException *e) {
        MPLog(@"!! удаление страницы: %@ (%@)", e.name, e.reason);
    }
}

@end
