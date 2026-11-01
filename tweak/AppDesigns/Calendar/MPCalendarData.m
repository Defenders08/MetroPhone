#import "MPCalendarData.h"
#import "MetroLauncher/MPMetroStyle.h"

NSString * const MPCalendarDataDidChangeNotification = @"MPCalendarDataDidChange";

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - MPCalendarEvent

@implementation MPCalendarEvent

+ (MPCalendarEvent *)eventFromEKEvent:(EKEvent *)ev color:(UIColor *)color {
    MPCalendarEvent *e = [[MPCalendarEvent alloc] init];
    e.title = ev.title ?: @"";
    e.start = ev.startDate;
    e.end = ev.endDate;
    e.allDay = ev.allDay;
    e.color = color;
    e.calendarTitle = ev.calendar.title ?: @"";
    e.eventIdentifier = ev.eventIdentifier;
    e.sourceEvent = ev;
    return e;
}

- (NSString *)timeSpanString {
    // NSDateFormatter дорогой — один статический (все вызовы с main-потока)
    static NSDateFormatter *df = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [[NSDateFormatter alloc] init];
        [df setDateStyle:NSDateFormatterNoStyle];
        [df setTimeStyle:NSDateFormatterShortStyle];
    });
    return [NSString stringWithFormat:@"%@ – %@", [df stringFromDate:self.start],
                                               [df stringFromDate:self.end]];
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - MPCalendarData

@interface MPCalendarData () {
    EKEventStore *_store;
    NSMutableDictionary *_eventsByDay;   // dayStart → NSArray<MPCalendarEvent>
    NSDate *_fetchedStart, *_fetchedEnd; // покрытый диапазон (границы включительно)
    NSMutableDictionary *_colorByCalendarID;
    NSDateFormatter *_timeFormatter;
    NSCalendar *_cal;                    // один календарь вместо нового на вызов
    NSUInteger _dataGeneration;          // растёт при invalidate — см. dataGeneration
    NSArray *_monthSymbols, *_standaloneMonthSymbols, *_weekdaySymbols, *_shortWeekdaySymbols;
}
- (void)storeChanged:(NSNotification *)n;
- (void)timeZoneChanged:(NSNotification *)n;
- (void)loadRange:(NSDate *)start end:(NSDate *)end;
@end

@implementation MPCalendarData

+ (MPCalendarData *)sharedData {
    static MPCalendarData *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[MPCalendarData alloc] init];
    });
    return s;
}

