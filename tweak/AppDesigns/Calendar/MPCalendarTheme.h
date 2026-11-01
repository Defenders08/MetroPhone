// MPCalendarTheme — метрики и цвета переоформления «Календаря»
// (com.apple.mobilecal) в WP-pivot. Геометрия скопирована с «Часов»
// (E3-ШАПКА-WP): та же шапка 96, строка действий на 96, контент с 166.

#import <UIKit/UIKit.h>

// Геометрия pivot — единая с «Часами» (система дизайна «Настроек»)
#define MPCalLead         16.0f   // левое поле: заголовки, действия, контент
#define MPCalStride       320.0f  // вкладка = весь экран
#define MPCalHeaderH      96.0f   // шапка: light 52 на y=24
#define MPCalActionsH     30.0f   // строка действий на y=96
#define MPCalHeaderBottom 126.0f  // низ шапки (96+30)
#define MPCalTopGap       20.0f   // зазор кнопки → контент
#define MPCalHeaderGap    24.0f   // зазор между заголовками в ленте
#define MPCalActionsGap   14.0f   // шаг кнопок в строке действий
#define MPCalPivotTag     0x4D50436C   // 'MPCl' — маркер нашей вьюхи

// Страница «Месяц»
#define MPCalMonthTitleH  56.0f   // полоса «октябрь 2026»: текст на y=8, воздух до дней недели
#define MPCalWeekdaysH    24.0f   // строка «пн … вс»
#define MPCalMonthCellH   44.0f   // высота строки сетки 7×6
#define MPCalMonthTail    14.0f   // воздух после сетки — до заголовка следующего месяца

// Страница «Неделя»
#define MPCalWeekHourH    44.0f   // высота часа в сетке недели
#define MPCalWeekDateH    36.0f   // строка дат над сеткой

// Страница «День»
#define MPCalDayHourH     48.0f   // высота часа в ленте дня
#define MPCalDayLeft      52.0f   // левая колонка меток часов
#define MPCalDayHeaderH   84.0f   // блок даты сверху (thin 60 + подписи)

// Страница «Повестка» (строка события = канон проекта)
#define MPCalAgendaRowH   56.0f   // строка 56: light 24 + regular 13

@interface MPCalendarTheme : NSObject

// Kill-switch: ключ calendarRestyle (домен ru.ash.metrophone), по умолчанию YES
+ (BOOL)restyleEnabled;

// Палитра «Настроек» (та же лестница, что в «Часах»)
+ (UIColor *)mutedColor;          // белый 0.6 — подписи, значения
+ (UIColor *)faintColor;          // белый 0.26 — неактивные заголовки pivot
+ (UIColor *)disabledColor;       // белый 0.40 — выключенное
+ (UIColor *)placeholderColor;    // белый 0.30 — плейсхолдер поля имени
+ (UIColor *)dangerColor;         // #E51400 — «удалить»

// Плоская текстовая кнопка-действие шапки: light 24, белый
+ (UIButton *)actionButtonWithTitle:(NSString *)title;

// Крупная текстовая кнопка (акцент/вторичная muted): light 24
+ (UIButton *)bigTextAction:(NSString *)title secondary:(BOOL)secondary;

@end
