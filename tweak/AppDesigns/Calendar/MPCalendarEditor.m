#import "MPCalendarEditor.h"
#import "MPCalendarTheme.h"
#import "MPCalendarData.h"
#import "MPCalendarPivotView.h"
#import "MetroLauncher/MPMetroStyle.h"

// WP-тумблер 46×22 (точная копия MPSettingsToggle/MPWPToggle: квадрат 18,
// акцент при on) — логика целиком наша, штатных переключателей тут нет
@interface MPCalEditorToggle : UIView
@property (nonatomic, assign) BOOL on;
@property (nonatomic, copy) void (^onChange)(BOOL on);
@end

@implementation MPCalEditorToggle

- (id)initWithFrame:(CGRect)frame on:(BOOL)on change:(void (^)(BOOL))change {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.on = on;
        self.onChange = change;
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(tapped:)];
        [self addGestureRecognizer:t];
        [self setNeedsDisplay];
    }
    return self;
}

- (void)setOn:(BOOL)on {
    _on = on;
    [self setNeedsDisplay];
}

- (void)tapped:(UITapGestureRecognizer *)g {
    self.on = !self.on;
    if (self.onChange) self.onChange(self.on);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIColor *track = self.on ? [MPMetroStyle accentColor]
                             : [UIColor colorWithWhite:1.0f alpha:0.38f];
    [track setFill];
    CGContextFillRect(ctx, CGRectMake(0.0f, 0.0f, 46.0f, 22.0f));
    [[UIColor blackColor] setFill];
    CGContextFillRect(ctx, CGRectMake(2.0f, 2.0f, 42.0f, 18.0f));
    [[UIColor whiteColor] setFill];
    CGFloat x = self.on ? 46.0f - 2.0f - 18.0f : 2.0f;
    CGContextFillRect(ctx, CGRectMake(x, 2.0f, 18.0f, 18.0f));
}

@end

//──────────────────────────────────────────────────────────────────────────────
// Группа «− значение +»: кнопки light 24, значение thin 34 (как пикер таймера
// «Часов»). Степпер держит СВОЮ дату: шаг применяет к ней (день ±1, час ±1,
// минута ±5) и уведомляет onChange; отображение — setDate:.

@interface MPCalStepper : UIView {
    UILabel *_value;
    NSInteger _kind;            // 0=день 1=час 2=минута
}
@property (nonatomic, retain) NSDate *dateValue;
@property (nonatomic, copy) void (^onChange)(void);
- (id)initWithFrame:(CGRect)frame kind:(NSInteger)kind;
@end

@implementation MPCalStepper

