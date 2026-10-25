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

+ (UIImage *)mp_flatImageWithSize:(CGSize)size color:(UIColor *)color radius:(CGFloat)radius {
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0f);
    [color setFill];
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                cornerRadius:radius];
    [p fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (void)styleSlider:(UISlider *)slider {
    if (slider == nil) return;
    @try {
        // По референсу WP8 (.sched/.sr__bar): линия 3px — заполненная часть акцентом,
        // пустая — белый α .16; бегунок — маленький белый квадрат (без скруглений)
        UIImage *minTrack = [[self class] mp_flatImageWithSize:CGSizeMake(3.0f, 3.0f)
                                                         color:[MPMetroStyle accentColor] radius:0.0f];
        UIImage *maxTrack = [[self class] mp_flatImageWithSize:CGSizeMake(3.0f, 3.0f)
                                                         color:[UIColor colorWithWhite:1.0f alpha:0.16f]
                                                          radius:0.0f];
        UIImage *thumb    = [[self class] mp_flatImageWithSize:CGSizeMake(14.0f, 14.0f)
                                                         color:[UIColor whiteColor] radius:0.0f];
        [slider setMinimumTrackImage:minTrack forState:UIControlStateNormal];
        [slider setMaximumTrackImage:maxTrack forState:UIControlStateNormal];
        [slider setThumbImage:thumb forState:UIControlStateNormal];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] слайдер: %@ (%@)", e.name, e.reason);
    }
}

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

            // Слайдеры: WP — линия 3px и белый квадратный бегунок
            UIImage *minTrack = [[self class] mp_flatImageWithSize:CGSizeMake(3.0f, 3.0f)
                                                             color:[MPMetroStyle accentColor] radius:0.0f];
            UIImage *maxTrack = [[self class] mp_flatImageWithSize:CGSizeMake(3.0f, 3.0f)
                                                             color:[UIColor colorWithWhite:1.0f alpha:0.16f]
                                                              radius:0.0f];
            UIImage *thumb = [[self class] mp_flatImageWithSize:CGSizeMake(14.0f, 14.0f)
                                                          color:[UIColor whiteColor] radius:0.0f];
            [[UISlider appearance] setMinimumTrackImage:minTrack forState:UIControlStateNormal];
            [[UISlider appearance] setMaximumTrackImage:maxTrack forState:UIControlStateNormal];
            [[UISlider appearance] setThumbImage:thumb forState:UIControlStateNormal];

            // Сегменты (язык и т.п.): плоско
            [[UISegmentedControl appearance] setTintColor:[UIColor colorWithWhite:0.25f alpha:1.0f]];

            // Навбар: Preferences использует подкласс UINavigationBar — хук базового
            // drawRect его не красит. Appearance с чёрной фоновоой картинкой красит все.
            UIImage *black = [[self class] mp_blackPixelImage];
            [[UINavigationBar appearance] setBackgroundImage:black
                                              forBarMetrics:UIBarMetricsDefault];
            [[UIBarButtonItem appearance] setTintColor:[UIColor whiteColor]];
            [self styleWindows];

            NSLog(@"[MetroPhone][Settings] UIAppearance настроен");
        } @catch (NSException *e) {
            NSLog(@"[MetroPhone][Settings] appearance: %@ (%@)", e.name, e.reason);
        }
    });
}

+ (void)styleNavigationBar:(UINavigationBar *)bar {
    if (bar == nil) return;
    @try {
        [bar setBackgroundImage:[self mp_blackPixelImage] forBarMetrics:UIBarMetricsDefault];
        [bar setTitleTextAttributes:@{
            UITextAttributeTextColor: [UIColor clearColor],
            UITextAttributeTextShadowColor: [UIColor clearColor],
        }];
        // заголовок: если это titleView — прячем; если текст — подменяем пустой вьюхой
        // (атрибутов недостаточно: iOS 6 кэширует отрисованную надпись)
        if (bar.topItem != nil) {
            if (bar.topItem.titleView != nil) {
                bar.topItem.titleView.hidden = YES;
            } else if (bar.topItem.title.length > 0) {
                bar.topItem.titleView = [[UIView alloc] initWithFrame:CGRectZero];
            }
        }
        [bar setNeedsLayout];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] навбар: %@ (%@)", e.name, e.reason);
    }
}

+ (void)styleWindows {
    @try {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            w.backgroundColor = [UIColor blackColor];
        }
        [UIApplication sharedApplication].keyWindow.backgroundColor = [UIColor blackColor];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] окна: %@ (%@)", e.name, e.reason);
    }
}

+ (UIView *)flatSelectionBackground {
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    v.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
    return v;
}

@end
