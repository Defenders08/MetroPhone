// MPCalcView — WP8.1-калькулятор целиком: дисплей + клавиатура + логика
// (арифметика с приоритетами, память MC/MR/M+, backspace, ±, %).
// Нативный UI CalculatorController прячется хуком, наша вьюха живёт поверх.

#import <UIKit/UIKit.h>

@interface MPCalcView : UIView

// Создать и показать в корневой вьюхе CalculatorController.
// Повторный вызов — возвращает уже живую вьюху (наверх).
+ (MPCalcView *)installedCalcInView:(UIView *)host;

// Повернуться под текущую ориентацию устройства (портрет/ландшафт/шиворот-навыворот)
- (void)applyOrientation;

@end
