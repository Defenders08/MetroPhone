#import "MPCalendarPages.h"
#import "MPCalendarTheme.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <objc/runtime.h>

// Сетки рисуются напрямую (drawRect): на iPhone 4 тысячи кнопок-ячеек
// недопустимы. Тапы различаются по координате: col/row → дата, прямоугольник
// события → контрол. Секции-вьюхи — НЕ скроллвью, setFrame им безвреден
// (грабла «setFrame сбрасывает bounds.origin» касается только страниц).

static CGFloat const MPCalColW = 320.0f / 7.0f;   // колонка сетки 7 дней
static NSInteger const MPCalMonthRadius = 12;      // месяцев вокруг якоря
static NSInteger const MPCalWeekRadius = 12;       // недель вокруг якоря
static NSInteger const MPCalDayRadius = 30;        // суток вокруг якоря

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Базовая страница

@implementation MPCalendarBasePage
@synthesize anchorDate = _anchorDate, onSelectDate = _onSelectDate, onSelectEvent = _onSelectEvent;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.showsVerticalScrollIndicator = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.alwaysBounceVertical = YES;
    }
    return self;
}

- (void)reload {}
- (void)tick {}
- (void)gotoDayStart:(NSDate *)dayStart animated:(BOOL)animated {}
- (void)scrollToTodayAnimated:(BOOL)animated {}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - СТРАНИЦА «МЕСЯЦ» — секция-месяц (drawRect + тап по координате)

@interface MPCalendarMonthSection : UIView {
    NSDate *_firstGridDay;             // первый день сетки (может быть прошлым месяцем)
    NSDate *_monthFirst;
    NSDate *_todayStart;
    NSMutableDictionary *_dotsByDay;   // dayStart → NSArray<UIColor*> (макс 2)
}
@property (nonatomic, copy) void (^onSelectDate)(NSDate *day);
- (id)initWithFrame:(CGRect)frame monthFirst:(NSDate *)monthFirst today:(NSDate *)today;
@end

@implementation MPCalendarMonthSection

- (id)initWithFrame:(CGRect)frame monthFirst:(NSDate *)monthFirst today:(NSDate *)today {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _monthFirst = monthFirst;
        _todayStart = today;
        MPCalendarData *d = [MPCalendarData sharedData];
        NSInteger lead = ([d.cal components:NSWeekdayCalendarUnit fromDate:monthFirst].weekday
                          - d.firstWeekday + 7) % 7;
        _firstGridDay = [d dayStartByAddingDays:-lead toDayStart:monthFirst];
        _dotsByDay = [[NSMutableDictionary alloc] init];
        // точки событий: не больше двух цветов календарей на день
        for (NSInteger i = 0; i < 42; i++) {
            NSDate *day = [d dayStartByAddingDays:i toDayStart:_firstGridDay];
            NSArray *evs = [d eventsForDayStart:day];
            if (evs.count == 0) continue;
            NSMutableArray *cols = [NSMutableArray array];
            for (MPCalendarEvent *ev in evs) {
                if (cols.count >= 2) break;
                if (![cols containsObject:ev.color]) [cols addObject:ev.color];
            }
            [_dotsByDay setObject:cols forKey:day];
        }
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(tapped:)];
        [self addGestureRecognizer:t];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    MPCalendarData *d = [MPCalendarData sharedData];
    NSDateComponents *mc = [d.cal components:NSYearCalendarUnit | NSMonthCalendarUnit
                                     fromDate:_monthFirst];
    // «октябрь» light 24 белым + год regular 13 справа (год — по ЦЕНТРУ
    // заголовка: раньше y=18 уводил его ниже базовой линии)
    NSString *mname = [d standaloneMonthName:mc.month];
    UIFont *mf = [MPMetroStyle lightFont:24.0f];
    [[UIColor whiteColor] setFill];
    [mname drawAtPoint:CGPointMake(MPCalLead, 8.0f) withFont:mf];
    NSString *year = [NSString stringWithFormat:@"%ld", (long)mc.year];
    UIFont *yf = [MPMetroStyle regularFont:13.0f];
    CGSize ys = [year sizeWithFont:yf];
    [[MPCalendarTheme mutedColor] setFill];
    [year drawAtPoint:CGPointMake(320.0f - MPCalLead - ys.width, 12.0f) withFont:yf];

    // строка дней недели в порядке локали (пн … вс)
    CGFloat wdY = MPCalMonthTitleH - 6.0f;
    UIFont *wf = [MPMetroStyle regularFont:13.0f];
    [[MPCalendarTheme mutedColor] setFill];
    for (NSInteger i = 0; i < 7; i++) {
        NSDate *day = [d dayStartByAddingDays:i toDayStart:_firstGridDay];
        NSInteger wd = [d.cal components:NSWeekdayCalendarUnit fromDate:day].weekday;
        NSString *s = [d shortWeekdayName:wd];
        CGSize sz = [s sizeWithFont:wf];
        [s drawAtPoint:CGPointMake(i * MPCalColW + (MPCalColW - sz.width) / 2.0f, wdY) withFont:wf];
    }

    // сетка 7×6: числа light 22, соседние месяцы faint, сегодня — акцентная
    // плитка 36×36 с белым числом, под числом до двух точек 4×4
    CGFloat gridY = MPCalMonthTitleH + MPCalWeekdaysH;
    UIFont *nf = [MPMetroStyle lightFont:22.0f];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    for (NSInteger idx = 0; idx < 42; idx++) {
        NSDate *day = [d dayStartByAddingDays:idx toDayStart:_firstGridDay];
        NSDateComponents *c = [d.cal components:NSDayCalendarUnit | NSMonthCalendarUnit
                                         fromDate:day];
        NSInteger col = idx % 7, row = idx / 7;
        CGFloat cx = col * MPCalColW + MPCalColW / 2.0f;
        CGFloat cy = gridY + row * MPCalMonthCellH + 6.0f;
        NSString *num = [NSString stringWithFormat:@"%ld", (long)c.day];
        CGSize ns = [num sizeWithFont:nf];
        BOOL isToday = [day isEqualToDate:_todayStart];
        if (isToday) {
            [[MPMetroStyle accentColor] setFill];
            CGContextFillRect(ctx, CGRectMake(cx - 18.0f, cy - 4.0f, 36.0f, 36.0f));
            [[UIColor whiteColor] setFill];
            [num drawAtPoint:CGPointMake(cx - ns.width / 2.0f, cy + 3.0f) withFont:nf];
        } else {
            BOOL sameMonth = (c.month == mc.month);
            [[UIColor colorWithWhite:1.0f alpha:sameMonth ? 1.0f : 0.26f] setFill];
            [num drawAtPoint:CGPointMake(cx - ns.width / 2.0f, cy) withFont:nf];
        }
        if (isToday) continue;
        NSArray *dots = [_dotsByDay objectForKey:day];
        if (dots.count > 0) {
            CGFloat dw = dots.count * 8.0f - 4.0f;
            for (NSUInteger k = 0; k < dots.count; k++) {
                [(UIColor *)[dots objectAtIndex:k] setFill];
                CGContextFillRect(ctx, CGRectMake(cx - dw / 2.0f + k * 8.0f,
                                                  cy + 30.0f, 4.0f, 4.0f));
            }
        }
    }
}

