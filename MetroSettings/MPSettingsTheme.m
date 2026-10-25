#import "MPSettingsTheme.h"

static BOOL MPSettingsPrefsBool(NSString *key, BOOL def) {
    CFTypeRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("ru.ash.metrophone"));
    if (v == NULL) return def;
    BOOL result = def;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) result = CFBooleanGetValue((CFBooleanRef)v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) result = [(__bridge NSNumber *)v boolValue];
    CFRelease(v);
    return result;
}

static UIImage *MPSettingsBlackPixel = nil;

@implementation MPSettingsTheme

+ (UIImage *)mp_blackPixelImage {
    if (MPSettingsBlackPixel == nil) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1.0f, 1.0f), NO, 1.0f);
        [[UIColor blackColor] setFill];
        UIRectFill(CGRectMake(0.0f, 0.0f, 1.0f, 1.0f));
        MPSettingsBlackPixel = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        MPSettingsBlackPixel = [MPSettingsBlackPixel stretchableImageWithLeftCapWidth:0 topCapHeight:0];
    }
    return MPSettingsBlackPixel;
}

+ (BOOL)restyleEnabled { return MPSettingsPrefsBool(@"settingsRestyle", YES); }
+ (BOOL)debugEnabled   { return MPSettingsPrefsBool(@"settingsDebug", NO); }

+ (NSArray *)excludedControllerClasses {
    // Экраны, где наша раскладка ломает контент, добавляются сюда по имени класса
    // (диагностика включается ключом settingsDebug).
    return @[
        // пока пусто — заполняется по результатам проверки на устройстве
    ];
}

+ (BOOL)isControllerExcluded:(UIViewController *)controller {
    if (controller == nil) return NO;
    NSString *cls = NSStringFromClass([controller class]);
    for (NSString *name in [self excludedControllerClasses]) {
        if ([cls isEqualToString:name]) return YES;
    }
    return NO;
}

+ (void)setupAppearanceOnce {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            // Тумблеры: акцентный включённый трек, белый бегунок (iOS 6 поддерживает)
            [[UISwitch appearance] setOnTintColor:[MPMetroStyle accentColor]];
            [[UISwitch appearance] setThumbTintColor:[UIColor whiteColor]];

            // Слайдеры: акцентный активный трек
            [[UISlider appearance] setMinimumTrackTintColor:[MPMetroStyle accentColor]];
            [[UISlider appearance] setMaximumTrackTintColor:[UIColor colorWithWhite:0.35f alpha:1.0f]];

            // Сегменты (язык и т.п.): плоско
            [[UISegmentedControl appearance] setTintColor:[UIColor colorWithWhite:0.25f alpha:1.0f]];

            // Навбар: Preferences использует подкласс UINavigationBar — хук базового
            // drawRect его не красит. Appearance с чёрной фоновоой картинкой красит все.
            UIImage *black = [[self class] mp_blackPixelImage];
            [[UINavigationBar appearance] setBackgroundImage:black
                                              forBarMetrics:UIBarMetricsDefault];
            [[UINavigationBar appearance] setTitleTextAttributes:@{
                UITextAttributeTextColor: [UIColor clearColor],          // заголовок всегда в нашей шапке
                UITextAttributeTextShadowColor: [UIColor clearColor],
            }];
            [[UIBarButtonItem appearance] setTintColor:[UIColor whiteColor]];

            // Белая полоса статус-бара: фон окна — чёрный
            [UIApplication sharedApplication].keyWindow.backgroundColor = [UIColor blackColor];

            NSLog(@"[MetroPhone][Settings] UIAppearance настроен");
        } @catch (NSException *e) {
            NSLog(@"[MetroPhone][Settings] appearance: %@ (%@)", e.name, e.reason);
        }
    });
}

+ (UIView *)flatSelectionBackground {
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    v.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
    return v;
}

@end
