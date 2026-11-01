#import "MPClockPages.h"
#import "MPClockTheme.h"
#import "MPClockData.h"
#import "MPClockEditor.h"
#import "MetroLauncher/MPMetroStyle.h"
#import "MetroLauncher/MPAnimationConstants.h"   // константы анимаций проекта
#import <QuartzCore/QuartzCore.h>

// Геометрия страницы в системе дизайна проекта (Настройки): поля 16,
// строки light 24 с подписями regular 13 (серые 0.6), разделители white .09.
// Страница шириной MPClockStride (320); контент живёт в полосе [16, 304].
#define MPContentW  288.0f
#define MPPageInset 16.0f

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Дисплей с роллом цифр (общий для секундомера и таймера)

// Дисплей = контейнер со слотами по символам; смена текста: изменившаяся
// цифра уезжает вверх, новая въезжает снизу (вертикальный ролл, WP-часы).
// Ширина слота цифры фиксирована по «0» (иначе «1» тоньше и строка прыгает),
// разделители «:» и «.» — своей ширины. Контейнер ничего не рисует сам.
@interface MPDigitDisplay : UIView
- (id)initWithFont:(UIFont *)font textColor:(UIColor *)color;
- (void)setText:(NSString *)text animated:(BOOL)animated;
- (void)setDigitColor:(UIColor *)color;   // перекрасить цифры (напр. по истечении)
@property (nonatomic, assign) BOOL centered;   // центрировать строку в контейнере
@end

@implementation MPDigitDisplay {
    NSMutableArray *_slots;
    UIFont *_font;
    UIColor *_ink;
}
@synthesize centered = _centered;

- (id)initWithFont:(UIFont *)font textColor:(UIColor *)color {
    self = [super initWithFrame:CGRectMake(0.0f, 0.0f, 10.0f, 72.0f)];
    if (self) {
        _slots = [[NSMutableArray alloc] init];
        _font = font;
        _ink = color;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (CGFloat)mpCharSlotWidth:(NSString *)ch {
    if ([ch isEqualToString:@":"] || [ch isEqualToString:@"."]) {
        return ceilf([ch sizeWithFont:_font].width);
    }
    return ceilf([@"0" sizeWithFont:_font].width);
}

- (UILabel *)mpNewLabel:(NSString *)ch width:(CGFloat)w height:(CGFloat)h y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, y, w, h)];
    l.backgroundColor = [UIColor clearColor];
    l.font = _font;
    l.textColor = _ink;
    l.textAlignment = NSTextAlignmentCenter;
    l.text = ch;
    return l;
}

- (void)mpRebuild:(NSString *)text {
    for (UIView *v in self.subviews) [v removeFromSuperview];
    [_slots removeAllObjects];
    CGFloat h = self.bounds.size.height;
    // суммарная ширина строки — для центрирования
    CGFloat total = 0.0f;
    for (NSUInteger i = 0; i < text.length; i++) {
        total += [self mpCharSlotWidth:[text substringWithRange:NSMakeRange(i, 1)]];
    }
    CGFloat x = _centered ? ((self.bounds.size.width - total) / 2.0f) : 0.0f;
    for (NSUInteger i = 0; i < text.length; i++) {
        NSString *ch = [text substringWithRange:NSMakeRange(i, 1)];
        CGFloat w = [self mpCharSlotWidth:ch];
        UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(x, 0.0f, w, h)];
        slot.clipsToBounds = YES;   // ролл обрезается в слоте
        slot.backgroundColor = [UIColor clearColor];
        [slot addSubview:[self mpNewLabel:ch width:w height:h y:0.0f]];
        [self addSubview:slot];
        [_slots addObject:slot];
        x += w;
    }
}

- (void)setText:(NSString *)text animated:(BOOL)animated {
    if (_slots.count != text.length) {
        [self mpRebuild:text];
        return;
    }
    CGFloat h = self.bounds.size.height;
    for (NSUInteger i = 0; i < text.length; i++) {
        NSString *ch = [text substringWithRange:NSMakeRange(i, 1)];
        UIView *slot = [_slots objectAtIndex:i];
        UILabel *cur = [slot.subviews lastObject];
        if ([cur.text isEqualToString:ch]) continue;
        if (!animated) {
            cur.text = ch;
            continue;
        }
        UILabel *next = [self mpNewLabel:ch width:slot.bounds.size.width height:h y:h];
        [slot addSubview:next];
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0.22f];
        [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
        cur.frame = CGRectMake(0.0f, -h, cur.frame.size.width, h);
        next.frame = CGRectMake(0.0f, 0.0f, next.frame.size.width, h);
        [UIView commitAnimations];
        UILabel *old = cur;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [old removeFromSuperview]; });
    }
}

