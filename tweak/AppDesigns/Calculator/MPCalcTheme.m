#import "MPCalcTheme.h"
#import "MetroLauncher/MPMetroStyle.h"

// Ключи префов (домен ru.ash.metrophone)
#define MPKeyCalcRestyle @"calcRestyle"

static BOOL MPCalcFlag(NSString *key, BOOL def) {
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

@implementation MPCalcTheme

+ (BOOL)restyleEnabled {
    return MPCalcFlag(MPKeyCalcRestyle, YES);
}

+ (UIColor *)keyColor {
    // WP8.1: клавиши — #333 (0.2), референс чуть светлее — 0.22
    return [UIColor colorWithWhite:1.0f alpha:0.22f];
}

+ (UIColor *)keyPressedColor {
    // нажатая клавиша заметно светлеет (как в WP8.1)
    return [UIColor colorWithWhite:1.0f alpha:0.36f];
}

+ (UIColor *)keyTextColor {
    return [UIColor whiteColor];
}

@end
