// MPCalendarPages — четыре страницы pivot-календаря: месяц / неделя / день /
// повестка. Все страницы — вертикальные UIScrollView (горизонталь забирает
// pivot, как в «Часах»). Секции-месяцы/недели рисуются напрямую (drawRect) —
// на iPhone 4 тысячи кнопок-ячеек недопустимы; тапы различаются по координате.

#import <UIKit/UIKit.h>
#import "MPCalendarData.h"

@interface MPCalendarBasePage : UIScrollView
// позиция ленты (начало месяца / недели / суток; у повестки — сегодня)
@property (nonatomic, retain) NSDate *anchorDate;
// пересобрать содержимое из данных (вызывает pivot)
- (void)reload;
// раз в ~30 с из pivot: линия «сейчас» в дне/неделе
- (void)tick;
// прыжок ленты к дате (переход из месяца/недели)
- (void)gotoDayStart:(NSDate *)dayStart animated:(BOOL)animated;
// кнопка «сегодня» в шапке
- (void)scrollToTodayAnimated:(BOOL)animated;
// колбэки в pivot
@property (nonatomic, copy) void (^onSelectDate)(NSDate *dayStart);
@property (nonatomic, copy) void (^onSelectEvent)(MPCalendarEvent *event);
@end

@interface MPCalendarMonthPage : MPCalendarBasePage   // стр. 0 — сетка месяцев
@end
@interface MPCalendarWeekPage : MPCalendarBasePage    // стр. 1 — лента недель
@end
@interface MPCalendarDayPage : MPCalendarBasePage     // стр. 2 — часовая лента
@end
@interface MPCalendarAgendaPage : MPCalendarBasePage  // стр. 3 — повестка
@end