- (void)setDigitColor:(UIColor *)color {
    _ink = color;
    for (UIView *slot in _slots) {
        for (UILabel *l in slot.subviews) l.textColor = color;
    }
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Общие помощники

static UIColor *MPMuted(void) { return [MPClockTheme mutedColor]; }

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - MPClockBasePage

@implementation MPClockBasePage

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.showsHorizontalScrollIndicator = NO;
        self.alwaysBounceVertical = YES;
        self.delaysContentTouches = NO;
        self.contentSize = CGSizeMake(MPClockStride, frame.size.height);
    }
    return self;
}

- (void)reload { }
- (void)tick { }

- (void)setEditingModeAnimated:(BOOL)on {
    _editingMode = on;
    [self reload];
}

- (void)setEditingMode:(BOOL)on {
    [self setEditingModeAnimated:on];
}

// Кнопка удаления строки «×» (режим правки) — текст без плашки (коробок нет)
- (UIButton *)deleteButtonAtRow:(NSUInteger)row target:(id)target action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(MPPageInset, 0.0f, 30.0f, 30.0f);
    b.titleLabel.font = [MPMetroStyle lightFont:18.0f];
    [b setTitle:@"×" forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[MPClockTheme faintColor] forState:UIControlStateHighlighted];
    b.tag = row;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Мировые часы

// строка списка: город + «сегодня, −3 ч» слева, время thin 28 справа
@interface MPWorldRow : NSObject
@property (nonatomic, retain) UILabel *city, *sub, *time;
@property (nonatomic, retain) MPClockCity *data;
@end
@implementation MPWorldRow @end

static NSDateFormatter *MPClockFmt(void) {
    static NSDateFormatter *fmt = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm";
    });
    return fmt;
}

@implementation MPClockWorldPage {
    NSMutableArray *_rows;
    NSInteger _dragRow, _dragTarget;   // перетаскивание: откуда и куда едет
    CGPoint _dragStartLoc;
    BOOL _dragging;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _rows = [NSMutableArray array];
        // перетаскивание города: долгий тап по строке — строка «взята» и едет
        // за пальцем; вертикальный скролл не мешает (он требует движения сразу,
        // долгий тап — неподвижности)
        UILongPressGestureRecognizer *lp =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(dragPress:)];
        lp.minimumPressDuration = 0.45f;
        [self addGestureRecognizer:lp];
    }
    return self;
}

// Типографика строки — из Настроек: заголовок light 24, подпись regular 13;
// время — крупный акцент thin 28 у правого края (язык WP-часов)
- (void)reload {
    // свои кнопки-действия (тег 100+, «Изменить»/«Добавить» из пивота)
    // переживаем: reload сносит только содержимое списка
    for (UIView *v in [self.subviews copy]) {
        if ([v isKindOfClass:[UIButton class]] && v.tag >= 100) continue;
        [v removeFromSuperview];
    }
    [_rows removeAllObjects];

    NSArray *cities = [MPClockData cities];
    CGFloat y = MPClockListTop;   // сверху строка кнопок страницы (Изменить/Добавить)
    BOOL edit = self.isEditingMode;
    CGFloat contentX = edit ? 56.0f : MPPageInset;   // под кнопку «×»
    CGFloat textW = MPPageInset + MPContentW - contentX - 100.0f;
    CGFloat timeX = MPPageInset + MPContentW - 90.0f;

    for (NSUInteger i = 0; i < cities.count; i++) {
        MPClockCity *c = [cities objectAtIndex:i];

        if (edit) {
            UIButton *del = [self deleteButtonAtRow:i target:self action:@selector(deleteTapped:)];
            del.frame = CGRectMake(MPPageInset, y + 13.0f, 30.0f, 30.0f);
            [self addSubview:del];
        }

        // ячейка по канону «Настроек»: заголовок y+7 h30, значение под ним y+32
        UILabel *city = [[UILabel alloc] initWithFrame:CGRectMake(contentX, y + 7.0f, textW, 30.0f)];
        city.backgroundColor = [UIColor clearColor];
        city.font = [MPMetroStyle lightFont:24.0f];
        city.textColor = [UIColor whiteColor];
        city.text = c.name;

        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(contentX, y + 32.0f, textW, 18.0f)];
        sub.backgroundColor = [UIColor clearColor];
        sub.font = [MPMetroStyle regularFont:13.0f];
        sub.textColor = MPMuted();

        // время thin 28 — по центру строки 56 (канон высоты строки)
        UILabel *time = [[UILabel alloc] initWithFrame:CGRectMake(timeX, y + 10.0f, 90.0f, 36.0f)];
        time.backgroundColor = [UIColor clearColor];
        time.font = [MPMetroStyle thinFont:28.0f];
        time.textColor = [UIColor whiteColor];
        time.textAlignment = NSTextAlignmentRight;

        [self addSubview:city];
        [self addSubview:sub];
        [self addSubview:time];

        MPWorldRow *row = [[MPWorldRow alloc] init];
        row.city = city; row.sub = sub; row.time = time; row.data = c;
        [_rows addObject:row];
        y += 56.0f;
    }

    if (cities.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(contentX, MPClockListTop, MPContentW, 40.0f)];
        empty.backgroundColor = [UIColor clearColor];
        empty.font = [MPMetroStyle lightFont:20.0f];
        empty.textColor = MPMuted();
        empty.text = @"Нет городов";
        [self addSubview:empty];
        y += 50.0f;
    }

    self.contentSize = CGSizeMake(MPClockStride, y + 8.0f);
    [self tick];
}

