#import "MPCalendarPivotView.h"
#import "MPCalendarTheme.h"
#import "MPCalendarPages.h"
#import "MPCalendarData.h"
#import "MPCalendarEditor.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <QuartzCore/QuartzCore.h>

//──────────────────────────────────────────────────────────────────────────────
// Механика скопирована с «Часов» (E3-ШАПКА-WP): системный UIScrollView с
// pagingEnabled, кольцо-скользящее окно (активная страница всегда в слоте 2,
// normalizeAfterStop молча перекладывает кластер и возвращает contentOffset
// в центр без анимации), шапка — слотовая WP-сетка с лерп-доводкой.

static NSInteger const MPPageCount = 4;

// МАРКЕР СБОРКИ — пишем в журнал при запуске (свежесть dylib проверять журналом)
static NSString * const MPCalendarBuildTag = @"CAL-2-АУДИТ";

static MPCalendarPivotView *MPCalendarSharedPivot = nil;   // для отладки

static NSInteger const MPCalCenterSlot = 2;                     // слот активной

static NSInteger MPCalMod4(NSInteger x) { return ((x % 4) + 4) % 4; }

@interface MPCalendarPivotView () <UIScrollViewDelegate>
@property (nonatomic, retain) UIView *headerRow;
@property (nonatomic, retain) UIView *actionsRow;
@property (nonatomic, retain) NSArray *pages;
@end

@implementation MPCalendarPivotView {
    UIButton *_headers[4];
    UIButton *_actA[4];      // левая кнопка действия («сегодня»/«добавить»)
    UIButton *_actB[4];      // правая (только «день»: пара добавить+сегодня)
    CGFloat _actAW[4], _actBW[4];
    NSTimer *_tickTimer;
    UIScrollView *_hScroll;
    NSInteger _curPage;
    CGFloat _vOffset, _vAnchor;
    NSUInteger _lastGen;     // поколение данных последней пересборки
    BOOL _pendingReload;     // данные изменились во время жеста — пересобрать после остановки
    // отладочный драйв (calslow/caburst): displayLink ведёт contentOffset
    CADisplayLink *_drvLink;
    CGFloat _drvFrom, _drvTo, _drvStart, _drvDur;
    NSInteger _drvShot, _drvMode;
    BOOL _drvShots, _drvWasScrollEnabled;
    NSMutableArray *_drvLog;
}

