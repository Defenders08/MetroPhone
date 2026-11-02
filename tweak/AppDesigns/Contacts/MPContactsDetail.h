// MPContactsDetail — WP-экран контакта: оверлей на КОРНЕ пивота, не в ленте
// страниц (иначе уедет вместе со свайпом — грабля редактора «Календаря»).
// Имя, круг-аватар, действия позвонить/смс/почта, избранное, список полей.
// «Изменить» отдаёт контакт нативному редактору (пивот прячет Hooks).

#import <UIKit/UIKit.h>
#import "MPContactsData.h"

@interface MPContactsDetail : UIView

+ (MPContactsDetail *)sharedDetail;

// Показать контакт (person — обёртка из данных). Повторный вызов при открытом
// экране игнорируется (guard двойного present — как в редакторе Календаря).
- (void)presentInPivot:(UIView *)pivot person:(MPContactsPerson *)person;

// «Изменить» → нативный редактор (реализует Hooks)
@property (nonatomic, copy) void (^onEdit)(MPContactsPerson *person);

@end
