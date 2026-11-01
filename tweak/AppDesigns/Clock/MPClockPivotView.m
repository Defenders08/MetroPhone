#import "MPClockPivotView.h"
#import "MPClockTheme.h"
#import "MPClockPages.h"
#import "MPClockEditor.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <QuartzCore/QuartzCore.h>

//──────────────────────────────────────────────────────────────────────────────
// План E + КОЛЬЦО: листание ведёт СИСТЕМНЫЙ UIScrollView с pagingEnabled,
// contentOffset — единственный источник правды. Бесконечность — «скользящее
// окно»: 4 слота, активная страница всегда в ЦЕНТРАЛЬНОМ (2), слева/справа
// соседи по кольцу. После каждой остановки кластер страниц молча
// перекладывается вокруг новой активной (setFrame с сохранением вертикального
// contentOffset) и contentOffset прыгает назад в центр БЕЗ анимации —
// экранно ничего не двигается. Дублей страниц нет: страница — один живой
// объект (секундомер/таймер тикают в единственном экземпляре).
// Шапка — СЛОТОВАЯ СЕТКА WP: заголовки стоят в ряд своими шагами (ширина +
// зазор), активный всегда на Lead, сосед выглядит справа; при листании лента
// едет с доводкой — медленнее контента, разная скорость на сегментах (фирменное
// «дыхание» WP-pivot), направление всегда согласно контенту, кольцо без
// встречных скачков (позиция — кусочно-линейная функция от виртуального offset).
//──────────────────────────────────────────────────────────────────────────────

static NSInteger const MPPageCount = 4;

// МАРКЕР СБОРКИ — пишем в журнал при запуске (экранную метку сняли 31.10
// по просьбе юзера; свежесть dylib проверять журналом)
static NSString * const MPClockBuildTag = @"E3-ШАПКА-WP";

static MPClockPivotView *MPClockSharedPivot = nil;   // для отладочной прокрутки

static NSInteger const MPClockCenterSlot = 2;              // слот активной страницы
static CGFloat const MPClockRingW = MPClockStride * 4.0f;  // период кольца (1280)

static NSInteger MPClockMod4(NSInteger x) { return ((x % 4) + 4) % 4; }

// Заворот в [−ring/2, ring/2): элементы прыгают на дальнем краю кольца,
// гарантированно за экраном (|значение| ≥ 640, экран видит ±330)
static CGFloat MPClockWrapC(CGFloat x) {
    CGFloat half = MPClockRingW / 2.0f;
    CGFloat m = fmodf(x + half, MPClockRingW);
    if (m < 0.0f) m += MPClockRingW;
    return m - half;
}

@interface MPClockPivotView () <UIScrollViewDelegate>
@property (nonatomic, retain) UIView *headerRow;      // контейнер заголовков
@property (nonatomic, retain) NSArray *pages;
@end

@implementation MPClockPivotView {
    UIButton *_headers[4];   // заголовки (только ivar: C-массив не свойство)
    UIButton *_actA[4];      // левые кнопки пар по страницам (Изменить)
    UIButton *_actB[4];      // правые кнопки пар (Добавить)
    CGFloat _actAW[2], _actBW[2];   // ширины пар (кэш, позиции считает syncChrome)
    NSTimer *_tickTimer;
    UIScrollView *_hScroll;  // системный горизонтальный пейджер — драйв листания
    NSInteger _curPage;      // активная страница 0..3 (для раскладки слотов)
    CGFloat _vOffset;        // виртуальный безграничный offset (шапка/квадрат)
    CGFloat _vAnchor;        // contentOffset на момент последнего didScroll
    // отладочный драйв (cslow/cburst/cfinger): displayLink ведёт contentOffset
    CADisplayLink *_drvLink;
    CGFloat _drvFrom, _drvTo, _drvStart, _drvDur;
    NSInteger _drvShot, _drvMode;   // 0 = линейный (cslow/cburst), 1 = «палец»
    BOOL _drvShots, _drvWasScrollEnabled;
    NSMutableArray *_drvLog;        // диагностика: offset по кадрам
    // квадратный прогресс таймера — на КОРНЕ пивота (не на странице: слои
    // скроллвю рендерятся непредсказуемо), позиция синхронизируется из v
    UIView *_timerSquare;
    CAShapeLayer *_sqTrack, *_sqProg;
}