+ (MPCalendarPivotView *)installedPivotInView:(UIView *)host {
    for (UIView *v in host.subviews) {
        if ([v isKindOfClass:[MPCalendarPivotView class]]) {
            [host bringSubviewToFront:v];
            return (MPCalendarPivotView *)v;
        }
    }
    MPCalendarPivotView *p = [[MPCalendarPivotView alloc] initWithFrame:host.bounds];
    MPCalendarSharedPivot = p;
    [host addSubview:p];
    MPLog(@"[Calendar] pivot установлен (%.0f×%.0f)",
          host.bounds.size.width, host.bounds.size.height);
    return p;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.clipsToBounds = YES;

        NSString *titles[4] = {@"месяц", @"неделя", @"день", @"повестка"};

        // ленты-контейнеры шире экрана: hitTest пускает тапы только внутри
        // bounds супервью (рисование не клипуется, касания — да)
        CGFloat beltW = MPCalStride * MPPageCount;
        CGFloat topInset = [MPMetroStyle statusBarInset];

        _headerRow = [[UIView alloc] initWithFrame:CGRectMake(0.0f, topInset, beltW, MPCalHeaderH)];
        [self addSubview:_headerRow];

        CGFloat topPad = 24.0f;
        CGFloat availW = frame.size.width - MPCalLead * 2.0f;
        for (NSInteger i = 0; i < MPPageCount; i++) {
            NSString *t = titles[i];
            // ужатие как в шапке «Настроек»: 52 → 38 → 30
            UIFont *f = nil;
            CGFloat size = 52.0f;
            for (; size >= 30.0f; size -= 2.0f) {
                f = [MPMetroStyle lightFont:size];
                if ([t sizeWithFont:f].width <= availW) break;
            }
            CGSize s = [t sizeWithFont:f];
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(0.0f, topPad, ceilf(s.width) + 4.0f, ceilf(s.height) + 4.0f);
            b.titleLabel.font = f;
            [b setTitle:t forState:UIControlStateNormal];
            [b setTitleColor:[MPCalendarTheme faintColor] forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            b.tag = i;
            [b addTarget:self action:@selector(headerTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_headerRow addSubview:b];
            _headers[i] = b;
        }

        // строка действий: месяц/неделя — «сегодня», день/повестка — «добавить»
        // (белые light 24, едут со своими заголовками; пары не ставим — шаг
        // слотовой сетки меньше ширины пары, действия соседей наезжали)
        _actionsRow = [[UIView alloc] initWithFrame:CGRectMake(0.0f, topInset + MPCalHeaderH,
                                                                beltW, MPCalActionsH)];
        [self addSubview:_actionsRow];
        NSString *actATitle[4] = {@"сегодня", @"сегодня", @"добавить", @"добавить"};
        for (NSInteger i = 0; i < MPPageCount; i++) {
            UIButton *a = [MPCalendarTheme actionButtonWithTitle:actATitle[i]];
            a.tag = i;
            [a addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_actionsRow addSubview:a];
            _actA[i] = a;
        }

        // системный горизонтальный пейджер
        CGFloat contentTop = topInset + MPCalHeaderBottom + MPCalTopGap;
        CGFloat contentH = frame.size.height - contentTop;
        _hScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0.0f, contentTop,
                                                                   frame.size.width, contentH)];
        _hScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _hScroll.pagingEnabled = YES;
        _hScroll.contentSize = CGSizeMake(MPCalStride * MPPageCount, contentH);
        _hScroll.showsHorizontalScrollIndicator = NO;
        _hScroll.showsVerticalScrollIndicator = NO;
        _hScroll.clipsToBounds = NO;
        _hScroll.backgroundColor = [UIColor clearColor];
        _hScroll.delegate = self;
        [self addSubview:_hScroll];

        MPCalendarMonthPage *month = [[MPCalendarMonthPage alloc]
                                      initWithFrame:CGRectMake(0.0f, 0.0f, MPCalStride, contentH)];
        MPCalendarWeekPage *week = [[MPCalendarWeekPage alloc]
                                    initWithFrame:CGRectMake(0.0f, 0.0f, MPCalStride, contentH)];
        MPCalendarDayPage *day = [[MPCalendarDayPage alloc]
                                  initWithFrame:CGRectMake(0.0f, 0.0f, MPCalStride, contentH)];
        MPCalendarAgendaPage *agenda = [[MPCalendarAgendaPage alloc]
                                        initWithFrame:CGRectMake(0.0f, 0.0f, MPCalStride, contentH)];
        _pages = @[month, week, day, agenda];

        __weak MPCalendarPivotView *wSelf = self;
        // тап по дате в месяце/неделе → переход в «День» на эту дату
        void (^onDate)(NSDate *) = ^(NSDate *dayStart) {
            [wSelf gotoPage:2 date:dayStart animated:YES];
        };
        // тап по событию в дне/повестке → редактор
        void (^onEvent)(MPCalendarEvent *) = ^(MPCalendarEvent *ev) {
            [[MPCalendarEditor sharedEditor] presentInPivot:wSelf event:ev.sourceEvent];
        };
        month.onSelectDate = onDate;
        week.onSelectDate = onDate;
        day.onSelectEvent = onEvent;
        agenda.onSelectEvent = onEvent;

        for (NSInteger i = 0; i < MPPageCount; i++) {
            UIView *pg = [_pages objectAtIndex:i];
            pg.autoresizingMask = UIViewAutoresizingFlexibleHeight;
            [_hScroll addSubview:pg];
        }

        // КОЛЬЦО: старт — страница 0 («месяц») в центральном слоте
        _curPage = 0;
        _lastGen = (NSUInteger)-1;   // первая reloadData обязана пересобрать
        [self layoutPages];
        _vOffset = 0.0f;
        _vAnchor = MPCalCenterSlot * MPCalStride;
        [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];

        // тик раз в 30 с: линия «сейчас» (день) и перерисовка недели
        _tickTimer = [NSTimer timerWithTimeInterval:30.0 target:self selector:@selector(clockTick)
                                            userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_tickTimer forMode:NSRunLoopCommonModes];

        // изменения хранилища (в т.ч. из нашего редактора) → перечитать страницы
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(dataChanged:)
                                                     name:MPCalendarDataDidChangeNotification
                                                   object:nil];

        MPLog(@"[Calendar] сборка %@", MPCalendarBuildTag);

        // ВАЖНО: контент страниц здесь НЕ строим — вьюха ещё НЕ в окне, и iOS 6
        // не отрисует слои, созданные до addSubview (у юзера: месяц/неделя пустые
        // при запуске, оживают при следующем свайпе). reloadData зовётся из
        // MPCalendarHooks уже ПОСЛЕ установки пивота в окно.
        [self layoutActionButtons];
        [self syncChrome];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tickTimer invalidate];
    [_drvLink invalidate];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - КОЛЬЦО