- (id)initWithFrame:(CGRect)frame kind:(NSInteger)kind {
    self = [super initWithFrame:frame];
    if (self) {
        _kind = kind;
        self.backgroundColor = [UIColor clearColor];
        CGFloat bw0 = 26.0f;
        _value = [[UILabel alloc] initWithFrame:CGRectMake(bw0 + 4.0f, 0.0f,
                                                           frame.size.width - 2.0f * (bw0 + 4.0f), 36.0f)];
        _value.font = [MPMetroStyle thinFont:30.0f];
        _value.textColor = [UIColor whiteColor];
        _value.backgroundColor = [UIColor clearColor];
        _value.textAlignment = NSTextAlignmentCenter;
        _value.adjustsFontSizeToFitWidth = YES;
        _value.minimumFontSize = 14.0f;
        [self addSubview:_value];
        CGFloat bw = 26.0f;
        NSString *minus = @"\u2212";   // типографский минус
        UIButton *m = [UIButton buttonWithType:UIButtonTypeCustom];
        m.frame = CGRectMake(0.0f, 0.0f, bw, 36.0f);
        m.titleLabel.font = [MPMetroStyle lightFont:24.0f];
        [m setTitle:minus forState:UIControlStateNormal];
        [m setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [m setTitleColor:[MPCalendarTheme mutedColor] forState:UIControlStateHighlighted];
        [m addTarget:self action:@selector(step:) forControlEvents:UIControlEventTouchUpInside];
        m.tag = -1;
        [self addSubview:m];
        UIButton *p = [UIButton buttonWithType:UIButtonTypeCustom];
        p.frame = CGRectMake(frame.size.width - bw, 0.0f, bw, 36.0f);
        p.titleLabel.font = [MPMetroStyle lightFont:24.0f];
        [p setTitle:@"+" forState:UIControlStateNormal];
        [p setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [p setTitleColor:[MPCalendarTheme mutedColor] forState:UIControlStateHighlighted];
        [p addTarget:self action:@selector(step:) forControlEvents:UIControlEventTouchUpInside];
        p.tag = 1;
        [self addSubview:p];
    }
    return self;
}

- (void)setDateValue:(NSDate *)date {
    _dateValue = date;
    MPCalendarData *d = [MPCalendarData sharedData];
    NSDateComponents *c = [d.cal components:NSHourCalendarUnit | NSMinuteCalendarUnit
                                    fromDate:date];
    switch (_kind) {
        case 0: _value.text = [d dayMonthStringForDate:date]; break;
        case 1: _value.text = [NSString stringWithFormat:@"%02ld", (long)c.hour]; break;
        default: _value.text = [NSString stringWithFormat:@"%02ld", (long)c.minute]; break;
    }
}

- (void)step:(UIButton *)sender {
    if (_dateValue == nil) return;
    NSDateComponents *c = [[NSDateComponents alloc] init];
    if (_kind == 0) c.day = sender.tag;
    else if (_kind == 1) c.hour = sender.tag;
    else c.minute = sender.tag * 5;
    self.dateValue = [[MPCalendarData sharedData].cal
                      dateByAddingComponents:c toDate:_dateValue options:0];
    if (self.onChange) self.onChange();
}

@end

//──────────────────────────────────────────────────────────────────────────────

@interface MPCalendarEditor () <UITextFieldDelegate>
@end

@implementation MPCalendarEditor {
    EKEvent *_event;                // nil → новое событие
    BOOL _isNew;
    UITextField *_titleField;
    MPCalStepper *_sDate[2], *_sHour[2], *_sMin[2];   // [0]=начало [1]=конец
    UILabel *_label[2];             // подписи «начало»/«конец»
    MPCalEditorToggle *_allDayToggle;
    UIView *_calMark;               // цвет-квадрат календаря
    UILabel *_calName;
    EKCalendar *_chosenCalendar;
    NSArray *_writable;
    NSDate *_start, *_end;
    BOOL _allDay;
    BOOL _saving;                   // guard двойного тапа «сохранить»
}

+ (MPCalendarEditor *)sharedEditor {
    static MPCalendarEditor *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[MPCalendarEditor alloc] initWithFrame:CGRectZero];
    });
    return s;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.hidden = YES;
        self.alpha = 0.0;
    }
    return self;
}

- (void)presentInPivot:(MPCalendarPivotView *)pivot event:(EKEvent *)event {
    @try {
        // уже открыт — повторный present пересобирал бы редактор под пальцем
        if (self.superview != nil && !self.hidden) return;
        _saving = NO;
        _event = event;
        _isNew = (event == nil);
        [self buildContentInFrame:pivot.bounds];
        self.frame = pivot.bounds;
        [pivot addSubview:self];
        // ГРАБЛЯ: hidden снимаем ДО alpha-анимации, иначе редактор «не открылся»
        self.hidden = NO;
        [UIView animateWithDuration:0.2f animations:^{
            self.alpha = 1.0;
        }];
        MPLog(@"[Calendar] редактор: %@ события", _isNew ? @"новое" : @"правка");
    }
    @catch (NSException *e) {
        MPLog(@"[Calendar] !! редактор: %@ — %@", e.name, e.reason);
    }
}

- (void)dismiss {
    [UIView animateWithDuration:0.15f animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
        [self removeFromSuperview];
    }];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Сборка содержимого