+ (MPClockPivotView *)installedPivotInView:(UIView *)host {
    for (UIView *v in host.subviews) {
        if ([v isKindOfClass:[MPClockPivotView class]]) {
            [host bringSubviewToFront:v];
            return (MPClockPivotView *)v;
        }
    }
    MPClockPivotView *p = [[MPClockPivotView alloc] initWithFrame:host.bounds];
    MPClockSharedPivot = p;
    [host addSubview:p];
    MPLog(@"[Clock] pivot установлен (%.0f×%.0f)", host.bounds.size.width, host.bounds.size.height);
    return p;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.clipsToBounds = YES;

        NSString *titles[4] = {@"Мировые часы", @"Будильник", @"Секундомер", @"Таймер"};

        // лента-контейнеры шире экрана — hitTest пускает касания только в
        // точки внутри bounds супервью (рисование не клипуется, тапы — нет)
        CGFloat beltW = MPClockStride * MPPageCount;

        // шапка как на НАТИВНЫХ страницах «Настроек» (замер 30.10: заголовок
        // «Основные» на 57.5 pt). Весь контент pivot сдвигается на statusBarInset
        CGFloat topInset = [MPMetroStyle statusBarInset];
        _headerRow = [[UIView alloc] initWithFrame:CGRectMake(0.0f, topInset, beltW, MPClockHeaderH)];
        [self addSubview:_headerRow];

        CGFloat topPad = 24.0f;
        CGFloat availW = frame.size.width - MPClockLead * 2.0f;
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
            // стартовый x неважен — позиции заголовков ставит syncChrome по
            // кольцу (кнопка — не скроллвью, setFrame ей безвреден)
            b.frame = CGRectMake(0.0f, topPad, ceilf(s.width) + 4.0f, ceilf(s.height) + 4.0f);
            b.titleLabel.font = f;
            [b setTitle:t forState:UIControlStateNormal];
            // WP-канон: активная страница — белая, соседние приглушённые
            [b setTitleColor:[MPClockTheme faintColor] forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            b.tag = i;
            [b addTarget:self action:@selector(headerTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_headerRow addSubview:b];
            _headers[i] = b;
        }

        // пары «Изменить/Добавить» (стр. 0–1) создаются ПОСЛЕ страниц и
        // кладутся ВНУТРЬ них (как Круг/Старт у Секундомера): отдельной полосы
        // действий в шапке больше нет — на вкладках без кнопок не остаётся
        // пустого отступа

        // системный горизонтальный пейджер: contentOffset — источник правды.
        // clipsToBounds = NO: Секундомер рисует цифры выше зоны контента
        // (y=−50 в координатах страницы — канон юзера), резать нельзя.
        // Старт сразу под заголовком (+зазор): строки действий в шапке нет
        CGFloat contentTop = topInset + MPClockHeaderH + MPClockTopGap;
        CGFloat contentH = frame.size.height - contentTop;
        _hScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0.0f, contentTop,
                                                                   frame.size.width, contentH)];
        _hScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _hScroll.pagingEnabled = YES;
        _hScroll.contentSize = CGSizeMake(MPClockStride * MPPageCount, contentH);
        _hScroll.showsHorizontalScrollIndicator = NO;
        _hScroll.showsVerticalScrollIndicator = NO;
        _hScroll.clipsToBounds = NO;
        _hScroll.backgroundColor = [UIColor clearColor];
        _hScroll.delegate = self;
        [self addSubview:_hScroll];

        // квадратный прогресс таймера: рамка-трек + акцентный ход; кадр
        // синхронизируется с виртуальным offset (живёт на корне, поверх пейджера)
        _timerSquare = [[UIView alloc] initWithFrame:CGRectZero];
        _timerSquare.backgroundColor = [UIColor clearColor];
        _timerSquare.userInteractionEnabled = NO;
        _timerSquare.hidden = YES;
        [self addSubview:_timerSquare];

        CGMutablePathRef sqp = CGPathCreateMutable();
        CGPathAddRect(sqp, NULL, CGRectMake(3.0f, 3.0f, 164.0f, 164.0f));
        _sqTrack = [CAShapeLayer layer];
        _sqTrack.frame = _timerSquare.bounds;
        _sqTrack.path = sqp;
        _sqTrack.lineWidth = 6.0f;
        _sqTrack.strokeColor = [UIColor colorWithWhite:1.0f alpha:0.14f].CGColor;
        _sqTrack.fillColor = NULL;
        [_timerSquare.layer addSublayer:_sqTrack];

        _sqProg = [CAShapeLayer layer];
        _sqProg.frame = _timerSquare.bounds;
        _sqProg.path = sqp;
        _sqProg.lineWidth = 6.0f;
        _sqProg.strokeColor = [MPMetroStyle accentColor].CGColor;
        _sqProg.fillColor = NULL;
        _sqProg.strokeEnd = 1.0f;
        [_timerSquare.layer addSublayer:_sqProg];
        CGPathRelease(sqp);

        MPClockWorldPage *world = [[MPClockWorldPage alloc] initWithFrame:CGRectMake(0.0f, 0.0f, MPClockStride, contentH)];
        MPClockAlarmPage *alarm = [[MPClockAlarmPage alloc] initWithFrame:CGRectMake(0.0f, 0.0f, MPClockStride, contentH)];
        MPClockStopwatchPage *sw = [[MPClockStopwatchPage alloc] initWithFrame:CGRectMake(0.0f, 0.0f, MPClockStride, contentH)];
        MPClockTimerPage *timer = [[MPClockTimerPage alloc] initWithFrame:CGRectMake(0.0f, 0.0f, MPClockStride, contentH)];
        _pages = @[world, alarm, sw, timer];

        // пары действий — внутрь страниц 0/1: едут со своей страницей и по
        // кольцу, и по вертикали. tag 100+i — маркер «наша кнопка»: reload
        // страниц сносит subviews, свои кнопки переживаем по нему (теги
        // delete-кнопок строк — индексы строк, до 100 не дорастают)
        for (NSInteger i = 0; i < 2; i++) {
            UIButton *a = [MPClockTheme actionButtonWithTitle:@"Изменить"];
            a.tag = 100 + i;
            [a addTarget:self action:@selector(editTapped:) forControlEvents:UIControlEventTouchUpInside];
            [[_pages objectAtIndex:i] addSubview:a];
            _actA[i] = a;

            UIButton *b = [MPClockTheme actionButtonWithTitle:@"Добавить"];
            b.tag = 100 + i;
            [b addTarget:self action:@selector(addTapped:) forControlEvents:UIControlEventTouchUpInside];
            [[_pages objectAtIndex:i] addSubview:b];
            _actB[i] = b;
        }
        [self layoutActionButtons];

        // состояние таймера (старт/пауза/конец) — пересинхронизация квадрата
        __weak MPClockPivotView *wSelf = self;
        timer.mpOnStateChange = ^(BOOL running) {
            [wSelf syncTimerSquare];
        };
        for (NSInteger i = 0; i < MPPageCount; i++) {
            UIView *pg = [_pages objectAtIndex:i];
            pg.autoresizingMask = UIViewAutoresizingFlexibleHeight;
            [_hScroll addSubview:pg];
        }

        // КОЛЬЦО: старт — страница 0 в центральном слоте, вокруг неё соседи
        _curPage = 0;
        [self layoutPages];
        _vOffset = 0.0f;
        _vAnchor = MPClockCenterSlot * MPClockStride;
        [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];

        // тик мировых часов раз в секунду
        _tickTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(clockTick)
                                            userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_tickTimer forMode:NSRunLoopCommonModes];

        MPLog(@"[Clock] сборка %@", MPClockBuildTag);

        [self reloadData];
        [self layoutActionButtons];
        [self syncChrome];
    }
    return self;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - КОЛЬЦО: раскладка слотов и нормализация

