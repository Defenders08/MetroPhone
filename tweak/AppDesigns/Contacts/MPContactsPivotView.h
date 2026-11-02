// MPContactsPivotView — контейнер WP-pivot «Контактов»: 2 страницы (все /
// избранное), лента заголовков с лерп-слотами и строка действий («добавить»
// у «всех»). Механика — «Часы»/«Календарь» план E: листание ведёт системный
// UIScrollView с pagingEnabled, contentOffset — единственный источник правды.

#import <UIKit/UIKit.h>

@interface MPContactsPivotView : UIView

// Создать и показать поверх нативного UI Контактов. Повторный вызов возвращает
// уже живую вьюху (идемпотентно).
+ (MPContactsPivotView *)installedPivotInView:(UIView *)host;

// Перечитать данные страниц (изменение адресной книги / избранного)
- (void)reloadData;

// Нативный редактор поверх: пивот убирается и возвращается (Hooks)
- (void)hideForNativeEditor;
- (void)showAfterNativeEditor;
// Сейчас открыт нативный редактор (пивот спрятан) — не мешаем ему
- (BOOL)isCoveringEditor;

// Программный переход на страницу 0..1 (0 = «все»)
- (void)gotoPage:(NSInteger)page animated:(BOOL)animated;

@end

// C-функции нативного редактора (реализованы в MPContactsHooks.xm).
// extern "C" обязателен: Hooks.xm — Objective-C++, без него имена манглятся.
#ifdef __cplusplus
extern "C" {
#endif
void MPContactsPresentNativeEditor(NSInteger recordID);
BOOL MPContactsEditorCovering(void);
#ifdef __cplusplus
}
#endif
