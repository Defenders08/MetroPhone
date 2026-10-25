// MPSettingsToggle — WP 8.1 тумблер поверх оригинального UISwitch.
// Оригинальный свитч остаётся в иерархии (скрыт) и продолжает вести логику:
// наш тап вызывает setOn: + sendActionsForControlEvents (ValueChanged),
// а %hook -setOn:animated: зеркалит состояние обратно в вид.

#import <UIKit/UIKit.h>

@interface MPSettingsToggle : UIView

// Найти/создать тумблер для свитча (один на свитч); сам свитч скрывается
+ (MPSettingsToggle *)attachedToggleForSwitch:(UISwitch *)sw;

// Подогнать кадр под положение оригинального свитча
- (void)syncFrameFromSwitch;

// Перечитать состояние и перерисовать
- (void)syncFromSwitch;

@end