- (void)layoutPages {
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIScrollView *pg = (UIScrollView *)[_pages objectAtIndex:i];
        NSInteger slot = MPCalMod4(i - _curPage + MPCalCenterSlot);
        CGPoint co = pg.contentOffset;   // setFrame сбрасывает bounds.origin
        CGRect f = pg.frame;
        f.origin.x = slot * MPCalStride;
        pg.frame = f;
        pg.contentOffset = co;
    }
}

- (void)normalizeAfterStop {
    NSInteger slot = (NSInteger)lroundf((float)(_hScroll.contentOffset.x / MPCalStride));
    if (slot < 0) slot = 0;
    if (slot > MPPageCount - 1) slot = MPPageCount - 1;
    if (slot == MPCalCenterSlot) {
        // прерванный анимированный скролл мог оставить offset между страницами —
        // тихо дощёлкиваем до центра (якорь предустанавливаем: дельта не
        // должна попасть в _vOffset)
        CGFloat target = MPCalCenterSlot * MPCalStride;
        if (fabsf(_hScroll.contentOffset.x - target) > 0.5f) {
            _vAnchor = target;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [_hScroll setContentOffset:CGPointMake(target, 0.0f) animated:NO];
            [CATransaction commit];
        }
        if (_pendingReload) { _pendingReload = NO; [self reloadData]; }
        return;
    }

    NSInteger newCur = MPCalMod4(_curPage + slot - MPCalCenterSlot);
    _curPage = newCur;
    _vAnchor = MPCalCenterSlot * MPCalStride;   // якорь до прыжка — дельта не попадает в _vOffset

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self layoutPages];
    [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];
    [CATransaction commit];

    [self syncChrome];
    if (_pendingReload) { _pendingReload = NO; [self reloadData]; }
    MPLog(@"[Calendar] кольцо: слот %ld → страница %ld", (long)slot, (long)newCur);
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Данные и действия

- (void)dataChanged:(NSNotification *)n {
    // жест/докат не прерываем — пересоберёмся, когда лента остановится
    // (normalizeAfterStop), иначе восстановление contentOffset рвёт палец
    if (_hScroll.tracking || _hScroll.dragging || _hScroll.decelerating) {
        _pendingReload = YES;
        return;
    }
    // пересборка при ещё открытом редакторе фризит его dismiss-анимацию —
    // даём ей улечься
    MPCalendarEditor *ed = [MPCalendarEditor sharedEditor];
    if (ed.superview != nil && !ed.hidden) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self reloadData]; });
        return;
    }
    [self reloadData];
}

- (void)reloadData {
    // пересборка дорогая (сотни вьюх на A4): viewDidAppear и активация
    // приложения приходят постоянно — пересобираемся только если данные
    // реально менялись (поколение бампится в invalidateCache)
    NSUInteger gen = [[MPCalendarData sharedData] dataGeneration];
    if (gen == _lastGen) return;
    _lastGen = gen;
    for (UIView *pg in _pages) {
        if ([pg respondsToSelector:@selector(reload)]) [(id)pg performSelector:@selector(reload)];
        // секции рисуются drawRect'ом лениво — без пинка iOS 6 не перерисует
        // их после пересборки (экран оставался пустым до следующего свайпа)
        [pg setNeedsLayout];
        [pg setNeedsDisplay];
    }
}

