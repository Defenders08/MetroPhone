// MPSettingsCellStyler — переоформление ячеек «Настроек» после оригинальной
// отрисовки: плоский чёрный фон, белый Light-заголовок, серый подзаголовок,
// без иконок/шевронов/карточек. Логику ячейки не трогаем.

#import <UIKit/UIKit.h>

@class PSTableCell;

// Видимость иконок на текущей странице «Настроек»: в корневом меню иконок нет
// (плоский WP-список), на внутренних страницах — наши глифы.
extern BOOL MPSettingsIconsHidden;
extern BOOL MPSettingsPageHasIcons;   // на странице есть хотя бы одна иконка
extern BOOL MPSettingsPageIsSounds;    // страница «Звуки»: картинки убираем

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

// Глубокая перекраска ОДНОЙ ячейки (кастомные списки Wi-Fi/VPN):
// лейблы белым (кроме красных), синие круглые диски → акцентные квадраты,
// мелкие иконки (замок/сигнал) тинтом в белый.
// Вызывается из cellForRowAtIndexPath — официальный момент UIKit, безопасно.
+ (void)styleCellDeep:(UITableViewCell *)cell;

// «Парение» по-Zune: при нажатии у текста строки — лёгкая светлая тень
// (подложка не используется). Вызывается из хука PSTableCell setHighlighted:.
+ (void)applyFloatingEffect:(BOOL)highlighted toCell:(UITableViewCell *)cell;

// Плоское поле ввода: белый текст, серый placeholder, тёмная клавиатура
+ (void)styleTextField:(UITextField *)field;

@end
