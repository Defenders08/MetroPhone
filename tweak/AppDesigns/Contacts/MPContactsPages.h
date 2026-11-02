// MPContactsPages — страницы pivot-контактов: «все» и «избранное». Обе —
// вертикальные UIScrollView (горизонталь забирает pivot, как в «Часах»).
// Секции-буквы рисуются напрямую (drawRect) — на iPhone 4 тысячи кнопок-ячеек
// недопустимы; тап по строке различается по координате.

#import <UIKit/UIKit.h>
#import "MPContactsData.h"

@interface MPContactsBasePage : UIScrollView
// пересобрать содержимое из данных (вызывает pivot)
- (void)reload;
// тап по строке → экран контакта
@property (nonatomic, copy) void (^onSelectPerson)(MPContactsPerson *person);
// поисковый запрос — задаёт пивот (полоса поиска живёт на пивоте, не здесь)
@property (nonatomic, copy) NSString *query;
@end

@interface MPContactsAllPage : MPContactsBasePage    // стр. 0 — все + поиск
@end
@interface MPContactsFavPage : MPContactsBasePage    // стр. 1 — избранное
@end