- (void)clockTick {
    if (_hScroll.tracking || _hScroll.dragging || _hScroll.decelerating) return;
    for (UIView *pg in _pages) {
        if ([pg respondsToSelector:@selector(tick)]) [(id)pg performSelector:@selector(tick)];
    }
}

- (MPCalendarBasePage *)page:(NSInteger)i {
    return [_pages objectAtIndex:i];
}

- (NSInteger)slotForPage:(NSInteger)tag {
    NSInteger d = MPCalMod4(tag - _curPage);
    if (d == 0) return MPCalCenterSlot;
    if (d == 1) return 3;
    if (d == 3) return 1;
    return 0;   // d == 2
}

- (void)headerTapped:(UIButton *)sender {
    NSInteger slot = [self slotForPage:sender.tag];
    if (slot == MPCalCenterSlot) return;
    if (_hScroll.decelerating) {
        // iOS 6: setContentOffset:animated: при декелерации молча
        // игнорируется — сперва тихо дощёлкиваем докат до центра
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _vAnchor = MPCalCenterSlot * MPCalStride;
        [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];
        [CATransaction commit];
        [self normalizeAfterStop];
    }
    [_hScroll setContentOffset:CGPointMake(slot * MPCalStride, 0.0f) animated:YES];
}

// программный переход (тап по дате, отладка): лента целиковой страницы
// прокручивается сразу, пивот приезжает поверх неё
- (void)gotoPage:(NSInteger)page date:(NSDate *)date animated:(BOOL)animated {
    if (date != nil) {
        for (NSInteger i = 0; i < MPPageCount; i++) {
            [[self page:i] gotoDayStart:date animated:NO];
        }
    }
    NSInteger slot = [self slotForPage:page];
    if (slot == MPCalCenterSlot && date != nil) return;
    if (slot == MPCalCenterSlot) return;
    if (!animated) {
        // телепорт: якорь предустанавливаем, иначе прыжок целиком попал бы
        // в дельту didScroll и сместил виртуальный offset на ±2 страницы
        _vAnchor = slot * MPCalStride;
    }
    [_hScroll setContentOffset:CGPointMake(slot * MPCalStride, 0.0f) animated:animated];
}

