#import "MPTileView.h"
#import "MPMetroStyle.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - MPIconLoader

// Всё состояние загрузчика трогается только на главном потоке.
static NSCache             *MPIconMem     = nil;   // bundleID → UIImage
static NSMutableSet        *MPIconMisses  = nil;   // bundleID, для которых иконки нет
static NSMutableArray      *MPIconQueue   = nil;   // MPAppEntry, ожидающие запроса
static NSMutableDictionary *MPIconWaiters = nil;   // bundleID → NSMutableArray<блок>
static BOOL                 MPIconBusy    = NO;    // идёт ровно один запрос

@implementation MPIconLoader

+ (void)setupIfNeeded {
    if (MPIconMem != nil) return;
    MPIconMem     = [[NSCache alloc] init];
    MPIconMem.countLimit = 150;   // ~100 приложений списка + плитки; под давлением памяти NSCache эвиктирует сам
    MPIconMisses  = [NSMutableSet set];
    MPIconQueue   = [NSMutableArray array];
    MPIconWaiters = [NSMutableDictionary dictionary];
}

+ (void)loadIconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion {
    if (entry == nil || entry.bundleID.length == 0 || completion == NULL) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MPIconLoader loadIconForEntry:entry completion:completion];
        });
        return;
    }
    [self setupIfNeeded];

    NSString *bid = entry.bundleID;
    UIImage *cached = [MPIconMem objectForKey:bid];
    if (cached != nil) { completion(cached); return; }
    if ([MPIconMisses containsObject:bid]) { completion(nil); return; }

    NSMutableArray *waiters = [MPIconWaiters objectForKey:bid];
    if (waiters != nil) {                                   // такой запрос уже в очереди
        [waiters addObject:[completion copy]];
        return;
    }
    [MPIconWaiters setObject:[NSMutableArray arrayWithObject:[completion copy]] forKey:bid];
    [MPIconQueue addObject:entry];
    [self pump];
}

// Смена темы иконок: сброс кэшей, чтобы иконки перезагрузились заново
+ (void)clearCache {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [MPIconLoader clearCache]; });
        return;
    }
    [self setupIfNeeded];
    [MPIconMem removeAllObjects];
    [MPIconMisses removeAllObjects];
}

+ (void)pump {
    if (MPIconBusy || MPIconQueue.count == 0) return;
    MPAppEntry *entry = [MPIconQueue objectAtIndex:0];
    [MPIconQueue removeObjectAtIndex:0];
    MPIconBusy = YES;
    NSString *bid = entry.bundleID;

    [[MPAppDataSource sharedDataSource] iconForEntry:entry completion:^(UIImage *icon) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MPIconBusy = NO;
            if (icon != nil) [MPIconMem setObject:icon forKey:bid];
            else [MPIconMisses addObject:bid];

            NSArray *blocks = [MPIconWaiters objectForKey:bid];
            [MPIconWaiters removeObjectForKey:bid];
            for (id b in blocks) {
                ((void (^)(UIImage *))b)(icon);
            }
            [MPIconLoader pump];                            // следующий — только после завершения этого
        });
    }];
}

@end

#pragma mark - MPBadgeView

@implementation MPBadgeView {
    UILabel *_label;
    NSInteger _count;      // текущее число: нужно для дешёвой проверки «изменилось ли»
}

- (NSInteger)count { return _count; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, 20, 20)];
    if (self) {
        // В стиле проекта: плоский белый квадрат с тёмной цифрой (без скруглений)
        self.backgroundColor = [UIColor whiteColor];
        self.layer.cornerRadius = 0.0f;
        self.userInteractionEnabled = NO;
        self.hidden = YES;

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = [UIColor colorWithWhite:0.08f alpha:1.0f];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [MPMetroStyle mediumFont:12.0f];
        [self addSubview:_label];
    }
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size {
    NSString *t = _label.text ?: @"";
    // sizeThatFits зовётся из layoutSubviews каждой плитки: замер строки на каждый
    // проход × 45 плиток при каждом свапе. Текстов бейджа максимум ~100 («1»…«99+»)
    // — кэшируем ширину по тексту.
    static NSMutableDictionary *widthCache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ widthCache = [[NSMutableDictionary alloc] init]; });
    NSNumber *tw = widthCache[t];
    if (tw == nil) {
        tw = @(ceilf([t sizeWithFont:_label.font].width));
        widthCache[t] = tw;
    }
    return CGSizeMake(MAX(20.0f, tw.doubleValue + 10.0f), 20.0f);
}