// Разложить 4 страницы по 4 слотам вокруг активной: слот страницы p =
// (p − cur + 2) mod 4 — активная всегда в центральном слоте 2, слева cur−1,
// справа cur+1, на дальнем слоте 0 — cur−2 (≡ cur+2 по кольцу из 4).
// ВАЖНО: setFrame на UIScrollView сбрасывает bounds.origin — вертикальную
// прокрутку страницы сохраняем и возвращаем руками.
- (void)layoutPages {
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIScrollView *pg = (UIScrollView *)[_pages objectAtIndex:i];
        NSInteger slot = MPClockMod4(i - _curPage + MPClockCenterSlot);
        CGPoint co = pg.contentOffset;
        CGRect f = pg.frame;
        f.origin.x = slot * MPClockStride;
        pg.frame = f;
        pg.contentOffset = co;
    }
}

// После остановки скролла: какая страница приехала в слот — та становится
// активной; кластер перекладывается вокруг неё, contentOffset молча
// возвращается в центр (экранно ничего не меняется: страница встала в слот 2
// на том же экранном x). Слот уже центральный — ничего не делаем.
- (void)normalizeAfterStop {
    NSInteger slot = (NSInteger)lroundf((float)(_hScroll.contentOffset.x / MPClockStride));
    if (slot < 0) slot = 0;
    if (slot > MPPageCount - 1) slot = MPPageCount - 1;
    if (slot == MPClockCenterSlot) {
        // прерванный анимированный скролл мог оставить offset между
        // страницами — тихо дощёлкиваем до центра (якорь предустанавливаем:
        // дельта не должна попасть в _vOffset)
        CGFloat target = MPClockCenterSlot * MPClockStride;
        if (fabsf(_hScroll.contentOffset.x - target) > 0.5f) {
            _vAnchor = target;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [_hScroll setContentOffset:CGPointMake(target, 0.0f) animated:NO];
            [CATransaction commit];
        }
        return;
    }

    NSInteger newCur = MPClockMod4(_curPage + slot - MPClockCenterSlot);
    _curPage = newCur;
    // якорь переставляем ДО прыжка — дельта прыжка не попадает в _vOffset
    _vAnchor = MPClockCenterSlot * MPClockStride;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self layoutPages];
    [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];
    [CATransaction commit];

    [self syncChrome];
    MPLog(@"[Clock] кольцо: слот %ld → страница %ld, окно в центр",
          (long)slot, (long)newCur);
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Данные и действия