- (void)tick {
    NSDate *now = [NSDate date];
    NSDateFormatter *fmt = MPClockFmt();
    for (MPWorldRow *r in _rows) {
        fmt.timeZone = r.data.zone;
        r.time.text = [fmt stringFromDate:now];
        // день и сдвиг — одной подписью слева (в строке 56 правая метка дня не живёт)
        NSString *dw = [r.data dayWord];
        NSInteger h = [r.data hoursFromLocal];
        if ([dw isEqualToString:@"сегодня"]) {
            r.sub.text = (h == 0) ? @"сегодня" : [NSString stringWithFormat:
                @"сегодня, %@%ld ч", (h > 0 ? @"+" : @"−"), (long)labs(h)];
        } else {
            r.sub.text = [NSString stringWithFormat:@"%@, %@%ld ч", dw,
                          (h > 0 ? @"+" : @"−"), (long)labs(h)];
        }
    }
}

- (void)deleteTapped:(UIButton *)sender {
    NSArray *cities = [MPClockData cities];
    if (sender.tag >= cities.count) return;
    MPClockCity *c = [cities objectAtIndex:sender.tag];
    [MPClockData removeCityWithZoneID:c.zoneID];
    MPLog(@"[Clock] город удалён: %@", c.zoneID);
    [self reload];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark Перетаскивание городов

// базовый y строки i в координатах контента (список от y=0, шаг 56)
static CGFloat MPWorldRowBaseY(NSInteger i) { return MPClockListTop + (CGFloat)i * 56.0f; }

// метки строки живут в контентных координатах: меняем только origin.y
- (void)setRowY:(NSInteger)i y:(CGFloat)y {
    MPWorldRow *r = [_rows objectAtIndex:i];
    r.city.frame = CGRectMake(r.city.frame.origin.x, y + 7.0f,
                              r.city.frame.size.width, r.city.frame.size.height);
    r.sub.frame  = CGRectMake(r.sub.frame.origin.x,  y + 32.0f,
                              r.sub.frame.size.width,  r.sub.frame.size.height);
    r.time.frame = CGRectMake(r.time.frame.origin.x, y + 10.0f,
                              r.time.frame.size.width, r.time.frame.size.height);
}

- (void)setRowAlpha:(NSInteger)i alpha:(CGFloat)a {
    MPWorldRow *r = [_rows objectAtIndex:i];
    r.city.alpha = a; r.sub.alpha = a; r.time.alpha = a;
}

- (void)dragPress:(UILongPressGestureRecognizer *)gr {
    NSArray *cities = [MPClockData cities];
    CGPoint loc = [gr locationInView:self];

    if (gr.state == UIGestureRecognizerStateBegan) {
        if (cities.count < 2) return;
        // locationInView: уже в контентных координатах (bounds.origin =
        // contentOffset у UIScrollView) — прокрутку прибавлять НЕ нужно
        NSInteger row = (NSInteger)floor((loc.y - MPClockListTop) / 56.0f);
        if (row < 0 || row >= (NSInteger)cities.count) return;
        _dragging = YES;
        _dragRow = row;
        _dragTarget = row;
        _dragStartLoc = loc;
        [self setRowAlpha:row alpha:0.7f];   // «взяли»
    } else if (gr.state == UIGestureRecognizerStateChanged && _dragging) {
        CGFloat dy = loc.y - _dragStartLoc.y;
        NSInteger target = _dragRow + (NSInteger)round(dy / 56.0f);
        if (target < 0) target = 0;
        if (target > (NSInteger)cities.count - 1) target = cities.count - 1;
        _dragTarget = target;
        // взятая строка едет за пальцем, остальные расступаются
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0.12];
        for (NSInteger i = 0; i < (NSInteger)_rows.count; i++) {
            CGFloat y = MPWorldRowBaseY(i);
            if (i == _dragRow) {
                y = MPWorldRowBaseY(_dragRow) + dy;
            } else if (_dragRow < _dragTarget && i > _dragRow && i <= _dragTarget) {
                y -= 56.0f;
            } else if (_dragRow > _dragTarget && i >= _dragTarget && i < _dragRow) {
                y += 56.0f;
            }
            [self setRowY:i y:y];
        }
        [UIView commitAnimations];
    } else if ((gr.state == UIGestureRecognizerStateEnded ||
                gr.state == UIGestureRecognizerStateCancelled ||
                gr.state == UIGestureRecognizerStateFailed) && _dragging) {
        _dragging = NO;
        [MPClockData moveCityFromIndex:_dragRow toIndex:_dragTarget];
        [self reload];   // пересобрать строки в новом порядке (и вернуть alpha)
    }
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - WP-тумблер — точная копия MPSettingsToggle из «Настроек»:
// прямоугольник 46×22, выключен = белый 0.38, включен = акцент; бегунок —
// белый квадрат side = h−4 = 18 с отступом 2, анимация 0.15
// (объявление класса — в MPClockPages.h, нужен ещё и редактору)

@implementation MPWPToggle

- (id)initWithFrame:(CGRect)frame on:(BOOL)on change:(void (^)(BOOL))change {
    self = [super initWithFrame:CGRectMake(frame.origin.x, frame.origin.y, 46.0f, 22.0f)];
    if (self) {
        self.backgroundColor = on ? [MPMetroStyle accentColor]
                                  : [UIColor colorWithWhite:1.0f alpha:0.38f];
        _on = on;
        _onChange = [change copy];
        [self syncKnobAnimated:NO];
    }
    return self;
}

// Бегунок: белый квадрат side = высота − 4 (как MPSettingsToggle)
- (void)syncKnobAnimated:(BOOL)animated {
    UIView *knob = nil;
    for (UIView *v in self.subviews) {
        if (v.tag == 0x4D504E4F) { knob = v; break; }
    }
    if (knob == nil) {
        knob = [[UIView alloc] initWithFrame:CGRectZero];
        knob.backgroundColor = [UIColor whiteColor];
        knob.tag = 0x4D504E4F;
        [self addSubview:knob];
    }
    CGFloat side = self.bounds.size.height - 4.0f;
    CGFloat knobX = _on ? (self.bounds.size.width - side - 2.0f) : 2.0f;
    CGRect target = CGRectMake(knobX, 2.0f, side, side);
    UIColor *bg = _on ? [MPMetroStyle accentColor]
                      : [UIColor colorWithWhite:1.0f alpha:0.38f];
    if (animated && !CGRectEqualToRect(knob.frame, target)) {
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0.15];
        knob.frame = target;
        self.backgroundColor = bg;
        [UIView commitAnimations];
    } else {
        knob.frame = target;
        self.backgroundColor = bg;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint p = [t locationInView:self];
    if (p.x < -20.0f || p.x > self.bounds.size.width + 20.0f ||
        p.y < -20.0f || p.y > self.bounds.size.height + 20.0f) return;
    [self setOn:!_on];
    if (_onChange) _onChange(_on);
}

- (void)setOn:(BOOL)on {
    if (_on == on) return;
    _on = on;
    [self syncKnobAnimated:YES];
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Будильники

// Строка: время thin 28 + подпись regular 13, тумблер справа — типографика
// как в мировых часах (главное y+7, подпись y+32)
@implementation MPClockAlarmPage

- (void)reload {
    // свои кнопки-действия (тег 100+) переживаем — как на мировой странице
    for (UIView *v in [self.subviews copy]) {
        if ([v isKindOfClass:[UIButton class]] && v.tag >= 100) continue;
        [v removeFromSuperview];
    }

    NSArray *alarms = [MPClockData alarms];
    CGFloat y = MPClockListTop;   // сверху строка кнопок страницы (Изменить/Добавить)
    BOOL edit = self.isEditingMode;
    CGFloat contentX = edit ? 56.0f : MPPageInset;
    CGFloat subW = MPPageInset + MPContentW - contentX - 60.0f;
    CGFloat togX = MPPageInset + MPContentW - 46.0f;   // правый край контента

    for (NSUInteger i = 0; i < alarms.count; i++) {
        MPClockAlarm *a = [alarms objectAtIndex:i];

        if (edit) {
            UIButton *del = [self deleteButtonAtRow:i target:self action:@selector(deleteTapped:)];
            del.frame = CGRectMake(MPPageInset, y + 13.0f, 30.0f, 30.0f);
            [self addSubview:del];
        }

        // типографика строки — как в мировых часах: главное (время) y+7,
        // подпись под ним y+32
        UILabel *time = [[UILabel alloc] initWithFrame:CGRectMake(contentX, y + 7.0f, 160.0f, 30.0f)];
        time.backgroundColor = [UIColor clearColor];
        time.font = [MPMetroStyle thinFont:28.0f];
        time.text = [NSString stringWithFormat:@"%ld:%02ld", (long)a.hour, (long)a.minute];

        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(contentX, y + 32.0f, subW, 18.0f)];
        sub.backgroundColor = [UIColor clearColor];
        sub.font = [MPMetroStyle regularFont:13.0f];
        sub.text = [a repeatLabel];

        // выключенный будильник — канон «Настроек» для disabled: время 0.4,
        // подпись 0.6 (как у всех значений); включённый — белый/0.6
        BOOL on = a.enabled;
        time.textColor = on ? [UIColor whiteColor] : [MPClockTheme disabledColor];
        sub.textColor = MPMuted();

        MPWPToggle *tog = [[MPWPToggle alloc] initWithFrame:CGRectMake(togX, y + 17.0f, 46.0f, 22.0f)
                                                        on:a.enabled
                                                    change:^(BOOL on) {
            // берём свежую модель из префов (список мог переиспользоваться)
            NSArray *cur = [MPClockData alarms];
            if (i < cur.count) {
                [MPClockData setEnabled:on forAlarm:[cur objectAtIndex:i]];
                [self reload];   // приглушить/осветлить строку под новое состояние
            }
        }];
        [self addSubview:time];
        [self addSubview:sub];
        [self addSubview:tog];

        y += 56.0f;
    }

    if (alarms.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(contentX, MPClockListTop, MPContentW, 40.0f)];
        empty.backgroundColor = [UIColor clearColor];
        empty.font = [MPMetroStyle lightFont:20.0f];
        empty.textColor = MPMuted();
        empty.text = @"Нет будильников";
        [self addSubview:empty];
        y += 50.0f;
    }

    self.contentSize = CGSizeMake(MPClockStride, y + 8.0f);
}

