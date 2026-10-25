// MPSettingsCellStyler — переоформление ячеек «Настроек» после оригинальной
// отрисовки: плоский чёрный фон, белый Light-заголовок, серый подзаголовок,
// без иконок/шевронов/карточек. Логику ячейки не трогаем.

#import <UIKit/UIKit.h>

@class PSTableCell;

// PSControlTableCell (свитч/слайдер лежат прямо в ячейке) отдаёт контрол
// через свойство control — объявляем протоколом, класс не трогаем
@protocol MPHasControl <NSObject>
- (UIControl *)control;
@end

@interface MPSettingsCellStyler : NSObject

// Полное оформление PS-ячейки (цвета/шрифты/фон/подсветка/аксессуары)
+ (void)stylePSTableCell:(UITableViewCell *)cell;

// Раскладка подвью (вызывается из layoutSubviews-хука): заголовок слева 16 pt,
// значение с правой стороны переносится ПОД заголовок серым 13 pt
+ (void)layoutPSTableCell:(UITableViewCell *)cell;

// Универсальный слой для не-PS ячеек (обычные UITableView своих экранов)
+ (void)styleGenericCell:(UITableViewCell *)cell;

// Плоское поле ввода: белый текст, серый placeholder, тёмная клавиатура
+ (void)styleTextField:(UITextField *)field;

@end