- (void)reloadData {
    for (UIView *pg in _pages) {
        if ([pg respondsToSelector:@selector(reload)]) [(id)pg performSelector:@selector(reload)];
    }
}

- (void)clockTick {
    // во время живого скролла текст мировых часов не перерисовываем (рывки на
    // A4); после остановки — догоняем время (didEndDecelerating/Animation)
    if (_hScroll.tracking || _hScroll.dragging || _hScroll.decelerating) return;
    for (UIView *pg in _pages) {
        if ([pg respondsToSelector:@selector(tick)]) [(id)pg performSelector:@selector(tick)];
    }
}

- (MPClockBasePage *)page:(NSInteger)i {
    return [_pages objectAtIndex:i];
}

// Слот, в котором стоит страница tag относительно активной (по кольцу):
// +1 → слот 3, −1 → слот 1, ±2 → слот 0 (страница cur−2 живёт там)
- (NSInteger)slotForPage:(NSInteger)tag {
    NSInteger d = MPClockMod4(tag - _curPage);
    if (d == 0) return MPClockCenterSlot;
    if (d == 1) return 3;
    if (d == 3) return 1;
    return 0;   // d == 2: кратчайший путь через cur−2
}

- (void)headerTapped:(UIButton *)sender {
    NSInteger slot = [self slotForPage:sender.tag];
    if (slot == MPClockCenterSlot) return;
    if (_hScroll.decelerating) {
        // iOS 6: setContentOffset:animated: при декелерации молча
        // игнорируется — сперва тихо дощёлкиваем докат до центра
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _vAnchor = MPClockCenterSlot * MPClockStride;
        [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];
        [CATransaction commit];
        [self normalizeAfterStop];
    }
    // системный переход на слот; после приезда didEndScrollingAnimation
    // нормализует окно (и страница tag станет активной)
    [_hScroll setContentOffset:CGPointMake(slot * MPClockStride, 0.0f) animated:YES];
}