- (void)deleteTapped:(UIButton *)sender {
    NSArray *alarms = [MPClockData alarms];
    if (sender.tag >= alarms.count) return;
    [MPClockData removeAlarm:[alarms objectAtIndex:sender.tag]];
    [self reload];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    // тап по строке (не по тумблеру/кнопке — те обрабатывают сами) — редактор
    UITouch *t = [touches anyObject];
    if (t.phase != UITouchPhaseEnded) return;
    if (self.dragging || self.decelerating) return;   // это был скролл, не тап
    // ВАЖНО: locationInView: у UIScrollView уже в КОНТЕНТНЫХ координатах
    // (bounds.origin = contentOffset) — прокрутку добавлять не нужно
    CGPoint p = [t locationInView:self];
    NSUInteger row = (NSUInteger)(p.y / 56.0f);   // высота строки, список с y=0
    NSArray *alarms = [MPClockData alarms];
    if (p.y < 0.0f || row >= alarms.count) return;
    MPClockAlarm *a = [alarms objectAtIndex:row];
    [[MPClockEditor sharedEditor] presentInPage:self alarm:a];
}

- (void)tick { /* будильники не тикают */ }

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Секундомер

@implementation MPClockStopwatchPage {
    MPDigitDisplay *_digits;   // дисплей с роллом цифр
    UIButton *_lapBtn;     // «круг»/«сброс»
    UIButton *_goBtn;      // «старт»/«стоп»
    UIView *_lapsView;
    BOOL _running;
    CFAbsoluteTime _start, _acc, _lapMark;
    NSInteger _lapN;
    CADisplayLink *_link;
}

