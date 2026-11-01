// MPCalendarData — слой данных «Календаря»: EventKit (EKEventStore) + кэш
// событий по дням + симвoлы локали (месяцы/дни) для заголовков страниц.
// iOS 6: системное приложение MobileCal имеет полный доступ к событиям без
// запроса; хранилище одно на процесс (sharedData).

#import <UIKit/UIKit.h>
#import <EventKit/EventKit.h>

// Лёгкая обёртка события: то, что нужно страницам (полный EKEvent держим
// для редактора)
@interface MPCalendarEvent : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, retain) NSDate *start;
@property (nonatomic, retain) NSDate *end;
@property (nonatomic, assign) BOOL allDay;
@property (nonatomic, retain) UIColor *color;      // плоский цвет календаря
@property (nonatomic, retain) NSString *calendarTitle;
@property (nonatomic, copy) NSString *eventIdentifier;
@property (nonatomic, retain) EKEvent *sourceEvent;   // для редактора
+ (MPCalendarEvent *)eventFromEKEvent:(EKEvent *)ev color:(UIColor *)color;
- (NSString *)timeSpanString;                      // «14:00 – 15:30»
@end

// Постится после изменения хранилища (EKEventStoreChanged) и после сохранения
// из редактора — страницы перечитывают содержимое
extern NSString * const MPCalendarDataDidChangeNotification;

@interface MPCalendarData : NSObject

+ (MPCalendarData *)sharedData;

// События дня (dayStart = начало суток из startOfDayForDate:); при промахе
// кэша дозагружается только недостающий кусок диапазона. Сортировка: весь
// день, затем по началу.
- (NSArray *)eventsForDayStart:(NSDate *)dayStart;
- (BOOL)dayHasEvents:(NSDate *)dayStart;
// Один фетч на rebuild страницы: гарантирует покрытие диапазона (начала
// суток), дозагружая только недостающие слева/справа куски
- (void)ensureEventsFrom:(NSDate *)start to:(NSDate *)end;

// Прямой доступ для редактора
- (EKEventStore *)store;
- (NSArray *)writableCalendars;                // календари, доступные для записи
- (UIColor *)colorForCalendar:(EKCalendar *)cal;
- (EKCalendar *)calendarForIdentifier:(NSString *)identifier;

// Сохранение/удаление (после — invalidate и уведомление страниц)
- (void)saveEvent:(EKEvent *)event;
- (void)deleteEvent:(EKEvent *)event;
- (void)invalidateCache;                       // + пост MPCalendarDataDidChange
// Растёт при каждом invalidate — страницы сравнивают его, чтобы не
// пересобираться зря при viewDidAppear/активации без изменений данных
@property (nonatomic, readonly) NSUInteger dataGeneration;

// Календарь и арифметика дней (DST-безопасно через NSCalendar)
@property (nonatomic, readonly) NSCalendar *cal;
- (NSDate *)startOfDayForDate:(NSDate *)date;
- (NSDate *)todayStart;
- (NSDate *)dayStartByAddingDays:(NSInteger)days toDayStart:(NSDate *)dayStart;
- (NSDate *)firstDayOfMonthForDayStart:(NSDate *)dayStart;
- (NSDate *)firstDayOfWeekForDayStart:(NSDate *)dayStart;
- (NSInteger)numberOfDaysInMonthContainingDayStart:(NSDate *)dayStart;
@property (nonatomic, readonly) NSInteger firstWeekday;   // 1=вс … 2=пн (по локали)
- (BOOL)dayStartIsToday:(NSDate *)dayStart;
- (BOOL)dayStartIsTomorrow:(NSDate *)dayStart;

// Символы локали (именительный падеж: «октябрь», «среда», «пн»)
- (NSString *)standaloneMonthName:(NSInteger)month;   // 1..12
- (NSString *)weekdayName:(NSInteger)weekday;         // 1=вс … 7=сб
- (NSString *)shortWeekdayName:(NSInteger)weekday;    // «пн»

// Заголовок секции повестки: «сегодня» / «завтра» / «среда, 4 ноября»
- (NSString *)agendaTitleForDayStart:(NSDate *)dayStart;
// Короткое время «14:00» (по локали устройства)
- (NSString *)timeStringFromDate:(NSDate *)date;
// «31 октября» / «1 ноября» для пикера дат редактора
- (NSString *)dayMonthStringForDate:(NSDate *)date;

@end