- (void)editTapped:(UIButton *)sender {
    // правка городов (стр. 0) или будильников (стр. 1)
    NSInteger pageIdx = sender.tag - 100;   // теги пар — 100+i (см. init)
    MPClockBasePage *pg = [self page:pageIdx];
    pg.editingMode = !pg.isEditingMode;
    [pg setEditingModeAnimated:pg.editingMode];
    [_actA[pageIdx] setTitle:pg.isEditingMode ? @"Готово" : @"Изменить" forState:UIControlStateNormal];
    // «Изменить»↔«Готово» — ширина меняется, фреймы пересчитываем
    [self layoutActionButtons];
}

- (void)addTapped:(UIButton *)sender {
    NSInteger pageIdx = sender.tag - 100;
    MPLog(@"[Clock] добавить (стр. %ld)", (long)pageIdx);
    MPClockEditor *ed = [MPClockEditor sharedEditor];
    if (pageIdx == 0) {
        [ed presentCityPickerInPage:[self page:0]];
    } else {
        [ed presentInPage:[self page:1] alarm:nil];
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Шапка (заголовки и пары)

// Ширины пар и фреймы В КООРДИНАТАХ СТРАНИЦ: кнопки живут внутри страниц
// 0–1 и едут с ними сами; пересчёт нужен при «Изменить»↔«Готово» (ширина
// «Готово» отличается). 16 = MPPageInset страниц
- (void)layoutActionButtons {
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *a = _actA[i];
        UIButton *b = _actB[i];
        if (a == nil || b == nil) continue;
        _actAW[i] = ceilf([a.titleLabel.text sizeWithFont:a.titleLabel.font].width) + 4.0f;
        _actBW[i] = ceilf([b.titleLabel.text sizeWithFont:b.titleLabel.font].width) + 4.0f;
        a.frame = CGRectMake(16.0f, 0.0f, _actAW[i], MPClockActionsH);
        b.frame = CGRectMake(16.0f + _actAW[i] + MPClockActionsGap, 0.0f,
                             _actBW[i], MPClockActionsH);
    }
}

// Шаг слотовой сетки «после заголовка m»: его ширина + зазор (следующий
// заголовок стоит сразу за ним, как строка секций в WP-pivot)
- (CGFloat)headerStep:(NSInteger)m {
    return _headers[m].frame.size.width + MPClockHeaderGap;
}

// Узловая позиция заголовка i при активной странице в k переходах
// (k > 0 — страница ПРОЙДЕНА, заголовок уехал влево; k < 0 — заголовок ещё
// справа, въедет). Узел 0 — активная, заголовок на Lead.
- (CGFloat)headerQ:(NSInteger)i k:(NSInteger)k {
    CGFloat s = 0.0f;
    if (k > 0) {
        for (NSInteger j = 0; j < k; j++) s -= [self headerStep:MPClockMod4(i + j)];
    } else {
        for (NSInteger j = -1; j >= k; j--) s += [self headerStep:MPClockMod4(i + j)];
    }
    return s;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Синхронизация шапки с виртуальным offset

// Слотовая WP-сетка: позиция заголовка i = Lead + лерп между узлами k и k+1,
// где n = mod(p − i + 2, 4) − 2 — кольцевое число переходов до него (−2..2].
// Лента едет с доводкой (скорость = шаг сетки / 320 < скорости контента),
// направления всегда согласно контенту; скачки ветки n случаются только
// за экраном. Пары 0–1 едут со своими заголовками.
- (void)syncChrome {
    CGFloat p = _vOffset / MPClockStride;

    // без неявных CA-анимаций: позиции меняются каждый кадр скролла
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
        f.origin.x = MPClockLead + q;
        _headers[i].frame = f;
    }

    // активный заголовок (по виртуальному прогрессу, по кольцу — смена на
    // СЕРЕДИНЕ свайпа)
    NSInteger active = MPClockMod4((NSInteger)lroundf((float)p));
    for (NSInteger i = 0; i < MPPageCount; i++) {
        [_headers[i] setSelected:(i == active)];
    }

    [self syncTimerSquare];

    [CATransaction commit];
}

// квадратный прогресс таймера: кадр едет с виртуальным offset (1:1 с
// контентом страницы 3), виден только когда Таймер спереди И отсчёт идёт
- (void)syncTimerSquare {
    CGFloat p3x = MPClockWrapC(3.0f * MPClockStride - _vOffset);
    BOOL onScreen = (p3x > -180.0f && p3x < 330.0f);
    BOOL counting = [(MPClockTimerPage *)[self page:3] running];
    _timerSquare.hidden = !onScreen || !counting;
    if (_timerSquare.hidden) return;
    _timerSquare.frame = CGRectMake(p3x + 75.0f, 146.0f, 170.0f, 170.0f);
    _sqProg.strokeEnd = [(MPClockTimerPage *)[self page:3] progress];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // виртуальный offset растёт от реального скролла; прыжки окна
    // (normalizeAfterStop) переставляют якорь заранее — дельта не попадает
    _vOffset += (scrollView.contentOffset.x - _vAnchor);
    _vAnchor = scrollView.contentOffset.x;
    [self syncChrome];
}

// остановки (мягкая без доката / докат / программная анимация) — каждое
// окончание нормализует окно; повторные вызовы безвредны (идемпотентно)
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
#pragma mark - ОТЛАДКА

// ОТЛАДКА: тестовые города для проверки прокрутки
- (void)debugCities:(int)add {
    NSArray *test = @[@"Europe/Paris", @"Europe/Rome", @"Europe/Madrid"];
    for (NSString *zid in test) {
        if (add) [MPClockData addCityWithZoneID:zid];
        else [MPClockData removeCityWithZoneID:zid];
    }
    MPLog(@"[Clock] отладка: тестовые города %@ (%@)",
          add ? @"добавлены" : @"удалены", [MPClockData cities].description);
    [self reloadData];
}

// ОТЛАДКА: программный драйв contentOffset (displayLink): mode 0 — линейный
// (cslow/cburst), 1 — «палец» с переломом и откатом. Живой скролл юзера в это
// время должен быть остановлен, scrollEnabled на время выключаем
- (void)driveToPage:(NSInteger)page duration:(CGFloat)dur mode:(NSInteger)mode shots:(BOOL)shots {
    if (_drvLink != nil) return;
    if (_hScroll.tracking || _hScroll.dragging || _hScroll.decelerating) {
        MPLog(@"[Clock] отладка: отказ — живой скролл ещё идёт");
        return;
    }
    _drvFrom = _hScroll.contentOffset.x;
    _drvTo = [self slotForPage:page] * MPClockStride;
    if (_drvTo == _drvFrom) {
        MPLog(@"[Clock] отладка: страница %ld уже активна", (long)page);
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
    MPLog(@"[Clock] отладка: драйв %.0f → %.0f за %.1f с (mode %ld, снимки %@)",
          _drvFrom, _drvTo, _drvDur, (long)mode, shots ? @"да" : @"нет");
}

- (void)drvTick {
    CGFloat t = (float)((CACurrentMediaTime() - _drvStart) / _drvDur);
    BOOL done = (t >= 1.0f);
    if (done) t = 1.0f;
    // «палец»: 70% пути вперёд, откат на 15% и снова вперёд — неуверенный свайп
    CGFloat k = t;
    if (_drvMode == 1) {
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
        // программный setContentOffset не порождает didEndDecelerating —
        // окно нормализуем сами
        [self normalizeAfterStop];
        if (_drvMode == 1) {
            MPLog(@"[Clock] палец завершён: %@", [_drvLog componentsJoinedByString:@" "]);
        } else if (_drvShots) {
            MPLog(@"[Clock] burst завершён (6 кадров)");
        }
    }
}

// ОТЛАДКА: МЕДЛЕННЫЙ переход на страницу N за dur секунд (cslow)
- (void)debugGoTo:(NSInteger)page duration:(CGFloat)dur {
    [self driveToPage:page duration:dur mode:0 shots:NO];
}

// ОТЛАДКА: переход на соседнюю страницу + 6 снимков окна (cburst)
- (void)debugBurst {
    [self driveToPage:(_curPage + 1) % MPPageCount duration:2.5 mode:0 shots:YES];
}

// ОТЛАДКА: «ПАЛЕЦ» — программный свайп с переломом (cfinger)
- (void)debugFinger {
    [self driveToPage:(_curPage + 1) % MPPageCount duration:3.0 mode:1 shots:NO];
}

// ОТЛАДКА: снимок пивота в файл (renderInContext — модель == экран для
// программного драйва; ВНИМАНИЕ: на пейджере renderInContext слеп к
// contentOffset — страницы верифицировать дампом/глазами)
- (void)mpBurstShot {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0);
    [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Caches/metrophone/burst%ld.png",
                      (long)_drvShot];
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    MPLog(@"[Clock] burst %ld (offset %.0f) → %@", (long)_drvShot, _hScroll.contentOffset.x, path);
    _drvShot++;
}

- (void)debugScrollFront:(float)fraction {
    // фронтальная = активная страница (кластер всегда в центре)
    UIScrollView *pg = [_pages objectAtIndex:_curPage];
    CGFloat maxOff = pg.contentSize.height - pg.bounds.size.height;
    if (maxOff < 1) { MPLog(@"[Clock] отладка: странице %ld нечего скроллить", (long)_curPage); return; }
    CGPoint o = pg.contentOffset;
    o.y = maxOff * fraction;
    pg.contentOffset = o;
    MPLog(@"[Clock] отладка: прокрутка страницы %ld на %.2f (offset %.0f)",
          (long)_curPage, fraction, o.y);
}

- (void)dealloc {
    [_tickTimer invalidate];
    [_drvLink invalidate];
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - C-обёртки для Tweak.xm (отладочные команды)

// ОТЛАДКА: прокрутка фронтальной страницы часов; пивот запоминается в
// installedPivotInView
void MPClockDebugScroll(float fraction) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugScrollFront:fraction];
}

// ОТЛАДКА: медленный переход на страницу N за dur с
void MPClockDebugGoTo(NSInteger page, CGFloat dur) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugGoTo:page duration:dur];
}

// ОТЛАДКА: burst — переход + 6 снимков на телефон
void MPClockDebugBurst(void) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugBurst];
}

// ОТЛАДКА: программный палец
void MPClockDebugFinger(void) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugFinger];
}

// ОТЛАДКА: добавить/убрать три тестовых города (проверка прокрутки)
void MPClockDebugCities(int add) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugCities:add];
}
