#import "MPColorsGridView.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString * const MPGridDomain     = @"ru.ash.metrophone";
static NSString * const MPGridAccentHex  = @"accentHex";
static NSString * const MPGridChanged    = @"ru.ash.metrophone.accent-changed";

// Палитра акцентов Windows Phone 8.1 (страница Colors): 20 цветов, 8 в ряду.
static NSString * const MPGridPalette[20] = {
    @"A4C400", @"60A917", @"008A00", @"00ABA9", @"1BA1E2", @"0050EF", @"6A00FF", @"AA00FF",
    @"F472D0", @"D80073", @"A20025", @"E51400", @"FA6800", @"F0A30A", @"E3C800",
    @"825A2C", @"6D8764", @"647687", @"76608A", @"87794E"
};

// Старые имена ключа «accent» (до 0.6.11) — чтобы выделение не терялось
static NSDictionary *MPGridLegacyNames(void) {
    static NSDictionary *m = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = @{ @"blue":    @"1BA1E2",
               @"purple":  @"A200FF",
               @"magenta": @"D80073",
               @"green":   @"008A00",
               @"lime":    @"A4C400",
               @"orange":  @"F09609",
               @"red":     @"E51400",
               @"teal":    @"00ABA9" };
    });
    return m;
}

static UIColor *MPGridColorFromHex(NSString *hex) {
    if (hex.length == 0) return nil;
    NSString *s = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (s.length != 6) return nil;
    NSScanner *sc = [NSScanner scannerWithString:s];
    unsigned v = 0;
    if (![sc scanHexInt:&v]) return nil;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0f
                           green:((v >> 8) & 0xFF) / 255.0f
                            blue:(v & 0xFF) / 255.0f
                           alpha:1.0f];
}

static NSString *MPGridHexFromColor(UIColor *c) {
    if (c == nil) return @"1BA1E2";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return @"1BA1E2";
    return [NSString stringWithFormat:@"%02X%02X%02X",
            (int)roundf(r * 255.0f), (int)roundf(g * 255.0f), (int)roundf(b * 255.0f)];
}

// Текущий выбранный HEX: accentHex → старое имя → синий по умолчанию
static NSString *MPGridCurrentHex(void) {
    NSString *hex = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(
        (__bridge CFStringRef)MPGridAccentHex, (__bridge CFStringRef)MPGridDomain);
    if ([hex isKindOfClass:[NSString class]] && MPGridColorFromHex(hex) != nil) {
        return [hex uppercaseString];
    }
    NSString *name = (__bridge_transfer NSString *)CFPreferencesCopyAppValue(
        CFSTR("accent"), (__bridge CFStringRef)MPGridDomain);
    if ([name isKindOfClass:[NSString class]]) {
        NSString *h = [MPGridLegacyNames() objectForKey:name];
        if (h != nil) return h;
    }
    return @"1BA1E2";
}

static void MPGridStoreHex(NSString *hex) {
    CFPreferencesSetAppValue((__bridge CFStringRef)MPGridAccentHex,
                             (__bridge CFStringRef)hex,
                             (__bridge CFStringRef)MPGridDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MPGridDomain);
    // живое обновление темы в этом процессе (Настройки) и в SpringBoard
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)MPGridChanged, NULL, NULL, TRUE);
}

// Плоская картинка-прямоугольник для трека/бегунка ползунка
static UIImage *MPGridFlatImage(CGSize size, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0f);
    [color setFill];
    UIRectFill(CGRectMake(0.0f, 0.0f, size.width, size.height));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation MPColorsGridView {
    NSMutableArray *_squares;       // UIButton[20]
    UILabel        *_check;         // галочка на выбранной плитке
    UILabel        *_capLabel;      // подпись «свой цвет»
    NSString       *_selectedHex;
    UIView         *_preview;       // квадрат текущего «своего» цвета
    UISlider       *_r, *_g, *_b;
    BOOL           _muteSliders;    // не писать в настройки при программной установке
}