- (void)tapped:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    CGFloat gridY = MPCalMonthTitleH + MPCalWeekdaysH;
    if (p.y < gridY) return;
    NSInteger row = (NSInteger)((p.y - gridY) / MPCalMonthCellH);
    NSInteger col = (NSInteger)(p.x / MPCalColW);
    if (row < 0 || row > 5 || col < 0 || col > 6) return;
    NSDate *day = [[MPCalendarData sharedData] dayStartByAddingDays:row * 7 + col
                                                           toDayStart:_firstGridDay];
    if (self.onSelectDate) self.onSelectDate(day);
}

@end

@implementation MPCalendarMonthPage {
    NSArray *_sections;      // секции в порядке месяцев; старт = якорь − radius
    NSDate *_firstSectionMonth;
    BOOL _built;
}

- (void)reload {
    CGPoint saved = self.contentOffset;
    for (UIView *v in [self.subviews copy]) [v removeFromSuperview];
    MPCalendarData *d = [MPCalendarData sharedData];
    NSDate *today = [d todayStart];
    NSDate *anchorMonth = [d firstDayOfMonthForDayStart:self.anchorDate ?: today];
    NSDateComponents *jump = [[NSDateComponents alloc] init];
    jump.month = -MPCalMonthRadius;
    _firstSectionMonth = [d.cal dateByAddingComponents:jump toDate:anchorMonth options:0];
    NSDateComponents *one = [[NSDateComponents alloc] init];
    one.month = 1;
    // один фетч на всю ленту (25 месяцев) — вместо серии промахов на секцию;
    // старт на неделю раньше: сетка первой секции начинается с
    // firstGridDay (до 6 дней до начала месяца)
    NSDateComponents *fwd = [[NSDateComponents alloc] init];
    fwd.month = MPCalMonthRadius + 1;
    [d ensureEventsFrom:[d dayStartByAddingDays:-7 toDayStart:_firstSectionMonth]
                     to:[d.cal dateByAddingComponents:fwd toDate:anchorMonth options:0]];
    CGFloat y = 0.0f;
    NSMutableArray *secs = [NSMutableArray array];
    NSDate *m = _firstSectionMonth;
    for (NSInteger i = 0; i < MPCalMonthRadius * 2 + 1; i++) {
        // хвостовой воздух (MPCalMonthTail) — заголовок следующего месяца
        // не прижат к сетке предыдущего
        CGFloat h = MPCalMonthTitleH + MPCalWeekdaysH + 6.0f * MPCalMonthCellH + MPCalMonthTail;
        MPCalendarMonthSection *s = [[MPCalendarMonthSection alloc]
                                     initWithFrame:CGRectMake(0.0f, y, 320.0f, h)
                                        monthFirst:m today:today];
        __weak MPCalendarMonthPage *wSelf = self;
        s.onSelectDate = ^(NSDate *day) { if (wSelf.onSelectDate) wSelf.onSelectDate(day); };
        [self addSubview:s];
        [secs addObject:s];
        y += h;
        m = [d.cal dateByAddingComponents:one toDate:m options:0];
    }
    _sections = secs;
    self.contentSize = CGSizeMake(320.0f, y);
    self.contentOffset = saved;
    if (!_built) {
        _built = YES;
        [self scrollToTodayAnimated:NO];
    }
    // ленивое рисование iOS 6: секции, созданные вне окна/вне экрана, могут
    // остаться пустыми — пинаем каждую явно
    for (UIView *s in _sections) [s setNeedsDisplay];
}

- (void)gotoDayStart:(NSDate *)dayStart animated:(BOOL)animated {
    // секция i покрывает месяц _firstSectionMonth + i; ищем месяц даты
    MPCalendarData *d = [MPCalendarData sharedData];
    for (NSUInteger i = 0; i < _sections.count; i++) {
        NSDateComponents *jump = [[NSDateComponents alloc] init];
        jump.month = i;
        NSDate *m = [d.cal dateByAddingComponents:jump toDate:_firstSectionMonth options:0];
        if ([dayStart compare:m] == NSOrderedAscending) continue;
        NSDateComponents *one = [[NSDateComponents alloc] init];
        one.month = 1;
        NSDate *next = [d.cal dateByAddingComponents:one toDate:m options:0];
        if ([dayStart compare:next] == NSOrderedAscending) {
            UIView *sec = [_sections objectAtIndex:i];
            [self setContentOffset:CGPointMake(0.0f, sec.frame.origin.y) animated:animated];
            return;
        }
    }
}

