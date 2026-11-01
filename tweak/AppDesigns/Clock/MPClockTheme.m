#import "MPClockTheme.h"
#import "MetroLauncher/MPMetroStyle.h"

// Ключи префов (домен ru.ash.metrophone)
#define MPKeyClockRestyle @"clockRestyle"

static BOOL MPClockFlag(NSString *key, BOOL def) {
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

@implementation MPClockTheme

+ (BOOL)restyleEnabled {
    return MPClockFlag(MPKeyClockRestyle, YES);
}

+ (UIColor *)mutedColor {
    // канон «Настроек»: подписи/значения/заголовки секций — белый 0.6
    return [UIColor colorWithWhite:1.0f alpha:0.6f];
}

+ (UIColor *)faintColor {
    return [UIColor colorWithWhite:1.0f alpha:0.26f];
}

+ (UIColor *)disabledColor {
    // выключенный пункт: белый 0.4 (как заголовок disabled-ячейки в Настройках)
    return [UIColor colorWithWhite:1.0f alpha:0.4f];
}

+ (UIColor *)placeholderColor {
    // плейсхолдер полей ввода: белый 0.3 (MPSettingsTheme placeholderColor)
    return [UIColor colorWithWhite:1.0f alpha:0.3f];
}

+ (UIColor *)dangerColor {
    // правило проекта: красный текст сохраняется для опасных действий;
    // red из палитры акцентов MPMetroStyle
    return [UIColor colorWithRed:0xE5 / 255.0f green:0x14 / 255.0f blue:0x00 / 255.0f alpha:1.0f];
}

+ (UIButton *)bigTextAction:(NSString *)title secondary:(BOOL)secondary {
    // канон «Настроек»: «коробок нет» — действие это текст без плашки и рамки
    // (аудит: «Push button с рамкой отклонён»); главное действие — акцент,
    // вторичное («круг», «сброс», «отмена») — приглушённое
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font = [MPMetroStyle lightFont:24.0f];
    [b setTitle:title forState:UIControlStateNormal];
    UIColor *normal = secondary ? [self mutedColor] : [MPMetroStyle accentColor];
    [b setTitleColor:normal forState:UIControlStateNormal];
    [b setTitleColor:[self faintColor] forState:UIControlStateHighlighted];
    [b setTitleColor:[self faintColor] forState:UIControlStateSelected];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    return b;
}

+ (UIButton *)actionButtonWithTitle:(NSString *)title {
    // действия шапки: БЕЛЫЕ, тем же шрифтом, что названия городов (light 24);
    // заглавную букву задаёт вызывающий
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font = [MPMetroStyle lightFont:24.0f];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[self mutedColor] forState:UIControlStateHighlighted];
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    return b;
}

@end
