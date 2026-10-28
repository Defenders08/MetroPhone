#import "MPSettingsHeaderView.h"

// Заголовок страницы — с заглавной буквы («Настройки», «Основные», «Wi-Fi»):
// бренды сохраняют свой регистр (вопрос 124B: «Wi-Fi», «iCloud», «App Store»),
// остальные названия — только первая буква заглавная, не каждое слово.
static NSString *MPDisplayTitle(NSString *raw) {
    if (raw.length == 0) return raw;
    static NSDictionary *brands = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        brands = @{
            @"wi-fi": @"Wi-Fi", @"wifi": @"Wi-Fi", @"icloud": @"iCloud",
            @"vpn": @"VPN", @"app store": @"App Store",
            @"itunes- и app store": @"iTunes и App Store",
            @"itunes и app store": @"iTunes и App Store",
            @"bluetooth": @"Bluetooth", @"facetime": @"FaceTime",
            @"twitter": @"Twitter", @"facebook": @"Facebook",
            @"safari": @"Safari", @"nike + ipod": @"Nike + iPod",
            @"2gis": @"2GIS", @"metrophone": @"MetroPhone",
        };
    });
    NSString *low = [raw lowercaseStringWithLocale:[NSLocale currentLocale]];
    NSString *brand = [brands objectForKey:low];
    if (brand != nil) return brand;
    if (low.length == 0) return low;
    // Только первое слово: «Об этом устройстве», а не «Об Этом Устройстве».
    NSString *head = [[low substringToIndex:1] uppercaseStringWithLocale:[NSLocale currentLocale]];
    return [head stringByAppendingString:[low substringFromIndex:1]];
}


@implementation MPSettingsHeaderView {
    UILabel *_small;
    UILabel *_big;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];

        _big = [[UILabel alloc] initWithFrame:CGRectZero];
        _big.font = [MPMetroStyle lightFont:52.0f];
        _big.textColor = [UIColor whiteColor];
        _big.backgroundColor = [UIColor clearColor];
        _big.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _big.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_big];

        // Стрелки «‹» в шапке больше нет (просьба 28.10): только типографика,
        // а «Назад» остаётся действием тапа по всей шапке (жест + кнопка ниже).

        // вся шапка — кнопка «Назад»: и жест, и прозрачная кнопка.
        // Жест на tableHeaderView срабатывал не всегда, кнопка надёжнее.
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(headerTapped)];
        [self addGestureRecognizer:tap];

        UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
        backButton.frame = self.bounds;
        backButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        backButton.backgroundColor = [UIColor clearColor];
        [backButton addTarget:self action:@selector(headerTapped)
             forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:backButton];
    }
    return self;
}

- (void)headerTapped {
    // защита от двойного срабатывания: жест и кнопка могут прийти вместе
    static NSTimeInterval lastTap = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - lastTap < 0.5) return;
    lastTap = now;
    MPLog(@"[Settings] шапка: тап (%@)", self.backTapped != nil ? @"обработчик есть" : @"обработчика нет");
    if (self.backTapped != nil) self.backTapped();
}

- (void)setPageTitle:(NSString *)pageTitle {
    _pageTitle = MPDisplayTitle(pageTitle);
    _big.text = _pageTitle;
    [self setNeedsLayout];
    [self shrinkTitleFont];
}

// ручной подбор размера: adjustsFontSizeToFitWidth на iOS 6 ненадёжен для
// динамически меняющегося текста — ужимаем от 52 до 30 pt по фактической ширине
- (BOOL)titleFitsAtSize:(CGFloat)size width:(CGFloat)w {
    return [_pageTitle sizeWithFont:[MPMetroStyle lightFont:size]].width <= w + 1.0f;
}

- (void)shrinkTitleFont {
    CGFloat w = self.bounds.size.width;
    if (w < 10.0f) w = 320.0f;                 // до первого layoutSubviews
    w -= [self bigLeftOffset] + 22.0f;         // 2B: правое поле 12 pt + запас
    CGFloat size = 52.0f;
    BOOL found = NO;
    for (CGFloat s = 52.0f; s >= 38.0f; s -= 2.0f) {      // 10B: обычный минимум 38
        if ([self titleFitsAtSize:s width:w]) { size = s; found = YES; break; }
    }
    if (!found) {
        // Длинные системные имена («iTunes и App Store») при 38 pt всё равно не влезают.
        // По 158A текст не сокращаем, поэтому ужимаем дальше до 30 — лучше мельче, чем обрез.
        for (CGFloat s = 36.0f; s >= 30.0f; s -= 2.0f) {
            if ([self titleFitsAtSize:s width:w]) { size = s; found = YES; break; }
        }
        if (!found) size = 30.0f;
    }
    UIFont *f = [MPMetroStyle lightFont:size];
    if (![_big.font isEqual:f]) {
        _big.font = f;
        [_big setNeedsDisplay];
    }
}

- (CGFloat)bigLeftOffset {
    // Без стрелки отступ один на всех страницах — 16 pt, как у строк списка.
    return 16.0f;
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    // 76 pt — сам заголовок; +20 pt воздуха до первой группы (1B).
    // Текст рисуется в верхних 66 pt (см. layoutSubviews), поэтому добавка
    // работает как отступ под заголовком, а не как рост шрифта.
    return 96.0f;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;

    CGFloat bigTop = 24.0f;    // как в сборках до правок: заголовок ниже статус-бара на 24 pt
    CGFloat bigH = 66.0f;      // фиксировано: добавка высоты — это воздух под текстом

    _big.frame = CGRectMake([self bigLeftOffset], bigTop, w - [self bigLeftOffset], bigH);
    [self shrinkTitleFont];
}

- (void)setShowsBackChevron:(BOOL)showsBackChevron {
    // Стрелка убрана из вида, но флаг оставлен: вызывающий код помечает им подстраницу.
    // Выход по-прежнему работает — тап по всей шапке (жест + прозрачная кнопка).
    _showsBackChevron = showsBackChevron;
    [self setNeedsLayout];
}

@end