- (void)scrollToTodayAnimated:(BOOL)animated {
    [self gotoDayStart:[[MPCalendarData sharedData] todayStart] animated:animated];
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - СТРАНИЦА «НЕДЕЛЯ» — секция-неделя (drawRect, полоски событий)

@interface MPCalendarWeekSection : UIView {
    NSDate *_weekFirst;
    NSArray *_days;                // 7 × dayStart
    NSDate *_todayStart;
    NSArray *_timed;               // расчитанные прямоугольники событий
    NSArray *_allDay;              // аллдей: колонки start/end + цвет
    NSInteger _allDayRows;
}
@property (nonatomic, copy) void (^onSelectDate)(NSDate *day);
- (id)initWithFrame:(CGRect)frame weekFirst:(NSDate *)weekFirst today:(NSDate *)today;
- (BOOL)containsToday;
- (void)refreshNowLine;
@end

// рассчитанный прямоугольник события в сетке недели
@interface MPCalWeekBlock : NSObject
@property CGFloat x, y, w, h;
@property (nonatomic, assign) NSInteger col;   // исходная колонка дня (до сдвигов lane)
@property (nonatomic, retain) UIColor *color;
@property (nonatomic, retain) MPCalendarEvent *event;
@end

@implementation MPCalWeekBlock
@end

@implementation MPCalendarWeekSection

- (id)initWithFrame:(CGRect)frame weekFirst:(NSDate *)weekFirst today:(NSDate *)today {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _weekFirst = weekFirst;
        _todayStart = today;
        MPCalendarData *d = [MPCalendarData sharedData];
        NSMutableArray *days = [NSMutableArray array];
        for (NSInteger i = 0; i < 7; i++) [days addObject:[d dayStartByAddingDays:i toDayStart:weekFirst]];
        _days = days;

        // события недели: разворачиваем кэш по дням, уникализируем по идентификатору
        NSDate *weekEnd = [d dayStartByAddingDays:7 toDayStart:weekFirst];
        NSMutableArray *all = [NSMutableArray array];
        NSMutableSet *seen = [[NSMutableSet alloc] init];
        for (NSDate *day in days) {
            for (MPCalendarEvent *ev in [d eventsForDayStart:day]) {
                if ([seen containsObject:ev.eventIdentifier ?: @""]) continue;
                [seen addObject:ev.eventIdentifier ?: @""];
                [all addObject:ev];
            }
        }
        // прямоугольники: clamp в границы недели, колейны по дням начала/конца
        NSMutableArray *blocks = [NSMutableArray array];
        NSMutableArray *allDayList = [NSMutableArray array];
        CGFloat gridX = 34.0f;
        CGFloat colW = (320.0f - gridX) / 7.0f;
        for (MPCalendarEvent *ev in all) {
            NSDate *s = [ev.start laterDate:weekFirst];
            NSDate *e = [ev.end earlierDate:weekEnd];
            if (ev.allDay) {
                // дни начала/конца полосы ищем сравнением суток
                NSInteger sc = 0, ec = 6;
                for (NSInteger i = 0; i < 7; i++) {
                    NSDate *day = [days objectAtIndex:i];
                    NSDate *dayNext = [d dayStartByAddingDays:1 toDayStart:day];
                    if ([ev.start compare:dayNext] == NSOrderedAscending && [ev.end compare:day] == NSOrderedDescending) {
                        if (sc == 0 && [ev.start compare:day] != NSOrderedAscending) sc = i;
                        if (ec == 6 && [ev.end compare:dayNext] != NSOrderedDescending) ec = i;
                    }
                }
                NSDictionary *info = @{@"sc": @(sc), @"ec": @(ec), @"color": ev.color ?: [UIColor grayColor]};
                [allDayList addObject:info];
                continue;
            }
            if ([e compare:s] != NSOrderedDescending) e = [s dateByAddingTimeInterval:1800.0];
            NSInteger col = 0;
            for (NSInteger i = 6; i >= 0; i--) {
                if ([s compare:[days objectAtIndex:i]] != NSOrderedAscending) { col = i; break; }
            }
            MPCalWeekBlock *b = [[MPCalWeekBlock alloc] init];
            b.col = col;   // фиксируем ДО сдвигов lane — иначе соседи по колонке теряются
            NSTimeInterval t0 = [s timeIntervalSinceDate:weekFirst];
            NSTimeInterval dur = [e timeIntervalSinceDate:s];
            b.x = gridX + col * colW + 2.0f;
            b.y = (CGFloat)(t0 / 3600.0) * MPCalWeekHourH;
            b.w = colW - 4.0f;
            b.h = (CGFloat)MAX(6.0, dur / 3600.0 * MPCalWeekHourH - 2.0);
            b.color = ev.color ?: [UIColor grayColor];
            b.event = ev;
            [blocks addObject:b];
        }
        // колейны перекрытия: жадно по start; ширина делится на максимум
        // одновременных в колонке
        [blocks sortUsingComparator:^NSComparisonResult(id a, id b) {
            MPCalWeekBlock *ba = (MPCalWeekBlock *)a, *bb = (MPCalWeekBlock *)b;
            return (ba.y < bb.y) ? NSOrderedAscending
                 : (ba.y > bb.y) ? NSOrderedDescending : NSOrderedSame;
        }];
        for (MPCalWeekBlock *b in blocks) {
            NSInteger lane = 0;
            NSMutableArray *peers = [NSMutableArray array];
            for (MPCalWeekBlock *o in blocks) {
                if (o == b) continue;
                if (o.col != b.col) continue;                   // та же колонка дня
                if (o.y < b.y + b.h && b.y < o.y + o.h) [peers addObject:o];
            }
            // lane = количество peers, уже размещённых слева от нас (по y)
            for (MPCalWeekBlock *o in peers) {
                if (o.y <= b.y) lane++;
            }
            CGFloat n = peers.count + 1.0f;
            b.w = (b.w + 2.0f) / n - 2.0f;
            b.x += lane * (b.w + 2.0f);
        }
        _timed = blocks;
        _allDay = allDayList;
        _allDayRows = allDayList.count;
        // фрейм зависел от числа аллдей-полос — уточняем
        CGRect f = self.frame;
        f.size.width = 320.0f;
        f.size.height = [MPCalendarWeekSection heightForAllDayRows:_allDayRows];
        self.frame = f;

        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(tapped:)];
        [self addGestureRecognizer:t];
    }
    return self;
}

