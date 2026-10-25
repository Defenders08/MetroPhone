// MPSettingsHeaderView — шапка страницы «Настроек» в духе WP 8.1:
// малый заголовок приложения ЗАГЛАВНЫМИ + огромное строчное название страницы.
// Прокручивается вместе со списком (tableHeaderView), модель заголовков не меняется.

#import <UIKit/UIKit.h>
#import "../MetroLauncher/MPMetroStyle.h"

@interface MPSettingsHeaderView : UIView

@property (nonatomic, copy) NSString *pageTitle;    // «основные», Light 52 → 30 (ручной подбор)

// WP 8.1: на подстраницах слева от большого заголовка — акцентная «‹»,
// тап по всей шапке работает как «Назад»
@property (nonatomic, assign) BOOL showsBackChevron;
@property (nonatomic, copy) void (^backTapped)(void);

+ (CGFloat)heightForWidth:(CGFloat)width;

@end