- (void)actionTapped:(UIButton *)sender {
    NSInteger i = sender.tag;
    NSString *title = sender.currentTitle;
    if ([title isEqualToString:@"сегодня"]) {
        [[self page:i] scrollToTodayAnimated:YES];
        MPLog(@"[Calendar] «сегодня» на странице %ld", (long)i);
    } else if ([title isEqualToString:@"добавить"]) {
        MPLog(@"[Calendar] «добавить» (страница %ld)", (long)i);
        [[MPCalendarEditor sharedEditor] presentInPivot:self event:nil];
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Шапка (слотовая WP-сетка)

- (void)layoutActionButtons {
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIButton *a = _actA[i];
        if (a == nil) continue;
        _actAW[i] = ceilf([a.titleLabel.text sizeWithFont:a.titleLabel.font].width) + 4.0f;
        UIButton *b = _actB[i];
        _actBW[i] = b ? ceilf([b.titleLabel.text sizeWithFont:b.titleLabel.font].width) + 4.0f : 0.0f;
    }
}

- (CGFloat)headerStep:(NSInteger)m {
    return _headers[m].frame.size.width + MPCalHeaderGap;
}

- (CGFloat)headerQ:(NSInteger)i k:(NSInteger)k {
    CGFloat s = 0.0f;
    if (k > 0) {
        for (NSInteger j = 0; j < k; j++) s -= [self headerStep:MPCalMod4(i + j)];
    } else {
        for (NSInteger j = -1; j >= k; j--) s += [self headerStep:MPCalMod4(i + j)];
    }
    return s;
}

- (void)syncChrome {
    CGFloat p = _vOffset / MPCalStride;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    for (NSInteger i = 0; i < MPPageCount; i++) {
        CGFloat n = fmodf((float)(p - i) + 2.0f, 4.0f);
        if (n < 0.0f) n += 4.0f;
        n -= 2.0f;
        NSInteger k = (NSInteger)floorf(n);
        CGFloat t = (float)(n - k);
        CGFloat q = [self headerQ:i k:k] * (1.0f - t) + [self headerQ:i k:k + 1] * t;
        CGRect f = _headers[i].frame;
        f.origin.x = MPCalLead + q;
        _headers[i].frame = f;
    }

    // активная страница по кольцу (меняется на СЕРЕДИНЕ свайпа)
    NSInteger active = MPCalMod4((NSInteger)lroundf((float)p));
    for (NSInteger i = 0; i < MPPageCount; i++) {
        [_headers[i] setSelected:(i == active)];
    }

    // действия — привязаны к разделам: у каждой страницы СВОЯ кнопка, едет
    // 1:1 с контентом своей страницы. Экранный x считаем из РЕАЛЬНОЙ
    // раскладки (слот фреймом минус offset пейджера): виртуальный _vOffset
    // безграничен (320·N через кольцо) и слоту по Mod4 несоизмерим —
    // старая формула была верна только при активном «Дне»
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIView *pg = [_pages objectAtIndex:i];
        CGFloat pageX = pg.frame.origin.x - _hScroll.contentOffset.x;
        _actA[i].frame = CGRectMake(MPCalLead + pageX, 0.0f, _actAW[i], MPCalActionsH);
        if (_actB[i] != nil) {
            _actB[i].frame = CGRectMake(MPCalLead + pageX + (_actAW[i] - 4.0f) + MPCalActionsGap,
                                        0.0f, _actBW[i], MPCalActionsH);
        }
    }

    [CATransaction commit];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    _vOffset += (scrollView.contentOffset.x - _vAnchor);
    _vAnchor = scrollView.contentOffset.x;
    [self syncChrome];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) [self normalizeAfterStop];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self normalizeAfterStop];
    [self clockTick];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    [self normalizeAfterStop];
    [self clockTick];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - ОТЛАДКА (канал shot.request, как у «Часов»)

- (void)driveToPage:(NSInteger)page duration:(CGFloat)dur mode:(NSInteger)mode shots:(BOOL)shots {
    if (_drvLink != nil) return;
    if (_hScroll.tracking || _hScroll.dragging || _hScroll.decelerating) {
        MPLog(@"[Calendar] отладка: отказ — живой скролл ещё идёт");
        return;
    }
    _drvFrom = _hScroll.contentOffset.x;
    _drvTo = [self slotForPage:page] * MPCalStride;
    if (_drvTo == _drvFrom) {
        MPLog(@"[Calendar] отладка: страница %ld уже активна", (long)page);
        return;
    }
    _drvStart = CACurrentMediaTime();
    _drvShot = 0;
    _drvDur = MAX(0.2, dur);
    _drvShots = shots;
    _drvMode = mode;
    _drvWasScrollEnabled = _hScroll.scrollEnabled;
    _hScroll.scrollEnabled = NO;
    _drvLog = [NSMutableArray array];
    _drvLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(drvTick)];
    [_drvLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    MPLog(@"[Calendar] отладка: драйв %.0f → %.0f за %.1f с (mode %ld)",
          _drvFrom, _drvTo, _drvDur, (long)mode);
}