@synthesize mpOnStateChange = _mpOnStateChange;

// сообщить шапке (и всем слушателям) новое состояние
- (void)mpNotifyState {
    if (_mpOnStateChange) _mpOnStateChange(_running, _acc > 0.0);
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // крупные тонкие цифры, по левой линии (как весь контент);
        // y = −50: страница НЕ обрезается и НЕ скроллится (см. ниже), поэтому
        // кадры могут выходить за границы — контент ближе к шапке
        _digits = [[MPDigitDisplay alloc] initWithFont:[MPMetroStyle thinFont:60.0f]
                                             textColor:[UIColor whiteColor]];
        _digits.frame = CGRectMake(MPPageInset, 0.0f, MPContentW, 72.0f);
        [self addSubview:_digits];
        [_digits setText:@"0:00.0" animated:NO];

        // кнопки рядом слева, БЕЛЫЕ (как действия шапки): ширины по тексту;
        // зазор от цифр минимальный (8)
        CGFloat by = 0.0f + 72.0f + 8.0f;
        _lapBtn = [MPClockTheme actionButtonWithTitle:@"Круг"];
        _lapBtn.frame = CGRectMake(MPPageInset, by, 80.0f, 44.0f);
        [_lapBtn addTarget:self action:@selector(lapTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_lapBtn];

        _goBtn = [MPClockTheme actionButtonWithTitle:@"Старт"];
        _goBtn.frame = CGRectMake(MPPageInset + 80.0f + MPClockActionsGap, by, 90.0f, 44.0f);
        [_goBtn addTarget:self action:@selector(goTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_goBtn];

        _lapsView = [[UIView alloc] initWithFrame:CGRectMake(MPPageInset, by + 44.0f + 12.0f,
                                                              MPContentW,
                                                              frame.size.height - by - 64.0f)];
        [self addSubview:_lapsView];
        [self layoutButtons];

        // страница секундомера не скроллится; обрезка включена — контентный
        // параллакс при свайпе режется по границе вкладки
        self.scrollEnabled = NO;
        self.alwaysBounceVertical = NO;
    }
    return self;
}

// кадры кнопок по фактической ширине заголовков («Старт»↔«Стоп»,
// «Круг»↔«Сброс» меняют ширину) — как layoutActionButtons в шапке
- (void)layoutButtons {
    CGFloat x = MPPageInset;
    CGSize as_ = [_lapBtn.titleLabel.text sizeWithFont:_lapBtn.titleLabel.font];
    _lapBtn.frame = CGRectMake(x, _lapBtn.frame.origin.y,
                               ceilf(as_.width) + 4.0f, _lapBtn.frame.size.height);
    x += ceilf(as_.width) + 4.0f + MPClockActionsGap;
    CGSize bs = [_goBtn.titleLabel.text sizeWithFont:_goBtn.titleLabel.font];
    _goBtn.frame = CGRectMake(x, _goBtn.frame.origin.y,
                              ceilf(bs.width) + 4.0f, _goBtn.frame.size.height);
}

- (NSString *)format:(CFAbsoluteTime)ms {
    NSInteger total = (NSInteger)(ms / 10.0);      // десятые доли
    NSInteger tenth = total % 10;
    NSInteger sec = (total / 10) % 60;
    NSInteger min = total / 600;
    return [NSString stringWithFormat:@"%ld:%02ld.%ld", (long)min, (long)sec, (long)tenth];
}

- (void)goTapped {
    if (!_running) {
        _running = YES;
        _start = CFAbsoluteTimeGetCurrent();
        [_goBtn setTitle:@"Стоп" forState:UIControlStateNormal];
        [_lapBtn setTitle:@"Круг" forState:UIControlStateNormal];
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayTick)];
        [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        [_digits setText:@"0:00.0" animated:YES];
    } else {
        _acc += (CFAbsoluteTimeGetCurrent() - _start) * 1000.0f;
        _running = NO;
        [_link invalidate];
        _link = nil;
        [_goBtn setTitle:@"Старт" forState:UIControlStateNormal];
        [_lapBtn setTitle:@"Сброс" forState:UIControlStateNormal];
        [_digits setText:[self format:_acc] animated:YES];
    }
    [self layoutButtons];
    [self mpNotifyState];
}