- (void)buildContentInFrame:(CGRect)bounds {
    for (UIView *v in [self.subviews copy]) [v removeFromSuperview];

    MPCalendarData *d = [MPCalendarData sharedData];

    // стартовые значения
    if (_isNew) {
        // новое событие: ближайший целый час, длительность час
        NSDate *now = [NSDate date];
        NSDateComponents *c = [d.cal components:NSHourCalendarUnit | NSMinuteCalendarUnit
                                        fromDate:now];
        _start = [now dateByAddingTimeInterval:-60.0 * c.minute];
        _end = [_start dateByAddingTimeInterval:3600.0];
        _allDay = NO;
        _writable = [d writableCalendars];
        _chosenCalendar = _writable.count > 0 ? _writable[0]
                         : [d.store defaultCalendarForNewEvents];
    } else {
        _start = _event.startDate;
        _end = _event.endDate;
        _allDay = _event.allDay;
        _chosenCalendar = _event.calendar;
        _writable = [d writableCalendars];
    }

    CGFloat top = [MPMetroStyle statusBarInset];
    CGFloat y = top;

    // шапка «событие» light 52 (ужатие как в шапке «Настроек»)
    NSString *head = @"событие";
    UIFont *hf = nil;
    CGFloat size = 52.0f;
    for (; size >= 30.0f; size -= 2.0f) {
        hf = [MPMetroStyle lightFont:size];
        if ([head sizeWithFont:hf].width <= bounds.size.width - MPCalLead * 2.0f) break;
    }
    UILabel *headL = [[UILabel alloc] initWithFrame:CGRectMake(MPCalLead, y + 24.0f,
                                                               bounds.size.width - 2 * MPCalLead, 66.0f)];
    headL.font = hf;
    headL.textColor = [UIColor whiteColor];
    headL.backgroundColor = [UIColor clearColor];
    headL.text = head;
    [self addSubview:headL];
    y += MPCalHeaderH;   // 96

    // название
    _titleField = [[UITextField alloc] initWithFrame:CGRectMake(MPCalLead, y + 4.0f,
                                                                288.0f, 40.0f)];
    _titleField.font = [MPMetroStyle lightFont:24.0f];
    _titleField.textColor = [UIColor whiteColor];
    _titleField.backgroundColor = [UIColor clearColor];
    _titleField.placeholder = @"название";
    _titleField.keyboardAppearance = UIKeyboardAppearanceAlert;
    _titleField.autocorrectionType = UITextAutocorrectionTypeNo;
    _titleField.delegate = self;
    _titleField.text = _isNew ? @"" : _event.title;
    [self addSubview:_titleField];
    y += 52.0f;

    // пикеры начала/конца: подпись muted 13 + строка «дата час минуты»
    NSString *labels[2] = {@"начало", @"конец"};
    for (NSInteger i = 0; i < 2; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(MPCalLead, y, 120.0f, 16.0f)];
        l.font = [MPMetroStyle regularFont:13.0f];
        l.textColor = [MPCalendarTheme mutedColor];
        l.backgroundColor = [UIColor clearColor];
        l.text = labels[i];
        [self addSubview:l];
        _label[i] = l;
        y += 18.0f;

        _sDate[i] = [[MPCalStepper alloc] initWithFrame:CGRectMake(MPCalLead, y, 132.0f, 36.0f) kind:0];
        _sHour[i] = [[MPCalStepper alloc] initWithFrame:CGRectMake(MPCalLead + 140.0f, y, 60.0f, 36.0f) kind:1];
        _sMin[i] = [[MPCalStepper alloc] initWithFrame:CGRectMake(MPCalLead + 208.0f, y, 80.0f, 36.0f) kind:2];
        __weak MPCalendarEditor *wSelf = self;
        void (^ch)(void) = ^{ [wSelf stepperChanged]; };
        _sDate[i].onChange = ch;
        _sHour[i].onChange = ch;
        _sMin[i].onChange = ch;
        [self addSubview:_sDate[i]];
        [self addSubview:_sHour[i]];
        [self addSubview:_sMin[i]];
        y += 46.0f;
    }

    // «весь день» + тумблер
    UILabel *adL = [[UILabel alloc] initWithFrame:CGRectMake(MPCalLead, y + 6.0f, 200.0f, 30.0f)];
    adL.font = [MPMetroStyle lightFont:24.0f];
    adL.textColor = [UIColor whiteColor];
    adL.backgroundColor = [UIColor clearColor];
    adL.text = @"весь день";
    [self addSubview:adL];
    __weak MPCalendarEditor *wSelf = self;
    _allDayToggle = [[MPCalEditorToggle alloc] initWithFrame:CGRectMake(258.0f, y + 10.0f, 46.0f, 22.0f)
                                                           on:_allDay
                                                        change:^(BOOL on) {
        [wSelf allDayChanged:on];
    }];
    [self addSubview:_allDayToggle];
    y += 52.0f;

    // календарь: цвет-квадрат + имя; тап циклично переключает
    UIControl *calRow = [[UIControl alloc] initWithFrame:CGRectMake(0.0f, y, 320.0f, 56.0f)];
    _calMark = [[UIView alloc] initWithFrame:CGRectMake(MPCalLead + 2.0f, 24.0f, 8.0f, 8.0f)];
    _calMark.backgroundColor = [d colorForCalendar:_chosenCalendar];
    [calRow addSubview:_calMark];
    _calName = [[UILabel alloc] initWithFrame:CGRectMake(36.0f, 7.0f, 268.0f, 30.0f)];
    _calName.font = [MPMetroStyle lightFont:24.0f];
    _calName.textColor = [UIColor whiteColor];
    _calName.backgroundColor = [UIColor clearColor];
    _calName.text = _chosenCalendar.title ?: @"календарь";
    [calRow addSubview:_calName];
    UILabel *calSub = [[UILabel alloc] initWithFrame:CGRectMake(36.0f, 32.0f, 268.0f, 18.0f)];
    calSub.font = [MPMetroStyle regularFont:13.0f];
    calSub.textColor = [MPCalendarTheme mutedColor];
    calSub.backgroundColor = [UIColor clearColor];
    calSub.text = @"календарь";
    [calRow addSubview:calSub];
    [calRow addTarget:self action:@selector(calendarTapped)
     forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:calRow];
    y += 60.0f;

    // действия: сохранить (акцент) / отмена (muted) / удалить (красный)
    UIButton *save = [MPCalendarTheme bigTextAction:@"сохранить" secondary:NO];
    save.frame = CGRectMake(MPCalLead, y, 140.0f, 36.0f);
    [save addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:save];
    UIButton *cancel = [MPCalendarTheme bigTextAction:@"отмена" secondary:YES];
    cancel.frame = CGRectMake(MPCalLead + 150.0f, y, 120.0f, 36.0f);
    [cancel addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:cancel];
    if (!_isNew) {
        UIButton *del = [UIButton buttonWithType:UIButtonTypeCustom];
        del.frame = CGRectMake(MPCalLead, y + 40.0f, 140.0f, 36.0f);
        del.titleLabel.font = [MPMetroStyle lightFont:24.0f];
        [del setTitle:@"удалить" forState:UIControlStateNormal];
        [del setTitleColor:[MPCalendarTheme dangerColor] forState:UIControlStateNormal];
        [del setTitleColor:[MPCalendarTheme mutedColor] forState:UIControlStateHighlighted];
        [del addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:del];
    }

    // тап по фону закрывает клавиатуру
    UITapGestureRecognizer *bg = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(bgTapped)];
    bg.cancelsTouchesInView = NO;
    [self addGestureRecognizer:bg];

    [self refreshSteppers];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Значения

