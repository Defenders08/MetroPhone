#import "MPSettingsHeaderView.h"

// Заголовок страницы: как было до правок — строчными («настройки», «основные»),
// но бренды сохраняют свой регистр (вопрос 124B: «Wi-Fi», «iCloud», «App Store»).
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
            @"2gis": @"2GIS",
        };
    });
    NSString *low = [raw lowercaseStringWithLocale:[NSLocale currentLocale]];
    NSString *brand = [brands objectForKey:low];
    return brand != nil ? brand : low;
}


@implementation MPSettingsHeaderView {
    UILabel *_small;
    UILabel *_big;
    UILabel *_chevron;
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

        _chevron = [[UILabel alloc] initWithFrame:CGRectZero];
        _chevron.text = @"\u2039";                       // ‹
        _chevron.font = [MPMetroStyle mediumFont:48.0f];  // 4B: крупнее и плотнее
        _chevron.textColor = [MPMetroStyle accentColor];
        _chevron.backgroundColor = [UIColor clearColor];
        _chevron.hidden = YES;
        [self addSubview:_chevron];

        // вся шапка — кнопка «Назад» (обработчик ставит хост)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(headerTapped)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)headerTapped {
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
    // Как было до правок: без шеврона (корень) — 16 pt, с шевроном — 40 pt.
    // По 5B делали «всегда 40», но на корне заголовок уезжал от левого края строк.
    return _chevron.hidden ? 16.0f : 40.0f;
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    // 76 pt — сам заголовок; +20 pt воздуха до первой группы (1B).
    // Текст рисуется в верхних 66 pt (см. layoutSubviews), поэтому добавка
    // работает как отступ под заголовком, а не как рост шрифта.
    return 96.0f;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _chevron.textColor = [MPMetroStyle accentColor];   // акцент может смениться на странице «Цвета»
    CGFloat w = self.bounds.size.width;

    CGFloat bigTop = 24.0f;    // как в сборках до правок: заголовок ниже статус-бара на 24 pt
    CGFloat bigH = 66.0f;      // фиксировано: добавка высоты — это воздух под текстом

    if (self.showsBackChevron) {
        _chevron.hidden = NO;
        _chevron.frame = CGRectMake(4.0f, bigTop + 2.0f, 34.0f, bigH);
        _big.frame = CGRectMake([self bigLeftOffset], bigTop, w - [self bigLeftOffset], bigH);
    } else {
        _chevron.hidden = YES;
        // место под шеврон остаётся занятым (5B), иначе заголовок прыгает влево
        _big.frame = CGRectMake([self bigLeftOffset], bigTop, w - [self bigLeftOffset], bigH);
    }
    [self shrinkTitleFont];
}

@end