- (void)setCount:(NSInteger)count {
    _count = count;
    if (count <= 0) {
        self.hidden = YES;
        _label.text = nil;
        return;
    }
    _label.text = (count > 99) ? @"99+" : [NSString stringWithFormat:@"%ld", (long)count];
    self.hidden = NO;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _label.frame = self.bounds;
}

@end

#pragma mark - MPTileView

@implementation MPTileView {
    UIImageView *_iconView;
    UILabel     *_letter;      // заглушка: первая буква имени
    MPBadgeView *_badge;
    NSString    *_displayName; // имя нужно только для заглушки-буквы
    CGFloat      _letterFontSize; // размер шрифта заглушки (ставим только при смене размера)
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [MPMetroStyle tileColor];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.backgroundColor = [UIColor clearColor];   // заглушка — буква на плитке, без серого квадрата
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];

        _letter = [[UILabel alloc] initWithFrame:CGRectZero];
        _letter.backgroundColor = [UIColor clearColor];
        _letter.textColor = [UIColor whiteColor];
        _letter.textAlignment = NSTextAlignmentCenter;
        [_iconView addSubview:_letter];

        _badge = [[MPBadgeView alloc] initWithFrame:CGRectZero];
        [self addSubview:_badge];
    }
    return self;
}

static NSString *MPFirstLetter(NSString *name) {
    if (name.length == 0) return @"?";
    NSRange r = [name rangeOfComposedCharacterSequenceAtIndex:0];
    return [[name substringWithRange:r] uppercaseString];
}

- (void)configureWithEntry:(MPAppEntry *)entry {
    self.bundleID = entry.bundleID;
    self.backgroundColor = [MPMetroStyle tileColor];
    self.fillsIcon = entry.themedFill;      // актуально уже при первом приходе иконки
    [self updateWithEntry:entry];

    _iconView.image = nil;
    _iconView.backgroundColor = [UIColor clearColor];
    _letter.hidden = NO;

    NSString *bid = entry.bundleID;
    __weak MPTileView *weakSelf = self;
    [MPIconLoader loadIconForEntry:entry completion:^(UIImage *icon) {
        MPTileView *tile = weakSelf;
        if (tile == nil || icon == nil) return;
        if (![tile.bundleID isEqualToString:bid]) return;
        tile.fillsIcon = entry.themedFill;  // резолв темы ставит флаг до отдачи иконки
        [tile setIcon:icon];
    }];
}

- (void)setIcon:(UIImage *)icon {
    _iconView.image = icon;
    _iconView.backgroundColor = [UIColor clearColor];
    _letter.hidden = YES;
    // Режим «на всю плитку» узнаётся в момент прихода иконки (themedFill):
    // без перекладки _iconView остаётся в кадре «60 % по центру» от первой раскладки
    [self setNeedsLayout];
}

// Обновление «на месте»: бейджи приходят пачками (noteBadgeDidChange),
// переукладка всех вьюх плитки дорога — трогаем только изменившееся.
- (void)updateWithEntry:(MPAppEntry *)entry {
    BOOL changed = NO;

    if (![entry.displayName isEqualToString:_displayName]) {
        _displayName = [entry.displayName copy];
        _letter.text = MPFirstLetter(entry.displayName);
    }
    if (_badge.count != entry.badge) {
        [_badge setCount:entry.badge];
        changed = YES;
    }
    if (changed) [self setNeedsLayout];
}

