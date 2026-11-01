// MPClockPivotView — контейнер WP-pivot «Часов»: 4 страницы (Мировые часы /
// Будильник / Секундомер / Таймер), лента заголовков с лерп-слотами, пары
// текстовых действий под своими заголовками (страницы 0–1). Листание —
// системный UIScrollView с pagingEnabled (план E): contentOffset единственный
// источник правды, позиции страниц руками не трогаются.

#import <UIKit/UIKit.h>

@interface MPClockPivotView : UIView

// Создать и показать в корневом таб-баре MobileTimer (спрятать нативный UI).
// Повторный вызов — просто возвращает уже живую вьюху.
+ (MPClockPivotView *)installedPivotInView:(UIView *)host;

// Перечитать данные всех страниц (города/будильники)
- (void)reloadData;

// Раз в секунду (мировые часы)
- (void)clockTick;

@end
