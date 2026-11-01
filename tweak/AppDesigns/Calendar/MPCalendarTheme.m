#import "MPCalendarTheme.h"
#import "MetroLauncher/MPMetroStyle.h"

// Ключи префов (домен ru.ash.metrophone)
#define MPKeyCalendarRestyle @"calendarRestyle"

static BOOL MPCalendarFlag(NSString *key, BOOL def) {
    CFPreferencesAppSynchronize(CFSTR("ru.ash.metrophone"));
    CFBooleanRef v = (CFBooleanRef)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                             CFSTR("ru.ash.metrophone"));
    BOOL res = def;
    if (v != NULL) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) res = CFBooleanGetValue(v);
        CFRelease(v);
    }
    return res;
}

@implementation MPCalendarTheme

+ (BOOL)restyleEnabled {
    return MPCalendarFlag(MPKeyCalendarRestyle, YES);
}

+ (UIColor *)mutedColor {
    return [UIColor colorWithWhite:1.0f alpha:0.6f];
}

+ (UIColor *)faintColor {
    return [UIColor colorWithWhite:1.0f alpha:0.26f];
}

+ (UIColor *)disabledColor {
    return [UIColor colorWithWhite:1.0f alpha:0.4f];
}

+ (UIColor *)placeholderColor {
    return [UIColor colorWithWhite:1.0f alpha:0.3f];
}

+ (UIColor *)dangerColor {
    return [UIColor colorWithRed:0xE5 / 255.0f green:0x14 / 255.0f blue:0x00 / 255.0f alpha:1.0f];
}

+ (UIButton *)actionButtonWithTitle:(NSString *)title {
    // действия шапки: белый light 24, как пары «Изменить/Добавить» в «Часах»
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font = [MPMetroStyle lightFont:24.0f];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[self mutedColor] forState:UIControlStateHighlighted];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    return b;
}

+ (UIButton *)bigTextAction:(NSString *)title secondary:(BOOL)secondary {
    // канон «Настроек»: «коробок нет» — главное действие акцентом, вторичное muted
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font = [MPMetroStyle lightFont:24.0f];
    [b setTitle:title forState:UIControlStateNormal];
    UIColor *normal = secondary ? [self mutedColor] : [MPMetroStyle accentColor];
    [b setTitleColor:normal forState:UIControlStateNormal];
    [b setTitleColor:[self faintColor] forState:UIControlStateHighlighted];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    return b;
}

@end