+ (CGFloat)heightForAllDayRows:(NSInteger)rows {
    return MPCalWeekDateH + rows * 22.0f + 24.0f * MPCalWeekHourH;
}

- (CGFloat)gridY {
    return MPCalWeekDateH + _allDayRows * 22.0f;
}

- (BOOL)containsToday {
    return [_days containsObject:_todayStart];
}

- (void)refreshNowLine {
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    MPCalendarData *d = [MPCalendarData sharedData];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat gridX = 34.0f;
    CGFloat colW = (320.0f - gridX) / 7.0f;

    // строка дат: «пн» + число; сегодня — акцентная плитка 30×30
    UIFont *wf = [MPMetroStyle regularFont:11.0f];
    UIFont *nf = [MPMetroStyle lightFont:20.0f];
    for (NSInteger i = 0; i < 7; i++) {
        NSDate *day = [_days objectAtIndex:i];
        NSDateComponents *c = [d.cal components:NSDayCalendarUnit | NSWeekdayCalendarUnit
                                        fromDate:day];
        NSString *wd = [d shortWeekdayName:c.weekday];
        CGSize ws = [wd sizeWithFont:wf];
        [[MPCalendarTheme mutedColor] setFill];
        [wd drawAtPoint:CGPointMake(gridX + i * colW + (colW - ws.width) / 2.0f, 2.0f) withFont:wf];
        BOOL isToday = [day isEqualToDate:_todayStart];
        NSString *num = [NSString stringWithFormat:@"%ld", (long)c.day];
        CGSize ns = [num sizeWithFont:nf];
        if (isToday) {
            [[MPMetroStyle accentColor] setFill];
            CGContextFillRect(ctx, CGRectMake(gridX + i * colW + (colW - 30.0f) / 2.0f, 14.0f, 30.0f, 30.0f));
        }
        [[UIColor whiteColor] setFill];
        [num drawAtPoint:CGPointMake(gridX + i * colW + (colW - ns.width) / 2.0f, 19.0f) withFont:nf];
    }

    // аллдей-полосы: по строке на событие (без упаковки — их обычно мало;
    // текст не рисуем, полосы узкие)
    for (NSUInteger k = 0; k < _allDay.count; k++) {
        NSDictionary *info = [_allDay objectAtIndex:k];
        NSInteger sc = [info[@"sc"] integerValue];
        NSInteger ec = [info[@"ec"] integerValue];
        UIColor *color = info[@"color"];
        CGFloat y = MPCalWeekDateH + k * 22.0f + 4.0f;
        [color setFill];
        CGContextFillRect(ctx, CGRectMake(gridX + sc * colW + 2.0f, y,
                                          (ec - sc + 1) * colW - 4.0f, 16.0f));
    }

    // метки часов каждые 3 часа (right-aligned к сетке)
    UIFont *hf = [MPMetroStyle regularFont:12.0f];
    [[MPCalendarTheme faintColor] setFill];
    for (NSInteger h = 0; h < 24; h += 3) {
        NSString *s = [NSString stringWithFormat:@"%02ld", (long)h];
        CGSize sz = [s sizeWithFont:hf];
        [s drawAtPoint:CGPointMake(gridX - 6.0f - sz.width, self.gridY + h * MPCalWeekHourH - 15.0f) withFont:hf];
    }

    // события — плоские полоски цвета календаря (текст не влезает: 40 pt)
    for (MPCalWeekBlock *b in _timed) {
        [b.color setFill];
        CGContextFillRect(ctx, CGRectMake(b.x, self.gridY + b.y, b.w, b.h));
    }

    // линия «сейчас»
    if ([self containsToday]) {
        NSDate *now = [NSDate date];
        NSTimeInterval t = [now timeIntervalSinceDate:_weekFirst];
        if (t >= 0.0 && t < 7.0 * 86400.0) {
            CGFloat y = self.gridY + (CGFloat)(t / 3600.0) * MPCalWeekHourH;
            [[MPMetroStyle accentColor] setFill];
            CGContextFillRect(ctx, CGRectMake(gridX - 4.0f, y, 320.0f - gridX + 4.0f, 2.0f));
            CGContextFillRect(ctx, CGRectMake(gridX - 10.0f, y - 2.0f, 6.0f, 6.0f));
        }
    }
}

- (void)tapped:(UITapGestureRecognizer *)g {
    CGPoint p = [g locationInView:self];
    CGFloat gridX = 34.0f;
    CGFloat colW = (320.0f - gridX) / 7.0f;
    NSInteger col = (NSInteger)((p.x - gridX) / colW);
    if (p.x < gridX) col = 0;
    if (col < 0) col = 0;
    if (col > 6) col = 6;
    if (self.onSelectDate) self.onSelectDate([_days objectAtIndex:col]);
}

@end

@implementation MPCalendarWeekPage {
    NSArray *_sections;
    NSDate *_firstSectionWeek;
    NSInteger _lastMinute;
    BOOL _built;
}

