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
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, 20, 20)];
    if (self) {
        self.backgroundColor = [MPMetroStyle badgeColor];
        self.layer.cornerRadius = 10.0f;
        self.userInteractionEnabled = NO;
        self.hidden = YES;

        _label = [[UILabel alloc] initWithFrame:CGRectZero];
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = [UIColor whiteColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [MPMetroStyle mediumFont:12.0f];
        [self addSubview:_label];
    }
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size {
    NSString *t = _label.text ?: @"";
    CGFloat tw = ceilf([t sizeWithFont:_label.font].width);
    return CGSizeMake(MAX(20.0f, tw + 10.0f), 20.0f);
}

- (void)setCount:(NSInteger)count {
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
    UILabel     *_nameLabel;
    MPBadgeView *_badge;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [MPMetroStyle tileColor];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.backgroundColor = [MPMetroStyle placeholderColor];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];

        _letter = [[UILabel alloc] initWithFrame:CGRectZero];
        _letter.backgroundColor = [UIColor clearColor];
        _letter.textColor = [UIColor whiteColor];
        _letter.textAlignment = NSTextAlignmentCenter;
        [_iconView addSubview:_letter];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.textColor = [UIColor whiteColor];
        _nameLabel.textAlignment = NSTextAlignmentLeft;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.font = [MPMetroStyle lightFont:11.0f];
        [self addSubview:_nameLabel];

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
    [self updateWithEntry:entry];

    _iconView.image = nil;
    _iconView.backgroundColor = [MPMetroStyle placeholderColor];
    _letter.hidden = NO;

    NSString *bid = entry.bundleID;
    __weak MPTileView *weakSelf = self;
    [MPIconLoader loadIconForEntry:entry completion:^(UIImage *icon) {
        MPTileView *tile = weakSelf;
        if (tile == nil || icon == nil) return;
        if (![tile.bundleID isEqualToString:bid]) return;
        [tile setIcon:icon];
    }];
}

- (void)setIcon:(UIImage *)icon {
    _iconView.image = icon;
    _iconView.backgroundColor = [UIColor clearColor];
    _letter.hidden = YES;
}

- (void)updateWithEntry:(MPAppEntry *)entry {
    _nameLabel.text = [entry.displayName uppercaseString];
    _letter.text = MPFirstLetter(entry.displayName);
    [_badge setCount:entry.badge];
    [self setNeedsLayout];
}

- (void)applyStyle {
    self.backgroundColor = [MPMetroStyle tileColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat labelH = 14.0f;

    // Иконка: 55 % ширины плитки, по центру области над подписью
    CGFloat icon = floorf(w * 0.55f);
    CGFloat areaH = h - labelH - 6.0f;
    CGFloat iy = floorf((areaH - icon) / 2.0f);
    if (iy < 4.0f) iy = 4.0f;
    _iconView.frame = CGRectMake(floorf((w - icon) / 2.0f), iy, icon, icon);
    _letter.frame = _iconView.bounds;
    _letter.font = [MPMetroStyle mediumFont:floorf(icon * 0.5f)];

    _nameLabel.frame = CGRectMake(6.0f, h - labelH - 4.0f, w - 12.0f, labelH);

    CGSize bs = [_badge sizeThatFits:CGSizeZero];
    _badge.frame = CGRectMake(w - bs.width - 4.0f, 4.0f, bs.width, bs.height);
}

#pragma mark - Дрожание (CABasicAnimation, ±1°)

// CABasicAnimation берётся через NSClassFromString, чтобы не добавлять линковку QuartzCore в Makefile.
- (void)startShaking {
    if ([self.layer animationForKey:@"mpShake"] != nil) return;
    Class animClass = NSClassFromString(@"CABasicAnimation");
    if (animClass == Nil) return;
    CABasicAnimation *a = [animClass animationWithKeyPath:@"transform.rotation.z"];
    a.fromValue = @(-0.0175f);                 // ≈ −1°
    a.toValue   = @(0.0175f);                  // ≈ +1°
    a.duration  = 0.10 + (arc4random() % 40) / 1000.0;   // небольшой разброс — плитки дрожат вразнобой
    a.autoreverses = YES;
    a.repeatCount = HUGE_VALF;
    [self.layer addAnimation:a forKey:@"mpShake"];
}

- (void)stopShaking {
    [self.layer removeAnimationForKey:@"mpShake"];
}

@end