- (void)lapTapped {
    if (_running) {
        CFAbsoluteTime cur = _acc + (CFAbsoluteTimeGetCurrent() - _start) * 1000.0f;
        CFAbsoluteTime lap = cur - _lapMark;
        _lapMark = cur;
        _lapN++;
        // строка круга: «Круг N» regular 13 слева серым, время круга
        // light 20 белым у правого края; новые сверху
        UIView *rowWrap = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, MPContentW, 40.0f)];
        UILabel *n = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 10.0f, 120.0f, 20.0f)];
        n.backgroundColor = [UIColor clearColor];
        n.font = [MPMetroStyle regularFont:13.0f];
        n.textColor = MPMuted();
        n.text = [NSString stringWithFormat:@"Круг %ld", (long)_lapN];
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(MPContentW - 150.0f, 6.0f, 150.0f, 28.0f)];
        t.backgroundColor = [UIColor clearColor];
        t.font = [MPMetroStyle lightFont:20.0f];
        t.textColor = [UIColor whiteColor];
        t.textAlignment = NSTextAlignmentRight;
        t.text = [self format:lap];
        [rowWrap addSubview:n];
        [rowWrap addSubview:t];
        // существующие круги сдвигаются вниз (список растёт — contentSize
        // увеличиваем, чтобы старые круги были доступны прокруткой)
        for (UIView *v in _lapsView.subviews) {
            CGRect f = v.frame;
            f.origin.y += 40.0f;
            v.frame = f;
        }
        [_lapsView addSubview:rowWrap];
        CGFloat needH = 136.0f + (CGFloat)_lapN * 40.0f + 32.0f;
        if (needH > self.frame.size.height) {
            self.contentSize = CGSizeMake(MPClockStride, needH);
        }
    } else if (_acc > 0.0) {
        _acc = 0.0; _lapMark = 0.0; _lapN = 0;
        for (UIView *v in _lapsView.subviews) [v removeFromSuperview];
        self.contentSize = CGSizeMake(MPClockStride, self.frame.size.height);
        [_goBtn setTitle:@"Старт" forState:UIControlStateNormal];
        [_lapBtn setTitle:@"Круг" forState:UIControlStateNormal];
        [_digits setText:@"0:00.0" animated:YES];
    }
    [self layoutButtons];
    [self mpNotifyState];
}

- (void)displayTick {
    if (_running) {
        CFAbsoluteTime cur = _acc + (CFAbsoluteTimeGetCurrent() - _start) * 1000.0f;
        [_digits setText:[self format:cur] animated:NO];
    }
}

- (void)tick { /* секундомер живёт своим CADisplayLink */ }

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Таймер

@implementation MPClockTimerPage {
    // пикер
    UIView *_picker;
    UILabel *_hVal, *_mVal, *_sVal;
    // отсчёт — дисплей как в секундомере (ролл цифр)
    MPDigitDisplay *_digits;
    // кнопки
    UIButton *_resetBtn, *_goBtn;
    NSInteger _h, _m, _s;
    NSInteger _total, _left;
    BOOL _running, _done;
    NSTimer *_timer;
    CFAbsoluteTime _endAt;
}

