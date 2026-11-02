// MPContactsNewEditor — свой WP-редактор создания контакта (вместо нативного
// ABNewPersonViewController): оверлей на КОРНЕ пивота, не в ленте страниц
// (иначе уедет со свайпом — грабля редактора «Календаря»). Шапка light 52,
// поля light 24, «сохранить» акцентом, «отмена» muted.

#import <UIKit/UIKit.h>
#import "MPContactsData.h"

@interface MPContactsNewEditor : UIView

+ (MPContactsNewEditor *)sharedEditor;

// Показать форму (повторный вызов при открытом редакторе игнорируется).
// onSuccess — после записи контакта (пивот перечитает данные сам через
// MPContactsDataDidChange).
- (void)presentInPivot:(UIView *)pivot onSuccess:(void (^)(void))onSuccess;

@end
