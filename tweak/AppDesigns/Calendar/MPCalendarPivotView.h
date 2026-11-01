// MPCalendarPivotView — контейнер WP-pivot «Календаря»: 4 страницы (месяц /
// неделя / день / повестка), лента заголовков с лерп-слотами и строка действий
// («сегодня» / «добавить»). Механика — «Часы» план E: листание ведёт системный
// UIScrollView с pagingEnabled, contentOffset — единственный источник правды,
// бесконечность — скользящее окно из 4 слотов.

#import <UIKit/UIKit.h>

@interface MPCalendarPivotView : UIView

// Создать и показать поверх нативного UI MobileCal. Повторный вызов возвращает
// уже живую вьюху (идемпотентно).
+ (MPCalendarPivotView *)installedPivotInView:(UIView *)host;

// Перечитать данные всех страниц (вызывается при изменении хранилища)
- (void)reloadData;

// Обновление линии «сейчас» (раз в ~30 с)
- (void)clockTick;

// Программный переход на страницу 0..3 (0=месяц); date — необязательная дата
// для страниц-лент (переход «месяц → день» по тапу по дате)
- (void)gotoPage:(NSInteger)page date:(NSDate *)date animated:(BOOL)animated;

@end
