#import "MPContactsTheme.h"
#import "MetroLauncher/MPMetroStyle.h"

// Ключи префов (домен ru.ash.metrophone)
#define MPKeyContactsRestyle @"contactsRestyle"

static BOOL MPContactsFlag(NSString *key, BOOL def) {
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

@implementation MPContactsTheme

+ (BOOL)restyleEnabled {
    return MPContactsFlag(MPKeyContactsRestyle, YES);
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

+ (UIButton *)actionButtonWithTitle:(NSString *)title {
    return [self actionButtonWithTitle:title size:24.0f];
}

+ (UIButton *)actionButtonWithTitle:(NSString *)title size:(CGFloat)size {
    // действия шапки: белый light (кегль задаёт вызов — ряд с «назад» ужимается)
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font = [MPMetroStyle lightFont:size];
    b.titleLabel.lineBreakMode = NSLineBreakByClipping;
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