@synthesize mpOnStateChange = _mpOnStateChange;

// сообщить шапке новое состояние (Старт↔Пауза)
- (void)mpNotifyState {
    if (_mpOnStateChange) _mpOnStateChange(_running);
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _h = 0; _m = 5; _s = 0;

        // пикер из 3 колонок (часы/минуты/секунды), значения thin 60 —
        // поднят в зону шапки (колонка: «−» сверху, значение, «+» снизу)
        CGFloat colX = MPPageInset + (MPContentW - 3 * 80.0f - 2 * 8.0f) / 2.0f;
        _picker = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, MPClockStride, 164.0f)];
        _hVal = [self timeColumnWithMinus:@selector(hMinus) plus:@selector(hPlus)
                                     name:@"часы" x:colX];
        _mVal = [self timeColumnWithMinus:@selector(mMinus) plus:@selector(mPlus)
                                     name:@"минуты" x:colX + 88.0f];
        _sVal = [self timeColumnWithMinus:@selector(sMinus) plus:@selector(sPlus)
                                     name:@"секунды" x:colX + 176.0f];
        [self addSubview:_picker];

        // отсчёт — цифры внутри КВАДРАТНОГО прогресса: рамка 170×170, цифры
        // thin 48 по центру (свойства таймера — квадрат, а не кольцо)
        CGFloat side = 170.0f;
        CGFloat sqx = MPPageInset + (MPContentW - side) / 2.0f;
        CGRect sqRect = CGRectMake(sqx, 0.0f, side, side);

        _digits = [[MPDigitDisplay alloc] initWithFont:[MPMetroStyle thinFont:48.0f]
                                             textColor:[UIColor whiteColor]];
        _digits.centered = YES;
        _digits.frame = CGRectMake(sqRect.origin.x + 10.0f,
                                   sqRect.origin.y + (side - 56.0f) / 2.0f,
                                   side - 20.0f, 56.0f);
        _digits.hidden = YES;
        [self addSubview:_digits];



        // кнопки рядом слева, БЕЛЫЕ (как действия шапки); в режиме пикера —
        // под пикером, при отсчёте уедут ниже квадрата (см. goTapped/reset)
        CGFloat by = 164.0f + 16.0f;
        _resetBtn = [MPClockTheme actionButtonWithTitle:@"Сброс"];
        _resetBtn.frame = CGRectMake(MPPageInset, by, 90.0f, 44.0f);
        [_resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_resetBtn];

        _goBtn = [MPClockTheme actionButtonWithTitle:@"Старт"];
        _goBtn.frame = CGRectMake(MPPageInset + 90.0f + MPClockActionsGap, by, 90.0f, 44.0f);
        [_goBtn addTarget:self action:@selector(goTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_goBtn];
        [self layoutButtons];
        [self refreshPicker];

        // страница таймера не скроллится; обрезка включена — контентный
        // параллакс при свайпе режется по границе вкладки
        self.scrollEnabled = NO;
        self.alwaysBounceVertical = NO;
    }
    return self;
}

// кадры кнопок по фактической ширине заголовков («Старт»↔«Пауза»)
- (void)layoutButtons {
    CGFloat x = MPPageInset;
    CGSize as_ = [_resetBtn.titleLabel.text sizeWithFont:_resetBtn.titleLabel.font];
    _resetBtn.frame = CGRectMake(x, _resetBtn.frame.origin.y,
                                 ceilf(as_.width) + 4.0f, _resetBtn.frame.size.height);
    x += ceilf(as_.width) + 4.0f + MPClockActionsGap;
    CGSize bs = [_goBtn.titleLabel.text sizeWithFont:_goBtn.titleLabel.font];
    _goBtn.frame = CGRectMake(x, _goBtn.frame.origin.y,
                              ceilf(bs.width) + 4.0f, _goBtn.frame.size.height);
}

// Колонка пикера: «−» / значение thin 60 / «+» / подпись — кнопки текстовые
// акцентом (канон «Настроек»: коробок нет), по центру колонки 80
- (UILabel *)timeColumnWithMinus:(SEL)minus plus:(SEL)plus name:(NSString *)name x:(CGFloat)x {
    UIButton *minusB = [MPClockTheme bigTextAction:@"−" secondary:NO];
    minusB.frame = CGRectMake(x + 17.0f, 0.0f, 46.0f, 30.0f);
    minusB.titleLabel.font = [MPMetroStyle lightFont:20.0f];
    minusB.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [minusB addTarget:self action:minus forControlEvents:UIControlEventTouchUpInside];

    UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(x, 34.0f, 80.0f, 72.0f)];
    val.backgroundColor = [UIColor clearColor];
    val.font = [MPMetroStyle thinFont:60.0f];
    val.textColor = [UIColor whiteColor];
    val.textAlignment = NSTextAlignmentCenter;

    UIButton *plusB = [MPClockTheme bigTextAction:@"+" secondary:NO];
    plusB.frame = CGRectMake(x + 17.0f, 110.0f, 46.0f, 30.0f);
    plusB.titleLabel.font = [MPMetroStyle lightFont:20.0f];
    plusB.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [plusB addTarget:self action:plus forControlEvents:UIControlEventTouchUpInside];

    UILabel *nameL = [[UILabel alloc] initWithFrame:CGRectMake(x, 146.0f, 80.0f, 18.0f)];
    nameL.backgroundColor = [UIColor clearColor];
    nameL.font = [MPMetroStyle regularFont:13.0f];
    nameL.textColor = MPMuted();
    nameL.textAlignment = NSTextAlignmentCenter;
    nameL.text = name;

    [_picker addSubview:minusB];
    [_picker addSubview:val];
    [_picker addSubview:plusB];
    [_picker addSubview:nameL];
    return val;
}

