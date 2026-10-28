// MPSettingsHeaderView — шапка страницы «Настроек» в духе WP 8.1:
// малый заголовок приложения ЗАГЛАВНЫМИ + огромное строчное название страницы.
// Прокручивается вместе со списком (tableHeaderView), модель заголовков не меняется.

#import <UIKit/UIKit.h>
#import "../MetroLauncher/MPMetroStyle.h"

@interface MPSettingsHeaderView : UIView

@property (nonatomic, copy) NSString *pageTitle;    // «Основные», Light 52 → 30 (ручной подбор)

// Стрелки-иконки в шапке нет: на подстранице заголовок остаётся типографикой,
// тап по всей шапке работает как «Назад»
@property (nonatomic, assign) BOOL showsBackChevron;   // флаг подстраницы; вид от него не зависит
@property (nonatomic, copy) void (^backTapped)(void);

+ (CGFloat)heightForWidth:(CGFloat)width;

@end