- (void)refreshSteppers {
    _sDate[0].dateValue = _start;
    _sHour[0].dateValue = _start;
    _sMin[0].dateValue = _start;
    _sDate[1].dateValue = _end;
    _sHour[1].dateValue = _end;
    _sMin[1].dateValue = _end;
    BOOL time = !_allDay;
    _sHour[0].hidden = !time;
    _sMin[0].hidden = !time;
    _sHour[1].hidden = !time;
    _sMin[1].hidden = !time;
}

// шаг любого степпера: пересобираем _start/_end из колонок
// (день — из колонки даты, время — из колонок часа/минуты)
- (void)stepperChanged {
    _start = [self assembleFromDay:_sDate[0].dateValue
                              hour:_sHour[0].dateValue
                              minute:_sMin[0].dateValue
                             anchor:_start];
    _end = [self assembleFromDay:_sDate[1].dateValue
                            hour:_sHour[1].dateValue
                            minute:_sMin[1].dateValue
                           anchor:_end];
    if ([_end compare:_start] != NSOrderedDescending) {
        _end = [_start dateByAddingTimeInterval:900.0];   // минимум 15 минут
    }
    [self refreshSteppers];
}

- (NSDate *)assembleFromDay:(NSDate *)dayD hour:(NSDate *)hourD minute:(NSDate *)minD
                    anchor:(NSDate *)anchor {
    MPCalendarData *d = [MPCalendarData sharedData];
    NSDateComponents *cd = [d.cal components:NSYearCalendarUnit | NSMonthCalendarUnit
                                           | NSDayCalendarUnit fromDate:dayD];
    NSDateComponents *ch = [d.cal components:NSHourCalendarUnit fromDate:hourD ?: anchor];
    NSDateComponents *cm = [d.cal components:NSMinuteCalendarUnit fromDate:minD ?: anchor];
    NSDateComponents *res = [[NSDateComponents alloc] init];
    res.year = cd.year;
    res.month = cd.month;
    res.day = cd.day;
    res.hour = ch.hour;
    res.minute = (cm.minute / 5) * 5;   // минута шагом 5
    return [d.cal dateFromComponents:res];
}