- (void)applyStyle {
    // сравниваем цвета: лишняя установка фона — это лишний проход отрисовки
    UIColor *color = [MPMetroStyle tileColor];
    if (![self.backgroundColor isEqual:color]) self.backgroundColor = color;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    // Иконка: пользовательские иконки и приложения без темы при fill-режиме —
    // на всю плитку (как живые плитки WP с картинкой); WP-иконки темы и
    // обычные — 60 % по центру (подписей на плитках нет, как в WP 8.1).
    // Широкая плитка (2 ячейки) — исключение: AspectFill квадратной иконки
    // кропает её до средней полосы (так выглядела «серая звезда во всю
    // широкую плитку»). На широких любая иконка стоит 60 % ВЫСОТЫ по центру
    // на фоне акцента — как плитки-логотипы в настоящем WP 8.1.
    BOOL wideTile = (w > h * 1.2f);
    CGFloat icon = floorf(MIN(w, h) * 0.60f);   // от меньшей стороны; размер нужен и для шрифта заглушки
    if (_fillsIcon && !wideTile) {
        UIViewContentMode want = UIViewContentModeScaleAspectFill;
        if (_iconView.contentMode != want) {
            _iconView.contentMode = want;
            _iconView.clipsToBounds = YES;
        }
        _iconView.frame = self.bounds;
    } else {
        UIViewContentMode want = UIViewContentModeScaleAspectFit;
        if (_iconView.contentMode != want) {
            _iconView.contentMode = want;
            _iconView.clipsToBounds = NO;
        }
        CGFloat iy = floorf((h - icon) / 2.0f);
        if (iy < 4.0f) iy = 4.0f;
        _iconView.frame = CGRectMake(floorf((w - icon) / 2.0f), iy, icon, icon);
    }
    _letter.frame = _iconView.bounds;
    // Шрифт заглушки зависит только от размера плитки: ставим при смене размера,
    // а не в каждом layoutSubviews (это строка-ключ + словарь шрифтов на плитку).
    CGFloat letterSize = floorf(icon * 0.62f);
    if (fabsf(_letterFontSize - letterSize) > 0.5f) {
        _letterFontSize = letterSize;
        _letter.font = [MPMetroStyle mediumFont:letterSize];
    }

    // Бейдж в правом верхнем углу; на мелкой сетке (плитка ~48 pt) непропорционально
    // крупный — сжимаем трансформой, позицию считаем от масштабированных габаритов.
    CGSize bs = [_badge sizeThatFits:CGSizeZero];
    CGFloat s = (w < 64.0f) ? 0.75f : 1.0f;
    CGAffineTransform t = (s == 1.0f) ? CGAffineTransformIdentity : CGAffineTransformMakeScale(s, s);
    if (!CGAffineTransformEqualToTransform(_badge.transform, t)) _badge.transform = t;
    _badge.bounds = CGRectMake(0.0f, 0.0f, bs.width, bs.height);
    _badge.center = CGPointMake(w - 4.0f - bs.width * s / 2.0f, 4.0f + bs.height * s / 2.0f);
}

#pragma mark - Парение (WP8.1: медленный вертикальный боб)

// Каждая плитка медленно поднимается-опускается со своей амплитудой, скоростью
// и фазой — мозаика «дышит» вразнобой. QuartzCore уже в FRAMEWORKS (Makefile).
- (void)startFloating {
    if ([self.layer animationForKey:@"mpFloat"] != nil) return;
    CGFloat duration  = 1.5f + (arc4random() % 10) / 10.0f;   // период 1,5–2,4 с
    CGFloat amplitude = 2.0f + (arc4random() % 10) / 10.0f;   // подъём 2,0–2,9 pt
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    a.fromValue = @(0.0f);
    a.toValue   = @(amplitude);
    a.duration  = duration;
    a.autoreverses = YES;
    a.repeatCount = HUGE_VALF;
    a.timeOffset = fmodf((arc4random() % 1000) / 1000.0f * duration, duration);   // сдвиг фазы
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.layer addAnimation:a forKey:@"mpFloat"];
}

- (void)stopFloating {
    [self.layer removeAnimationForKey:@"mpFloat"];
}

@end