- (void)drvTick {
    CGFloat t = (float)((CACurrentMediaTime() - _drvStart) / _drvDur);
    BOOL done = (t >= 1.0f);
    if (done) t = 1.0f;
    CGFloat k = t;
    if (_drvMode == 1) {   // «палец»: вперёд, откат, снова вперёд
        k = t < 0.6f ? (t / 0.6f)
          : t < 0.75f ? (1.0f - (t - 0.6f) / 0.15f * 0.15f)
          : (0.85f + (t - 0.75f) / 0.25f * 0.15f);
    }
    CGFloat x = _drvFrom + (_drvTo - _drvFrom) * k;
    [_hScroll setContentOffset:CGPointMake(x, 0.0f) animated:NO];
    [_drvLog addObject:[NSString stringWithFormat:@"%.0f", x]];

    if (_drvShots) {
        static CGFloat marks[6] = {0.06f, 0.22f, 0.38f, 0.54f, 0.72f, 0.92f};
        if (_drvShot < 6 && t >= marks[_drvShot]) [self mpBurstShot];
    }

    if (done) {
        [_drvLink invalidate];
        _drvLink = nil;
        _hScroll.scrollEnabled = _drvWasScrollEnabled;
        [self normalizeAfterStop];
        if (_drvMode == 1) {
            MPLog(@"[Calendar] палец завершён: %@", [_drvLog componentsJoinedByString:@" "]);
        } else if (_drvShots) {
            MPLog(@"[Calendar] burst завершён (6 кадров)");
        }
    }
}

- (void)debugGoTo:(NSInteger)page duration:(CGFloat)dur {
    [self driveToPage:page duration:dur mode:0 shots:NO];
}

- (void)debugBurst {
    [self driveToPage:(_curPage + 1) % MPPageCount duration:2.5 mode:0 shots:YES];
}

- (void)debugFinger {
    [self driveToPage:(_curPage + 1) % MPPageCount duration:3.0 mode:1 shots:NO];
}

- (void)mpBurstShot {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0);
    [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    // sandbox MobileCal запрещает запись в Caches — пишем рядом с журналом
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/burst%ld.png",
                      (long)_drvShot];
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    MPLog(@"[Calendar] burst %ld (offset %.0f) → %@", (long)_drvShot, _hScroll.contentOffset.x, path);
    _drvShot++;
}

- (void)debugScrollFront:(float)fraction {
    UIScrollView *pg = [_pages objectAtIndex:_curPage];
    CGFloat maxOff = pg.contentSize.height - pg.bounds.size.height;
    if (maxOff < 1) {
        MPLog(@"[Calendar] отладка: странице %ld нечего скроллить", (long)_curPage);
        return;
    }
    CGPoint o = pg.contentOffset;
    o.y = maxOff * fraction;
    pg.contentOffset = o;
    MPLog(@"[Calendar] отладка: прокрутка страницы %ld на %.2f", (long)_curPage, fraction);
}

// прыжок на дату (формат YYYY-MM-DD) — проверка лент
- (void)debugDate:(NSString *)dateStr {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd"];
    NSDate *date = [df dateFromString:dateStr];
    if (date == nil) {
        MPLog(@"[Calendar] отладка: не понял дату %@ (нужен YYYY-MM-DD)", dateStr);
        return;
    }
    NSDate *day = [[MPCalendarData sharedData] startOfDayForDate:date];
    for (NSInteger i = 0; i < MPPageCount; i++) {
        [[self page:i] gotoDayStart:day animated:NO];
    }
    MPLog(@"[Calendar] отладка: ленты на %@", dateStr);
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - C-обёртки для Tweak.xm (отладочные команды)

void MPCalendarDebugScroll(float fraction) {
    if (MPCalendarSharedPivot == nil) return;
    [MPCalendarSharedPivot debugScrollFront:fraction];
}

void MPCalendarDebugGoTo(NSInteger page, CGFloat dur) {
    if (MPCalendarSharedPivot == nil) return;
    [MPCalendarSharedPivot debugGoTo:page duration:dur];
}

void MPCalendarDebugBurst(void) {
    if (MPCalendarSharedPivot == nil) return;
    [MPCalendarSharedPivot debugBurst];
}

void MPCalendarDebugFinger(void) {
    if (MPCalendarSharedPivot == nil) return;
    [MPCalendarSharedPivot debugFinger];
}

void MPCalendarDebugDate(NSString *dateStr) {
    if (MPCalendarSharedPivot == nil) return;
    [MPCalendarSharedPivot debugDate:dateStr];
}

// одиночный снимок окна Календаря (команда calshot)
void MPCalendarDebugShot(void) {
    if (MPCalendarSharedPivot == nil) return;
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0);
    [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSString *path = @"/var/mobile/Library/Preferences/calshot.png";
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    MPLog(@"[Calendar] снимок → %@", path);
}