- (void)reload {
    CGPoint saved = self.contentOffset;
    for (UIView *v in [self.subviews copy]) [v removeFromSuperview];
    MPCalendarData *d = [MPCalendarData sharedData];
    NSDate *today = [d todayStart];
    NSDate *anchor = [d firstDayOfWeekForDayStart:self.anchorDate ?: today];
    _firstSectionWeek = [d dayStartByAddingDays:-MPCalWeekRadius * 7 toDayStart:anchor];
    // один фетч на всю ленту (25 недель) — вместо серии промахов на секцию
    [d ensureEventsFrom:_firstSectionWeek
                     to:[d dayStartByAddingDays:(MPCalWeekRadius + 1) * 7 toDayStart:anchor]];
    CGFloat y = 0.0f;
    NSMutableArray *secs = [NSMutableArray array];
    for (NSInteger i = 0; i < MPCalWeekRadius * 2 + 1; i++) {
        NSDate *wf = [d dayStartByAddingDays:i * 7 toDayStart:_firstSectionWeek];
        MPCalendarWeekSection *s = [[MPCalendarWeekSection alloc]
                                    initWithFrame:CGRectMake(0.0f, 0.0f, 320.0f, 100.0f)
                                                  weekFirst:wf today:today];
        CGRect f = s.frame;
        f.origin = CGPointMake(0.0f, y);
        s.frame = f;
        __weak MPCalendarWeekPage *wSelf = self;
        s.onSelectDate = ^(NSDate *day) { if (wSelf.onSelectDate) wSelf.onSelectDate(day); };
        [self addSubview:s];
        [secs addObject:s];
        y += s.frame.size.height;
    }
    _sections = secs;
    self.contentSize = CGSizeMake(320.0f, y);
    self.contentOffset = saved;
    if (!_built) {
        _built = YES;
        [self scrollToTodayAnimated:NO];
    }
    for (UIView *s in _sections) [s setNeedsDisplay];
}

- (void)tick {
    // перерисовка линии «сейчас» не чаще раза в минуту и только видимых секций
    NSDateComponents *c = [[MPCalendarData sharedData].cal components:NSMinuteCalendarUnit
                                                              fromDate:[NSDate date]];
    if (c.minute == _lastMinute) return;
    _lastMinute = c.minute;
    CGRect vis = self.bounds;
    vis.origin = self.contentOffset;
    for (MPCalendarWeekSection *s in _sections) {
        if (CGRectIntersectsRect(s.frame, vis) && [s containsToday]) [s refreshNowLine];
    }
}

- (void)gotoDayStart:(NSDate *)dayStart animated:(BOOL)animated {
    for (NSUInteger i = 0; i < _sections.count; i++) {
        UIView *sec = [_sections objectAtIndex:i];
        NSDate *wf = [[MPCalendarData sharedData] dayStartByAddingDays:(NSInteger)i * 7
                                                              toDayStart:_firstSectionWeek];
        NSDate *we = [[MPCalendarData sharedData] dayStartByAddingDays:7 toDayStart:wf];
        if ([dayStart compare:wf] != NSOrderedAscending &&
            [dayStart compare:we] == NSOrderedAscending) {
            [self setContentOffset:CGPointMake(0.0f, sec.frame.origin.y) animated:animated];
            return;
        }
    }
}

