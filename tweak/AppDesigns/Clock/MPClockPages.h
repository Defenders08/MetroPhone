// MPClockPages — четыре страницы pivot-часов (мировые, будильник, секундомер,
// таймер) по утверждённому HTML-прототипу. Все страницы — вертикальные
// UIScrollView: горизонтальный свайп перехватывает pivot, вертикаль остаётся им.

#import <UIKit/UIKit.h>

@interface MPClockBasePage : UIScrollView
// пересобрать содержимое из данных (города/будильники)
- (void)reload;
// обновить цифры времени (зывается раз в секунду из pivot)
- (void)tick;
// режим правки: у строк появляются кнопки удаления «×»
@property (nonatomic, assign, getter=isEditingMode) BOOL editingMode;
- (void)setEditingModeAnimated:(BOOL)on;
@end

// WP-тумблер (серый прямоугольник + белый квадратный бегунок, 51×31) — общий
// для страниц и редактора; реализация в MPClockPages.m
@interface MPWPToggle : UIView
@property (nonatomic, assign) BOOL on;
@property (nonatomic, copy) void (^onChange)(BOOL on);
- (id)initWithFrame:(CGRect)frame on:(BOOL)on change:(void (^)(BOOL))change;
@end

@interface MPClockWorldPage : MPClockBasePage
@end

@interface MPClockAlarmPage : MPClockBasePage
@end

// у страниц 2–3 шапочные пары дублируют страничные кнопки; состояние
// (Старт↔Стоп/Пауза, Круг↔Сброс) отдаётся колбэком для заголовков шапки
@interface MPClockStopwatchPage : MPClockBasePage
@property (nonatomic, copy) void (^mpOnStateChange)(BOOL running, BOOL hasAcc);
- (void)lapTapped;
- (void)goTapped;
@end

@interface MPClockTimerPage : MPClockBasePage
@property (nonatomic, copy) void (^mpOnStateChange)(BOOL running);
- (void)goTapped;
- (void)resetTapped;
// идёт ли отсчёт (для видимости квадратного прогресса в pivot)
- (BOOL)running;
// прогресс отсчёта 0..1 (остаток/общее) — для квадратного индикатора в pivot
- (CGFloat)progress;
@end
