// MPColorsGridView — визуальный выбор акцентного цвета в стиле WP 8.1:
// сетка квадратных плиток (выбранная — с белой рамкой и галочкой) и
// «свой цвет» на трёх ползунках R/G/B. Живёт только в бандле настроек:
// выбранная плитка пишет ключ accentHex (домен ru.ash.metrophone) и
// рассылает Darwin-уведомление «ru.ash.metrophone.accent-changed».

#import <UIKit/UIKit.h>

@interface MPColorsGridView : UIView

+ (CGFloat)heightForWidth:(CGFloat)width;

@end