- (void)scrollToTodayAnimated:(BOOL)animated {
    [self gotoDayStart:[[MPCalendarData sharedData] todayStart] animated:animated];
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - СТРАНИЦА «ДЕНЬ» — заголовок даты + лента 24 часов

// сетка-фон ленты: метки часов (drawRect); события — UIControl поверх
@interface MPCalDayGrid : UIView
@end

@implementation MPCalDayGrid

- (void)drawRect:(CGRect)rect {
    UIFont *f = [MPMetroStyle regularFont:12.0f];
    [[MPCalendarTheme faintColor] setFill];
    for (NSInteger h = 0; h < 24; h++) {
        NSString *s = [NSString stringWithFormat:@"%02ld:00", (long)h];
        CGSize sz = [s sizeWithFont:f];
        [s drawAtPoint:CGPointMake(MPCalDayLeft - 8.0f - sz.width,
                                   h * MPCalDayHourH - 15.0f) withFont:f];
    }
}

@end

@interface MPCalendarDaySection : UIView {
    NSDate *_dayStart;
    NSDate *_todayStart;
    UIView *_nowLine;
    UIView *_nowDot;
}
@property (nonatomic, assign) NSInteger allDayCount;
@property (nonatomic, copy) void (^onSelectEvent)(MPCalendarEvent *event);
- (id)initWithFrame:(CGRect)frame dayStart:(NSDate *)dayStart today:(NSDate *)today;
- (BOOL)isToday;
- (void)updateNowLine;
+ (CGFloat)heightForAllDayCount:(NSInteger)n;
- (CGFloat)lentaY;
@end

@implementation MPCalendarDaySection

+ (CGFloat)heightForAllDayCount:(NSInteger)n {
    return MPCalDayHeaderH + n * 32.0f + 24.0f * MPCalDayHourH + 12.0f;
}

- (CGFloat)lentaY {
    return MPCalDayHeaderH + self.allDayCount * 32.0f;
}

- (id)initWithFrame:(CGRect)frame dayStart:(NSDate *)dayStart today:(NSDate *)today {
    self = [super initWithFrame:frame];
    if (self) {
        MPCalendarData *d = [MPCalendarData sharedData];
        _dayStart = dayStart;
        _todayStart = today;
        NSArray *evs = [d eventsForDayStart:dayStart];
        NSMutableArray *timed = [NSMutableArray array];
        NSMutableArray *allDay = [NSMutableArray array];
        for (MPCalendarEvent *ev in evs) (ev.allDay ? [allDay addObject:ev] : [timed addObject:ev]);
        self.allDayCount = allDay.count;

        // заголовок: число thin 60 + «среда» light 24 + «октябрь» regular 13
        NSDateComponents *c = [d.cal components:NSDayCalendarUnit | NSMonthCalendarUnit
                                            | NSWeekdayCalendarUnit fromDate:dayStart];
        NSString *num = [NSString stringWithFormat:@"%ld", (long)c.day];
        UIFont *nf = [MPMetroStyle thinFont:60.0f];
        UILabel *numL = [[UILabel alloc] initWithFrame:CGRectMake(MPCalLead, 4.0f, 90.0f, 68.0f)];
        numL.font = nf;
        numL.textColor = [UIColor whiteColor];
        numL.backgroundColor = [UIColor clearColor];
        numL.text = num;
        [self addSubview:numL];
        CGFloat x2 = MPCalLead + ceilf([num sizeWithFont:nf].width) + 14.0f;
        UILabel *wdL = [[UILabel alloc] initWithFrame:CGRectMake(x2, 12.0f, 200.0f, 30.0f)];
        wdL.font = [MPMetroStyle lightFont:24.0f];
        wdL.textColor = [UIColor whiteColor];
        wdL.backgroundColor = [UIColor clearColor];
        wdL.text = [d weekdayName:c.weekday];
        [self addSubview:wdL];
        UILabel *mL = [[UILabel alloc] initWithFrame:CGRectMake(x2, 46.0f, 200.0f, 20.0f)];
        mL.font = [MPMetroStyle regularFont:13.0f];
        mL.textColor = [MPCalendarTheme mutedColor];
        mL.backgroundColor = [UIColor clearColor];
        mL.text = [d standaloneMonthName:c.month];
        [self addSubview:mL];

        // аллдей — плоские полосы во всю ширину
        for (NSUInteger k = 0; k < allDay.count; k++) {
            MPCalendarEvent *ev = [allDay objectAtIndex:k];
            UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(0.0f,
                    MPCalDayHeaderH + k * 32.0f, 320.0f, 32.0f)];
            row.backgroundColor = ev.color ?: [UIColor grayColor];
            UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(10.0f, 6.0f, 230.0f, 20.0f)];
            t.font = [MPMetroStyle regularFont:15.0f];
            t.textColor = [UIColor whiteColor];
            t.backgroundColor = [UIColor clearColor];
            t.text = ev.title.length ? ev.title : @"(без названия)";
            [row addSubview:t];
            UILabel *ad = [[UILabel alloc] initWithFrame:CGRectMake(240.0f, 6.0f, 70.0f, 20.0f)];
            ad.font = [MPMetroStyle regularFont:12.0f];
            ad.textColor = [UIColor colorWithWhite:1.0f alpha:0.8f];
            ad.backgroundColor = [UIColor clearColor];
            ad.textAlignment = NSTextAlignmentRight;
            ad.text = @"весь день";
            [row addSubview:ad];
            [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(row, @selector(rowTapped:), ev, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self addSubview:row];
        }

        // сетка-фон
        CGFloat lentaY = self.lentaY;
        MPCalDayGrid *grid = [[MPCalDayGrid alloc] initWithFrame:CGRectMake(0.0f, lentaY,
                                                                             320.0f,
                                                                             24.0f * MPCalDayHourH)];
        [self addSubview:grid];

        // события — плоские блоки цвета календаря; наложения → 2 колонки
        [timed sortUsingComparator:^NSComparisonResult(id a, id b) {
            return [((MPCalendarEvent *)a).start compare:((MPCalendarEvent *)b).start];
        }];
        for (NSUInteger k = 0; k < timed.count; k++) {
            MPCalendarEvent *ev = [timed objectAtIndex:k];
            // lane: сколько предыдущих событий пересекают нас по времени
            NSUInteger lane = 0, overlap = 0;
            for (NSUInteger j = 0; j < timed.count; j++) {
                if (j == k) continue;
                MPCalendarEvent *o = [timed objectAtIndex:j];
                BOOL inter = [o.start compare:ev.end] == NSOrderedAscending &&
                             [ev.start compare:o.end] == NSOrderedAscending;
                if (!inter) continue;
                overlap++;
                if (j < k) lane++;
            }
            NSUInteger lanes = overlap + 1;
            if (lanes > 2) lanes = 2;
            if (lane > 1) lane = 1;
            NSTimeInterval s = [ev.start timeIntervalSinceDate:dayStart];
            NSTimeInterval dur = [ev.end timeIntervalSinceDate:ev.start];
            CGFloat blockW = (304.0f - MPCalDayLeft) / lanes - 4.0f;
            UIControl *blk = [[UIControl alloc] initWithFrame:CGRectMake(
                    MPCalDayLeft + lane * (blockW + 4.0f),
                    lentaY + (CGFloat)MAX(0.0, s / 3600.0) * MPCalDayHourH + 1.0f,
                    blockW,
                    (CGFloat)MAX(32.0, dur / 3600.0 * MPCalDayHourH - 2.0))];
            blk.backgroundColor = ev.color ?: [UIColor grayColor];
            UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(8.0f, 4.0f, blk.bounds.size.width - 16.0f, 22.0f)];
            t.font = [MPMetroStyle lightFont:15.0f];
            t.textColor = [UIColor whiteColor];
            t.backgroundColor = [UIColor clearColor];
            t.text = ev.title.length ? ev.title : @"(без названия)";
            [blk addSubview:t];
            if (blk.bounds.size.height >= 44.0f) {
                UILabel *tm = [[UILabel alloc] initWithFrame:CGRectMake(8.0f, 26.0f, blk.bounds.size.width - 16.0f, 18.0f)];
                tm.font = [MPMetroStyle regularFont:12.0f];
                tm.textColor = [UIColor colorWithWhite:1.0f alpha:0.85f];
                tm.backgroundColor = [UIColor clearColor];
                tm.text = [NSString stringWithFormat:@"%@ – %@", [d timeStringFromDate:ev.start],
                                                       [d timeStringFromDate:ev.end]];
                [blk addSubview:tm];
            }
            [blk addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(blk, @selector(rowTapped:), ev, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self addSubview:blk];
        }

        // линия «сейчас» — акцентная, живёт поверх блоков
        _nowLine = [[UIView alloc] initWithFrame:CGRectZero];
        _nowLine.backgroundColor = [MPMetroStyle accentColor];
        _nowLine.userInteractionEnabled = NO;
        [self addSubview:_nowLine];
        _nowDot = [[UIView alloc] initWithFrame:CGRectMake(MPCalDayLeft - 12.0f, 0.0f, 6.0f, 6.0f)];
        _nowDot.backgroundColor = [MPMetroStyle accentColor];
        _nowDot.userInteractionEnabled = NO;
        [self addSubview:_nowDot];
        [self updateNowLine];
    }
    return self;
}