- (void)refreshPicker {
    _hVal.text = [NSString stringWithFormat:@"%ld", (long)_h];
    _mVal.text = [NSString stringWithFormat:@"%ld", (long)_m];
    _sVal.text = [NSString stringWithFormat:@"%ld", (long)_s];
}

- (void)hMinus { if (!_running && _left == 0 && _h > 0)  { _h--;  [self refreshPicker]; } }
- (void)hPlus  { if (!_running && _left == 0 && _h < 23) { _h++;  [self refreshPicker]; } }
- (void)mMinus { if (!_running && _left == 0 && _m > 0)  { _m--;  [self refreshPicker]; } }
- (void)mPlus  { if (!_running && _left == 0 && _m < 59) { _m++;  [self refreshPicker]; } }
- (void)sMinus { if (!_running && _left == 0 && _s > 0)  { _s--;  [self refreshPicker]; } }
- (void)sPlus  { if (!_running && _left == 0 && _s < 59) { _s++;  [self refreshPicker]; } }

- (BOOL)running {
    return _running;
}

// прогресс отсчёта для квадратного индикатора в pivot (0..1)
- (CGFloat)progress {
    return (_total > 0) ? ((CGFloat)_left / (CGFloat)_total) : 1.0f;
}

- (NSString *)formatLeft:(NSInteger)sec {
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(sec / 60), (long)(sec % 60)];
}

- (void)goTapped {
    if (!_running) {
        if (_left == 0) {
            _total = _h * 3600 + _m * 60 + _s;
            if (_total == 0) return;
            _left = _total;
        }
        _running = YES;
        _done = NO;
        _endAt = CFAbsoluteTimeGetCurrent() + (NSTimeInterval)_left;
        [_goBtn setTitle:@"Пауза" forState:UIControlStateNormal];
        _picker.hidden = YES;
        _digits.hidden = NO;
        [_digits setDigitColor:[UIColor whiteColor]];
        [_digits setText:[self formatLeft:_left] animated:NO];
        [self setButtonsY:194.0f];   // ниже квадрата (абс. ~310)
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.25f target:self
                                                selector:@selector(countdownTick)
                                                userInfo:nil repeats:YES];
    } else {
        // пауза: замораживаем остаток
        _left = (NSInteger)MAX(0.0f, (CGFloat)(_endAt - CFAbsoluteTimeGetCurrent()));
        _running = NO;
        [_timer invalidate];
        _timer = nil;
        [_goBtn setTitle:@"Старт" forState:UIControlStateNormal];
    }
    [self layoutButtons];
    [self mpNotifyState];
}

// кадры кнопок на заданной высоте (режим пикера — 106, отсчёт — 194)
- (void)setButtonsY:(CGFloat)y {
    _resetBtn.frame = CGRectMake(_resetBtn.frame.origin.x, y,
                                 _resetBtn.frame.size.width, _resetBtn.frame.size.height);
    _goBtn.frame = CGRectMake(_goBtn.frame.origin.x, y,
                              _goBtn.frame.size.width, _goBtn.frame.size.height);
}

- (void)resetTapped {
    [_timer invalidate];
    _timer = nil;
    _running = NO;
    _left = 0;
    _done = NO;
    [_goBtn setTitle:@"Старт" forState:UIControlStateNormal];
    _picker.hidden = NO;
    _digits.hidden = YES;
    [self setButtonsY:106.0f];
    [self refreshPicker];
    [self layoutButtons];
    [self mpNotifyState];
}

- (void)countdownTick {
    if (!_running) return;
    _left = (NSInteger)MAX(0.0f, (CGFloat)(_endAt - CFAbsoluteTimeGetCurrent()));
    [_digits setText:[self formatLeft:_left] animated:YES];   // ролл раз в секунду
    if (_left <= 0) {
        _running = NO;
        [_timer invalidate];
        _timer = nil;
        [_goBtn setTitle:@"Старт" forState:UIControlStateNormal];
        [_digits setDigitColor:[MPMetroStyle accentColor]];   // по прототипу: цифры акцентом
        _done = YES;
        [self layoutButtons];
        [self mpNotifyState];
    }
}

- (void)tick { /* таймер живёт своим NSTimer */ }

@end