- (id)init {
    self = [super init];
    if (self) {
        _store = [[EKEventStore alloc] init];
        _eventsByDay = [[NSMutableDictionary alloc] init];
        _colorByCalendarID = [[NSMutableDictionary alloc] init];
        _cal = [[NSCalendar currentCalendar] copy];
        // символы локали неизменны в рамках процесса — читаем один раз
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        _monthSymbols = [df.monthSymbols copy];
        _standaloneMonthSymbols = [df.standaloneMonthSymbols copy];
        _weekdaySymbols = [df.weekdaySymbols copy];
        _shortWeekdaySymbols = [df.shortStandaloneWeekdaySymbols copy];
        // Первое чтение EventKit в iOS 6 у сторонних приложений показывает
        // системный запрос доступа; MobileCal — системное приложение, доступ
        // уже выдан, запроса не будет. Если селектор есть — прогреваем его
        // с пустым колбэком (безопасно и для будущего).
        if ([_store respondsToSelector:@selector(requestAccessToEntityType:completion:)]) {
            [_store requestAccessToEntityType:EKEntityTypeEvent
                                   completion:^(BOOL granted, NSError *err) {}];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(storeChanged:)
                                                     name:EKEventStoreChangedNotification
                                                   object:_store];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(timeZoneChanged:)
                                                     name:NSSystemTimeZoneDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)storeChanged:(NSNotification *)n {
    // EKEventStoreChanged часто приходит с фонового потока — кэш мутируем и
    // UIKit-обработчиков дергаем только с main
    dispatch_async(dispatch_get_main_queue(), ^{
        MPLog(@"[Calendar] хранилище изменилось — кэш сброшен");
        [self invalidateCache];
    });
}

- (void)timeZoneChanged:(NSNotification *)n {
    // ключи кэша — полуночи в старой зоне; после смены зоны (перелёт)
    // данные надо перечитать, и _cal подменять только с main
    dispatch_async(dispatch_get_main_queue(), ^{
        _cal = [[NSCalendar currentCalendar] copy];
        [self invalidateCache];
    });
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Кэш по дням

- (NSCalendar *)cal {
    return _cal;
}

- (NSDate *)startOfDayForDate:(NSDate *)date {
    NSDate *start = nil;
    NSTimeInterval dur = 0.0;
    [[self cal] rangeOfUnit:NSDayCalendarUnit startDate:&start
                    interval:&dur forDate:date];
    return start;
}

- (NSDate *)todayStart {
    return [self startOfDayForDate:[NSDate date]];
}

- (NSDate *)dayStartByAddingDays:(NSInteger)days toDayStart:(NSDate *)dayStart {
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.day = days;
    return [[self cal] dateByAddingComponents:c toDate:dayStart options:0];
}

- (NSDate *)firstDayOfMonthForDayStart:(NSDate *)dayStart {
    NSDateComponents *c = [[self cal] components:NSYearCalendarUnit | NSMonthCalendarUnit
                                         fromDate:dayStart];
    c.day = 1;
    return [[self cal] dateFromComponents:c];
}

- (NSDate *)firstDayOfWeekForDayStart:(NSDate *)dayStart {
    NSDateComponents *c = [[self cal] components:NSWeekdayCalendarUnit fromDate:dayStart];
    NSInteger back = (c.weekday - self.firstWeekday + 7) % 7;
    return [self dayStartByAddingDays:-back toDayStart:dayStart];
}

- (NSInteger)numberOfDaysInMonthContainingDayStart:(NSDate *)dayStart {
    NSRange r = [[self cal] rangeOfUnit:NSDayCalendarUnit
                                inUnit:NSMonthCalendarUnit forDate:dayStart];
    return r.length;
}

- (NSInteger)firstWeekday {
    return [[self cal] firstWeekday];
}

- (BOOL)dayStartIsToday:(NSDate *)dayStart {
    return [dayStart isEqualToDate:[self todayStart]];
}

- (BOOL)dayStartIsTomorrow:(NSDate *)dayStart {
    NSDate *tom = [self dayStartByAddingDays:1 toDayStart:[self todayStart]];
    return [dayStart isEqualToDate:tom];
}

- (NSArray *)eventsForDayStart:(NSDate *)dayStart {
    // при промахе кэша дозагружаем ТОЛЬКО недостающий кусок диапазона —
    // полный рефетч накопленного диапазона на каждый промах давал O(n²)
    if (_fetchedStart == nil) {
        NSDate *from = [self dayStartByAddingDays:-45 toDayStart:dayStart];
        NSDate *to = [self dayStartByAddingDays:45 toDayStart:dayStart];
        [self loadRange:from end:to];
        _fetchedStart = from;
        _fetchedEnd = to;
    } else if ([dayStart compare:_fetchedStart] == NSOrderedAscending) {
        NSDate *from = [self dayStartByAddingDays:-45 toDayStart:dayStart];
        NSDate *to = [self dayStartByAddingDays:-1 toDayStart:_fetchedStart];
        [self loadRange:from end:to];
        _fetchedStart = from;
    } else if ([dayStart compare:_fetchedEnd] == NSOrderedDescending) {
        NSDate *from = [self dayStartByAddingDays:1 toDayStart:_fetchedEnd];
        NSDate *to = [self dayStartByAddingDays:45 toDayStart:dayStart];
        [self loadRange:from end:to];
        _fetchedEnd = to;
    }
    return [_eventsByDay objectForKey:dayStart] ?: @[];
}

// Один фетч на rebuild страницы: гарантирует покрытие [start, end] (начала
// суток), дозагружая только недостающие слева/справа куски
- (void)ensureEventsFrom:(NSDate *)start to:(NSDate *)end {
    start = [self startOfDayForDate:start];
    end = [self startOfDayForDate:end];
    if (start == nil || end == nil || [start compare:end] == NSOrderedDescending) return;
    if (_fetchedStart != nil &&
        [start compare:_fetchedStart] != NSOrderedAscending &&
        [end compare:_fetchedEnd] != NSOrderedDescending) return;   // уже покрыто
    if (_fetchedStart == nil) {
        [self loadRange:start end:end];
        _fetchedStart = start;
        _fetchedEnd = end;
        return;
    }
    if ([start compare:_fetchedStart] == NSOrderedAscending) {
        NSDate *to = [self dayStartByAddingDays:-1 toDayStart:_fetchedStart];
        [self loadRange:start end:to];
        _fetchedStart = start;
    }
    if ([end compare:_fetchedEnd] == NSOrderedDescending) {
        NSDate *from = [self dayStartByAddingDays:1 toDayStart:_fetchedEnd];
        [self loadRange:from end:end];
        _fetchedEnd = end;
    }
}

- (BOOL)dayHasEvents:(NSDate *)dayStart {
    return [self eventsForDayStart:dayStart].count > 0;
}

// Загрузка диапазона [start, end] В КЭШ — границы покрытого диапазона ведут
// вызывающие (eventsForDayStart:/ensureEventsFrom:to:). Событие попадает во
// все покрываемые дни (многодневные размножаются, но КЛАМПЯТСЯ в диапазон —
// иначе событие на стыке дозагрузки задвоится в уже закэшированных днях).
- (void)loadRange:(NSDate *)start end:(NSDate *)end {
    @try {
        NSDate *dayAfterEnd = [self dayStartByAddingDays:1 toDayStart:end];
        NSPredicate *p = [_store predicateForEventsWithStartDate:start
                                                           endDate:dayAfterEnd
                                                         calendars:nil];
        NSArray *found = [_store eventsMatchingPredicate:p];
        NSMutableArray *touched = [NSMutableArray array];
        for (NSDate *d = start; [d compare:end] != NSOrderedDescending;
             d = [self dayStartByAddingDays:1 toDayStart:d]) {
            [_eventsByDay removeObjectForKey:d];
            [touched addObject:d];
        }
        for (EKEvent *ev in found) {
            UIColor *color = [self colorForCalendar:ev.calendar];
            MPCalendarEvent *wrap = [MPCalendarEvent eventFromEKEvent:ev color:color];
            NSDate *d = [self startOfDayForDate:ev.startDate];
            NSDate *last = [self startOfDayForDate:[ev.endDate dateByAddingTimeInterval:-1.0]];
            if ([last compare:d] == NSOrderedAscending) last = d;
            if ([d compare:start] == NSOrderedAscending) d = start;
            if ([last compare:end] == NSOrderedDescending) last = end;
            NSInteger guardCount = 0;
            while (guardCount++ < 400) {
                NSMutableArray *arr = [_eventsByDay objectForKey:d];
                if (arr == nil) {
                    arr = [NSMutableArray array];
                    [_eventsByDay setObject:arr forKey:d];
                }
                [arr addObject:wrap];
                if ([d isEqualToDate:last]) break;
                d = [self dayStartByAddingDays:1 toDayStart:d];
            }
        }
        // сортировка только затронутых дней (не всего кэша)
        for (NSDate *d in touched) {
            NSMutableArray *arr = [_eventsByDay objectForKey:d];
            if (arr.count > 1) {
                [arr sortUsingComparator:^NSComparisonResult(id a, id b) {
                    MPCalendarEvent *ea = a, *eb = b;
                    if (ea.allDay != eb.allDay) return ea.allDay ? NSOrderedAscending : NSOrderedDescending;
                    return [ea.start compare:eb.start];
                }];
            }
        }
        MPLog(@"[Calendar] кэш: %@ … %@ (%ld событий)", start, end, (long)found.count);
    }
    @catch (NSException *e) {
        MPLog(@"[Calendar] !! загрузка кэша: %@ — %@", e.name, e.reason);
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Календари и запись

- (EKEventStore *)store {
    return _store;
}

- (UIColor *)colorForCalendar:(EKCalendar *)cal {
    if (cal == nil) return [UIColor grayColor];
    NSString *key = cal.calendarIdentifier;
    UIColor *c = [_colorByCalendarID objectForKey:key];
    if (c != nil) return c;
    CGColorRef cg = [cal CGColor];
    c = cg ? [UIColor colorWithCGColor:cg] : [UIColor grayColor];
    [_colorByCalendarID setObject:c forKey:key];
    return c;
}

- (NSArray *)writableCalendars {
    NSMutableArray *res = [NSMutableArray array];
    for (EKCalendar *cal in [_store calendarsForEntityType:EKEntityTypeEvent]) {
        if ([cal allowsContentModifications]) [res addObject:cal];
    }
    return res;
}

- (EKCalendar *)calendarForIdentifier:(NSString *)identifier {
    for (EKCalendar *cal in [_store calendarsForEntityType:EKEntityTypeEvent]) {
        if ([cal.calendarIdentifier isEqualToString:identifier]) return cal;
    }
    return nil;
}

- (void)saveEvent:(EKEvent *)event {
    @try {
        NSError *err = nil;
        if (![_store saveEvent:event span:EKSpanThisEvent commit:YES error:&err]) {
            MPLog(@"[Calendar] !! сохранение: %@", err.localizedDescription);
        }
    }
    @catch (NSException *e) {
        MPLog(@"[Calendar] !! сохранение: %@ — %@", e.name, e.reason);
    }
    [self invalidateCache];
}

- (void)deleteEvent:(EKEvent *)event {
    @try {
        NSError *err = nil;
        if (![_store removeEvent:event span:EKSpanThisEvent commit:YES error:&err]) {
            MPLog(@"[Calendar] !! удаление: %@", err.localizedDescription);
        }
    }
    @catch (NSException *e) {
        MPLog(@"[Calendar] !! удаление: %@ — %@", e.name, e.reason);
    }
    [self invalidateCache];
}

- (void)invalidateCache {
    [_eventsByDay removeAllObjects];
    _fetchedStart = nil;
    _fetchedEnd = nil;
    _dataGeneration++;
    [[NSNotificationCenter defaultCenter] postNotificationName:MPCalendarDataDidChangeNotification
                                                        object:self];
}

- (NSUInteger)dataGeneration {
    return _dataGeneration;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Символы локали и строки

- (NSString *)standaloneMonthName:(NSInteger)month {
    if (month >= 1 && month <= (NSInteger)_standaloneMonthSymbols.count)
        return [_standaloneMonthSymbols objectAtIndex:month - 1];
    return @"";
}

- (NSString *)weekdayName:(NSInteger)weekday {
    if (weekday >= 1 && weekday <= (NSInteger)_weekdaySymbols.count)
        return [_weekdaySymbols objectAtIndex:weekday - 1];
    return @"";
}

- (NSString *)shortWeekdayName:(NSInteger)weekday {
    if (weekday >= 1 && weekday <= (NSInteger)_shortWeekdaySymbols.count)
        return [_shortWeekdaySymbols objectAtIndex:weekday - 1];
    return @"";
}

- (NSString *)agendaTitleForDayStart:(NSDate *)dayStart {
    if ([self dayStartIsToday:dayStart]) return @"сегодня";
    if ([self dayStartIsTomorrow:dayStart]) return @"завтра";
    NSDateComponents *c = [[self cal] components:NSWeekdayCalendarUnit | NSDayCalendarUnit
                                             | NSMonthCalendarUnit fromDate:dayStart];
    NSString *wd = [self weekdayName:c.weekday];
    NSString *mn = [self standaloneMonthName:c.month];
    return [NSString stringWithFormat:@"%@, %ld %@", wd, (long)c.day, mn];
}

- (NSString *)timeStringFromDate:(NSDate *)date {
    if (_timeFormatter == nil) {
        _timeFormatter = [[NSDateFormatter alloc] init];
        [_timeFormatter setDateStyle:NSDateFormatterNoStyle];
        [_timeFormatter setTimeStyle:NSDateFormatterShortStyle];
    }
    return [_timeFormatter stringFromDate:date];
}

- (NSString *)dayMonthStringForDate:(NSDate *)date {
    NSDateComponents *c = [[self cal] components:NSDayCalendarUnit | NSMonthCalendarUnit
                                         fromDate:date];
    // родительный падеж: «31 октября» (monthSymbols), не «31 Октябрь»
    if (c.month >= 1 && c.month <= (NSInteger)_monthSymbols.count) {
        return [NSString stringWithFormat:@"%ld %@", (long)c.day,
                [_monthSymbols objectAtIndex:c.month - 1]];
    }
    return @"";
}

@end