- (void)rowTapped:(UIControl *)sender {
    MPCalendarEvent *ev = objc_getAssociatedObject(sender, @selector(rowTapped:));
    if (ev != nil && self.onSelectEvent) self.onSelectEvent(ev);
}

- (BOOL)isToday {
    return [_dayStart isEqualToDate:_todayStart];
}

- (void)updateNowLine {
    BOOL today = [self isToday];
    _nowLine.hidden = !today;
    _nowDot.hidden = !today;
    if (!today) return;
    NSTimeInterval t = [[NSDate date] timeIntervalSinceDate:_dayStart];
    if (t < 0.0) t = 0.0;
    if (t > 24.0 * 3600.0) t = 24.0 * 3600.0;
    CGFloat y = self.lentaY + (CGFloat)(t / 3600.0) * MPCalDayHourH;
    _nowLine.frame = CGRectMake(MPCalDayLeft - 8.0f, y, 320.0f - MPCalDayLeft + 8.0f, 2.0f);
    CGRect df = _nowDot.frame;
    df.origin.y = y - 2.0f;
    _nowDot.frame = df;
}

@end

@implementation MPCalendarDayPage {
    NSArray *_sections;         // параллельно _sectionDays
    NSArray *_sectionDays;
    BOOL _built;
}

- (void)reload {
    CGPoint saved = self.contentOffset;
    for (UIView *v in [self.subviews copy]) [v removeFromSuperview];
    MPCalendarData *d = [MPCalendarData sharedData];
    NSDate *today = [d todayStart];
    NSDate *first = [d dayStartByAddingDays:-MPCalDayRadius toDayStart:today];
    // один фетч на всю ленту (61 сутки) — вместо серии промахов на секцию
    [d ensureEventsFrom:first to:[d dayStartByAddingDays:MPCalDayRadius + 1 toDayStart:today]];
    NSMutableArray *secs = [NSMutableArray array];
    NSMutableArray *daysArr = [NSMutableArray array];
    CGFloat y = 0.0f;
    for (NSInteger i = 0; i < MPCalDayRadius * 2 + 1; i++) {
        NSDate *day = [d dayStartByAddingDays:i toDayStart:first];
        NSArray *evs = [d eventsForDayStart:day];
        NSInteger allDay = 0;
        for (MPCalendarEvent *ev in evs) if (ev.allDay) allDay++;
        CGFloat h = [MPCalendarDaySection heightForAllDayCount:allDay];
        MPCalendarDaySection *s = [[MPCalendarDaySection alloc]
                                   initWithFrame:CGRectMake(0.0f, y, 320.0f, h)
                                        dayStart:day today:today];
        __weak MPCalendarDayPage *wSelf = self;
        s.onSelectEvent = ^(MPCalendarEvent *ev) { if (wSelf.onSelectEvent) wSelf.onSelectEvent(ev); };
        [self addSubview:s];
        [secs addObject:s];
        [daysArr addObject:day];
        y += h;
    }
    _sections = secs;
    _sectionDays = daysArr;
    self.contentSize = CGSizeMake(320.0f, y);
    self.contentOffset = saved;
    if (!_built) {
        _built = YES;
        // первый показ: сегодня к текущему часу (чуть выше)
        NSUInteger idx = [daysArr indexOfObject:today];
        if (idx != NSNotFound) {
            UIView *sec = [secs objectAtIndex:idx];
            NSDate *now = [NSDate date];
            NSDateComponents *c = [d.cal components:NSHourCalendarUnit fromDate:now];
            [self setContentOffset:CGPointMake(0.0f, sec.frame.origin.y + MPCalDayHeaderH
                                               + (c.hour - 1) * MPCalDayHourH) animated:NO];
        }
    }
}

- (void)tick {
    for (NSUInteger i = 0; i < _sections.count; i++) {
        MPCalendarDaySection *s = [_sections objectAtIndex:i];
        if ([s isToday]) [s updateNowLine];
    }
}

- (void)gotoDayStart:(NSDate *)dayStart animated:(BOOL)animated {
    // точное indexOfObject ненадёжно: даты приходят из разных конструкторов
    // (парсер UTC / dateByAddingComponents), ищём секцию, содержащую сутки
    MPCalendarData *d = [MPCalendarData sharedData];
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < _sectionDays.count; i++) {
        NSDate *secDay = [_sectionDays objectAtIndex:i];
        if ([dayStart timeIntervalSinceDate:secDay] >= 0.0 &&
            [dayStart timeIntervalSinceDate:[d dayStartByAddingDays:1 toDayStart:secDay]] < 0.0) {
            idx = i;
            break;
        }
    }
    if (idx == NSNotFound) return;
    UIView *sec = [_sections objectAtIndex:idx];
    CGFloat y = sec.frame.origin.y;
    if ([[MPCalendarData sharedData] dayStartIsToday:dayStart]) {
        // сегодня — сразу к текущему часу
        NSDateComponents *c = [d.cal components:NSHourCalendarUnit fromDate:[NSDate date]];
        y += MPCalDayHeaderH + MAX(0, (NSInteger)c.hour - 1) * MPCalDayHourH;
    }
    [self setContentOffset:CGPointMake(0.0f, y) animated:animated];
}