+ (CGFloat)cellSizeForWidth:(CGFloat)width {
    // 8 колонок, поля 16, зазор 4 — как на странице Colors в WP 8.1
    return floorf(((width - 32.0f - 7.0f * 4.0f) / 8.0f) * 2.0f) / 2.0f;
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat cell = [self cellSizeForWidth:width];
    CGFloat gridH = 3.0f * cell + 2.0f * 4.0f;              // 20 цветов: 8+8+4
    return 10.0f + gridH + 14.0f + 24.0f + 3.0f * 32.0f + 16.0f;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        _squares = [NSMutableArray array];
        _selectedHex = MPGridCurrentHex();

        for (NSUInteger i = 0; i < 20; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.backgroundColor = MPGridColorFromHex(MPGridPalette[i]);
            b.tag = i;
            [b addTarget:self action:@selector(squareTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:b];
            [_squares addObject:b];
        }

        // галочка выбранной плитки (белая, по центру — как в WP)
        _check = [[UILabel alloc] initWithFrame:CGRectZero];
        _check.text = @"\u2713";
        _check.textColor = [UIColor whiteColor];
        _check.font = [UIFont boldSystemFontOfSize:17.0f];
        _check.textAlignment = NSTextAlignmentCenter;
        _check.backgroundColor = [UIColor clearColor];

        // ---- свой цвет ----
        UILabel *cap = [[UILabel alloc] initWithFrame:CGRectZero];
        cap.text = @"свой цвет";
        cap.font = [UIFont systemFontOfSize:12.0f];
        cap.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
        cap.backgroundColor = [UIColor clearColor];
        [self addSubview:cap];
        _capLabel = cap;

        _preview = [[UIView alloc] initWithFrame:CGRectZero];
        _preview.backgroundColor = MPGridColorFromHex(_selectedHex);
        [self addSubview:_preview];

        _r = [self makeSlider];
        _g = [self makeSlider];
        _b = [self makeSlider];

        [self applyHexToSliders:MPGridCurrentHex()];
        [self refreshSelection];
    }
    return self;
}

- (UISlider *)makeSlider {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectZero];
    s.minimumValue = 0.0f;
    s.maximumValue = 255.0f;
    s.continuous = YES;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:s];
    return s;
}

- (void)applyHexToSliders:(NSString *)hex {
    UIColor *c = MPGridColorFromHex(hex);
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (c != nil && [c getRed:&r green:&g blue:&b alpha:&a]) {
        _muteSliders = YES;
        _r.value = r * 255.0f;
        _g.value = g * 255.0f;
        _b.value = b * 255.0f;
        _muteSliders = NO;
    }
}

// Выбранная плитка: белая рамка 2pt + галочка
- (void)refreshSelection {
    UIButton *selected = nil;
    for (UIButton *b in _squares) {
        BOOL match = [MPGridPalette[b.tag] isEqualToString:_selectedHex];
        b.layer.borderWidth = match ? 2.0f : 0.0f;
        b.layer.borderColor = [UIColor whiteColor].CGColor;
        if (match) selected = b;
    }
    [_check removeFromSuperview];
    if (selected != nil) {
        _check.frame = selected.bounds;
        [selected addSubview:_check];
    }
}

- (void)squareTapped:(UIButton *)sender {
    _selectedHex = MPGridPalette[sender.tag];
    [self applyHexToSliders:_selectedHex];
    _preview.backgroundColor = MPGridColorFromHex(_selectedHex);
    [self refreshSelection];
    MPGridStoreHex(_selectedHex);
}

- (void)sliderChanged:(UISlider *)slider {
    if (_muteSliders) return;
    UIColor *c = [UIColor colorWithRed:_r.value / 255.0f
                                 green:_g.value / 255.0f
                                  blue:_b.value / 255.0f
                                 alpha:1.0f];
    _selectedHex = MPGridHexFromColor(c);
    _preview.backgroundColor = c;
    [self refreshSelection];
    MPGridStoreHex(_selectedHex);
    [self styleSliders];
}

- (void)styleSliders {
    // WP-ползунок: трек 3px (заполненная часть — цветом), белый квадратный бегунок
    NSArray *sliders = @[_r, _g, _b];
    for (UISlider *s in sliders) {
        [s setMinimumTrackImage:MPGridFlatImage(CGSizeMake(3.0f, 3.0f), _preview.backgroundColor)
                       forState:UIControlStateNormal];
        [s setMaximumTrackImage:MPGridFlatImage(CGSizeMake(3.0f, 3.0f),
                                                [UIColor colorWithWhite:1.0f alpha:0.16f])
                       forState:UIControlStateNormal];
        [s setThumbImage:MPGridFlatImage(CGSizeMake(14.0f, 14.0f), [UIColor whiteColor])
                forState:UIControlStateNormal];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat cell = [MPColorsGridView cellSizeForWidth:w];
    CGFloat gap = 4.0f;
    CGFloat y = 10.0f;

    for (NSUInteger i = 0; i < _squares.count; i++) {
        NSUInteger row = i / 8;
        NSUInteger col = i % 8;
        UIButton *b = [_squares objectAtIndex:i];
        b.frame = CGRectMake(16.0f + col * (cell + gap), y + row * (cell + gap), cell, cell);
    }
    y += 3.0f * cell + 2.0f * gap;

    y += 14.0f;
    _capLabel.frame = CGRectMake(16.0f, y, 120.0f, 18.0f);
    _preview.frame = CGRectMake(w - 16.0f - 22.0f, y, 22.0f, 22.0f);
    y += 24.0f;

    CGFloat labelW = 14.0f;
    NSArray *sliders = @[_r, _g, _b];
    for (NSUInteger i = 0; i < sliders.count; i++) {
        UISlider *s = [sliders objectAtIndex:i];
        s.frame = CGRectMake(16.0f + labelW + 8.0f, y, w - 32.0f - labelW - 8.0f, 24.0f);
        y += 32.0f;
    }
    [self styleSliders];
}

@end
