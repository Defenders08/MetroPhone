#import "MPSettingsTheme.h"

// iOS 5+: атрибуты заголовка элемента навигации (в SDK 10.3 метод не объявлен)
@interface UINavigationItem (MPTitleAttrs)
- (void)setTitleTextAttributes:(NSDictionary *)attributes;
@end

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
        // Канал в стиле тумблера: узкий прямоугольник с серой рамкой 1 px,
        // заполненная часть — акцентом, пустая — тёмная; бегунок — белый квадрат.
        UIImage *minTrack = [self mp_sliderTrackFilled:YES];
        UIImage *maxTrack = [self mp_sliderTrackFilled:NO];
        UIImage *thumb    = [[self class] mp_flatImageWithSize:CGSizeMake(14.0f, 14.0f)
                                                         color:[UIColor whiteColor] radius:0.0f];
        [slider setMinimumTrackImage:minTrack forState:UIControlStateNormal];
        [slider setMaximumTrackImage:maxTrack forState:UIControlStateNormal];
        [slider setThumbImage:thumb forState:UIControlStateNormal];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] слайдер: %@ (%@)", e.name, e.reason);
    }
}

// Картинка канала ползунка: прямоугольник 24×6 с рамкой белый α0.25;
// filled=YES — внутренность акцентом, NO — тёмная. Растяжимая по горизонтали.
+ (UIImage *)mp_sliderTrackFilled:(BOOL)filled {
    // Тонкая линия, как на странице «Цвета»: заполненная — акцентом, пустая —
    // белый 16 %. Рамку не рисуем: на коротком участке (ползунок у края) она
    // превращала трек в белый квадрат.
    UIImage *img = [self mp_flatImageWithSize:CGSizeMake(3.0f, 3.0f)
                                        color:(filled ? [MPMetroStyle accentColor]
                                                      : [UIColor colorWithWhite:1.0f alpha:0.16f])
                                       radius:0.0f];
    return [img resizableImageWithCapInsets:UIEdgeInsetsZero];
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
        // CyDown: свой контроллер с кастомным UI выхода — оформление запирает
        // страницу (кнопка выхода не в стандартных местах навбара). Штатный вид.
        @"CyDownSettingsListController",
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

+ (NSArray *)excludedPageTitles {
    // Твики без своего класса (обычный PSListController) — исключаем по заголовку.
    // Auxo: страница не покидается через pop/dismiss (не в nav-стеке).
    return @[
        @"Auxo",
    ];
}

+ (BOOL)isTitleExcluded:(NSString *)title {
    if (title.length == 0) return NO;
    for (NSString *t in [self excludedPageTitles]) {
        if ([title caseInsensitiveCompare:t] == NSOrderedSame) return YES;
    }
    return NO;
}

// Слайдерные картинки зависят от акцента — используются в setupAppearanceOnce
// и в reapplyAccentAppearance (после смены цвета)
+ (void)applySliderAppearance {
    UIImage *minTrack = [self mp_sliderTrackFilled:YES];
    UIImage *maxTrack = [self mp_sliderTrackFilled:NO];
    UIImage *thumb = [[self class] mp_flatImageWithSize:CGSizeMake(14.0f, 14.0f)
                                                  color:[UIColor whiteColor] radius:0.0f];
    [[UISlider appearance] setMinimumTrackImage:minTrack forState:UIControlStateNormal];
    [[UISlider appearance] setMaximumTrackImage:maxTrack forState:UIControlStateNormal];
    [[UISlider appearance] setThumbImage:thumb forState:UIControlStateNormal];
}

+ (void)reapplyAccentAppearance {
    @try {
        [[UISwitch appearance] setOnTintColor:[MPMetroStyle accentColor]];
        [self applySliderAppearance];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] reapplyAccent: %@ (%@)", e.name, e.reason);
    }
}

+ (void)setupAppearanceOnce {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            // Тумблеры: акцентный включённый трек, белый бегунок (iOS 6 поддерживает)
            [[UISwitch appearance] setOnTintColor:[MPMetroStyle accentColor]];
            [[UISwitch appearance] setThumbTintColor:[UIColor whiteColor]];

            // Слайдеры: WP — линия 3px и белый квадратный бегунок
            [self applySliderAppearance];

            // Сегменты (язык и т.п.): плоско
            [[UISegmentedControl appearance] setTintColor:[UIColor colorWithWhite:0.25f alpha:1.0f]];

            // Навбар и бар-кнопки НЕ трогаем глобально: на страницах твиков это
            // делало кнопку «назад» невидимой (белая на белом). Красим инстансно
            // только системные страницы (MPSettingsTheme styleNavigationBar).
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
        bar.tintColor = [UIColor whiteColor];   // бар-кнопки белые (на чёрном фоне)
        // ВНИМАНИЕ: titleView НЕ трогаем — твики (CyDown и др.) вешают туда
        // собственные кнопки выхода; скрытие запирало страницу
        if (bar.topItem != nil && [bar.topItem respondsToSelector:@selector(setTitleTextAttributes:)]) {
            [(UINavigationItem *)bar.topItem setTitleTextAttributes:@{
                UITextAttributeTextColor: [UIColor clearColor],
                UITextAttributeTextShadowColor: [UIColor clearColor],
            }];
        }
        [bar setNeedsLayout];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] навбар: %@ (%@)", e.name, e.reason);
    }
}

#pragma mark - Бар-кнопки

+ (UIImage *)mp_transparentStretchable {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(4.0f, 4.0f), NO, 1.0f);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img stretchableImageWithLeftCapWidth:2 topCapHeight:2];
}

+ (void)applyFlatBarButtonAppearance {
    @try {
        // «только текст»: прозрачная подложка вместо родного глянца — остаётся
        // белый текст кнопки (tintColor белым ставит styleNavigationBar)
        UIImage *none = [self mp_transparentStretchable];
        [[UIBarButtonItem appearance] setBackgroundImage:none
                                                forState:UIControlStateNormal
                                              barMetrics:UIBarMetricsDefault];
        [[UIBarButtonItem appearance] setBackgroundImage:none
                                                forState:UIControlStateHighlighted
                                              barMetrics:UIBarMetricsDefault];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] barButtons: %@ (%@)", e.name, e.reason);
    }
}

+ (void)resetBarButtonAppearance {
    @try {
        // страницам твиков — родной вид кнопок (на белом фоне их не видно иначе)
        [[UIBarButtonItem appearance] setBackgroundImage:nil
                                                forState:UIControlStateNormal
                                              barMetrics:UIBarMetricsDefault];
        [[UIBarButtonItem appearance] setBackgroundImage:nil
                                                forState:UIControlStateHighlighted
                                              barMetrics:UIBarMetricsDefault];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] barButtonsReset: %@ (%@)", e.name, e.reason);
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
    // подложка нажатия не используется: вместо неё — «парение» текста
    // (светлая тень, см. MPSettingsCellStyler applyFloatingEffect)
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    v.backgroundColor = [UIColor clearColor];
    return v;
}

@end