- (void)scrollToTodayAnimated:(BOOL)animated {
    [self gotoDayStart:[[MPCalendarData sharedData] todayStart] animated:animated];
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - СТРАНИЦА «ПОВЕСТА» — дни с событиями, строки 56 pt

@implementation MPCalendarAgendaPage {
    NSArray *_sectionDays;
    NSArray *_sections;
    BOOL _built;
}

- (void)reload {
    CGPoint saved = self.contentOffset;
    for (UIView *v in [self.subviews copy]) [v removeFromSuperview];
    MPCalendarData *d = [MPCalendarData sharedData];
    NSDate *today = [d todayStart];
    NSMutableArray *secs = [NSMutableArray array];
    NSMutableArray *daysArr = [NSMutableArray array];
    CGFloat y = 0.0f;
    // один фетч на всю повестку (500 дней) — раньше серия промахов давала
    // до десятка синхронных рефетчей растущего диапазона на главном потоке
    [d ensureEventsFrom:[d dayStartByAddingDays:-45 toDayStart:today]
                     to:[d dayStartByAddingDays:455 toDayStart:today]];
    // дни от сегодня−45 до сегодня+15 месяцев: только с событиями (+ сегодня)
    for (NSInteger i = -45; i <= 455; i++) {
        NSDate *day = [d dayStartByAddingDays:i toDayStart:today];
        NSArray *evs = [d eventsForDayStart:day];
        BOOL isToday = [day isEqualToDate:today];
        if (evs.count == 0 && !isToday) continue;
        UIView *sec = [self makeSectionForDay:day events:evs y:y];
        [self addSubview:sec];
        [secs addObject:sec];
        [daysArr addObject:day];
        y += sec.bounds.size.height;
    }
    _sections = secs;
    _sectionDays = daysArr;
    self.contentSize = CGSizeMake(320.0f, y);
    self.contentOffset = saved;
    if (!_built) {
        _built = YES;
        [self scrollToTodayAnimated:NO];
    }
}

- (UIView *)makeSectionForDay:(NSDate *)day events:(NSArray *)evs y:(CGFloat)y {
    MPCalendarData *d = [MPCalendarData sharedData];
    BOOL isToday = [day isEqualToDate:[d todayStart]];
    CGFloat h = 36.0f + evs.count * MPCalAgendaRowH + 10.0f;
    if (evs.count == 0) h += 36.0f;
    UIView *sec = [[UIView alloc] initWithFrame:CGRectMake(0.0f, y, 320.0f, h)];
    sec.backgroundColor = [UIColor clearColor];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(MPCalLead, 6.0f, 280.0f, 30.0f)];
    title.font = [MPMetroStyle lightFont:24.0f];
    title.textColor = isToday ? [MPMetroStyle accentColor] : [UIColor whiteColor];
    title.backgroundColor = [UIColor clearColor];
    title.text = [d agendaTitleForDayStart:day];
    [sec addSubview:title];
    if (evs.count == 0) {
        UILabel *none = [[UILabel alloc] initWithFrame:CGRectMake(MPCalLead, 42.0f, 260.0f, 24.0f)];
        none.font = [MPMetroStyle regularFont:15.0f];
        none.textColor = [MPCalendarTheme disabledColor];
        none.backgroundColor = [UIColor clearColor];
        none.text = @"нет событий";
        [sec addSubview:none];
        return sec;
    }
    for (NSUInteger k = 0; k < evs.count; k++) {
        MPCalendarEvent *ev = [evs objectAtIndex:k];
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(0.0f,
                36.0f + k * MPCalAgendaRowH, 320.0f, MPCalAgendaRowH)];
        row.backgroundColor = [UIColor clearColor];
        UIView *mark = [[UIView alloc] initWithFrame:CGRectMake(MPCalLead + 2.0f, 24.0f, 8.0f, 8.0f)];
        mark.backgroundColor = ev.color ?: [UIColor grayColor];
        mark.userInteractionEnabled = NO;
        [row addSubview:mark];
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(36.0f, 7.0f, 268.0f, 30.0f)];
        t.font = [MPMetroStyle lightFont:24.0f];
        t.textColor = [UIColor whiteColor];
        t.backgroundColor = [UIColor clearColor];
        t.text = ev.title.length ? ev.title : @"(без названия)";
        [row addSubview:t];
        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(36.0f, 32.0f, 268.0f, 18.0f)];
        sub.font = [MPMetroStyle regularFont:13.0f];
        sub.textColor = [MPCalendarTheme mutedColor];
        sub.backgroundColor = [UIColor clearColor];
        sub.text = ev.allDay ? @"весь день" : [ev timeSpanString];
        [row addSubview:sub];
        [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(row, @selector(rowTapped:), ev, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sec addSubview:row];
    }
    return sec;
}

- (void)rowTapped:(UIControl *)sender {
    MPCalendarEvent *ev = objc_getAssociatedObject(sender, @selector(rowTapped:));
    if (ev != nil && self.onSelectEvent) self.onSelectEvent(ev);
}

- (void)gotoDayStart:(NSDate *)dayStart animated:(BOOL)animated {
    // точное indexOfObject ненадёжно: даты приходят из разных конструкторов
    // (парсер UTC / dateByAddingComponents) — ищем секцию, содержащую сутки,
    // как в странице «день»
    MPCalendarData *d = [MPCalendarData sharedData];
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < _sectionDays.count; i++) {
        NSDate *secDay = [_sectionDays objectAtIndex:i];
        if ([dayStart timeIntervalSinceDate:secDay] >= 0.0 &&
            [dayStart timeIntervalSinceDate:[d dayStartByAddingDays:1 toDayStart:secDay]] < 0.0) {
            idx = i;
            break;
        }
    }
    if (idx == NSNotFound) {
        // дня нет в повестке (без событий) — до ближайшего следующего
        for (NSUInteger i = 0; i < _sectionDays.count; i++) {
            if ([dayStart compare:[_sectionDays objectAtIndex:i]] == NSOrderedAscending) {
                idx = i;
                break;
            }
        }
        if (idx == NSNotFound) return;
    }
    UIView *sec = [_sections objectAtIndex:idx];
    [self setContentOffset:CGPointMake(0.0f, sec.frame.origin.y) animated:animated];
}

- (void)scrollToTodayAnimated:(BOOL)animated {
    [self gotoDayStart:[[MPCalendarData sharedData] todayStart] animated:animated];
}

@end