- (void)allDayChanged:(BOOL)on {
    _allDay = on;
    [self refreshSteppers];
}

- (void)calendarTapped {
    if (_writable.count < 2) return;
    NSUInteger idx = [_writable indexOfObject:_chosenCalendar];
    if (idx == NSNotFound) idx = 0;
    _chosenCalendar = _writable[(idx + 1) % _writable.count];
    _calMark.backgroundColor = [[MPCalendarData sharedData] colorForCalendar:_chosenCalendar];
    _calName.text = _chosenCalendar.title ?: @"календарь";
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Действия

- (void)saveTapped {
    if (_saving) return;   // двойной тап до dismiss успевал создать два события
    _saving = YES;
    // «весь день» — границы суток, а не время суток (иначе событие ложится
    // на чужие часы и растягивается в повестке)
    if (_allDay) {
        MPCalendarData *d = [MPCalendarData sharedData];
        _start = [d startOfDayForDate:_start];
        _end = [d startOfDayForDate:_end];
        if ([_end compare:_start] != NSOrderedDescending) {
            _end = [d dayStartByAddingDays:1 toDayStart:_start];   // одни сутки
        }
    } else if ([_end compare:_start] != NSOrderedDescending) {
        // снятие тумблера с аллдей-события даёт start == end (обе полночи) —
        // EKEventStore такое отклоняет; кламп как в stepperChanged
        _end = [_start dateByAddingTimeInterval:900.0];
    }
    [[MPCalendarData sharedData] store];   // прогрев
    EKEvent *ev = _isNew
        ? [EKEvent eventWithEventStore:[MPCalendarData sharedData].store]
        : _event;
    ev.title = _titleField.text ?: @"";
    ev.startDate = _start;
    ev.endDate = _end;
    ev.allDay = _allDay;
    if (_chosenCalendar != nil) ev.calendar = _chosenCalendar;
    [[MPCalendarData sharedData] saveEvent:ev];
    MPLog(@"[Calendar] событие сохранено: «%@» %@ — %@", ev.title, ev.startDate, ev.endDate);
    [self dismiss];
}

- (void)cancelTapped {
    if (_saving) return;   // повторный тап не перезапускает dismiss-анимацию
    [self dismiss];
}

- (void)deleteTapped {
    if (_saving) return;   // «удалить» во время сохранения удалял бы свежесохранённое
    if (!_isNew && _event != nil) {
        [[MPCalendarData sharedData] deleteEvent:_event];
        MPLog(@"[Calendar] событие удалено");
    }
    [self dismiss];
}

- (void)bgTapped {
    [_titleField resignFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

@end
