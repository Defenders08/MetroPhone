// MPCalcTheme — метрики и цвета переоформления «Калькулятора»
// (com.apple.calculator) в WP8.1-стиль. Референс юзера: чёрный фон,
// большая светлая строка дисплея справа, клавиши #333 с зазором ~4,
// «=» — акцентная (в референсе лаймовая; берём акцент из MPMetroStyle).

#import <UIKit/UIKit.h>

#define MPCalcMargin       4.0f    // внешние поля сетки клавиш
#define MPCalcGap          4.0f    // зазор между клавишами
#define MPCalcDisplayH     124.0f  // высота зоны дисплея (клавиши начинаются ниже)
#define MPCalcCols         4
#define MPCalcRows         6
#define MPCalcViewTag      0x4D50436C   // 'MPCl' — маркер нашей вьюхи в дереве

@interface MPCalcTheme : NSObject

// Kill-switch: ключ calcRestyle (домен ru.ash.metrophone), по умолчанию YES
+ (BOOL)restyleEnabled;

// Клавиша: фон белый 0.22 (≈ #383838 на чёрном), нажатая — светлее (канон WP)
+ (UIColor *)keyColor;
+ (UIColor *)keyPressedColor;
+ (UIColor *)keyTextColor;

@end
