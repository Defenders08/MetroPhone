#import "MPTileBattery.h"
#import "MPLiveTileView.h"
#import "MetroLauncher/MPMetroStyle.h"

// UIDevice-батарея: мониторинг включается один раз на процесс. SpringBoard сам
// показывает батарею в статус-баре, так что чтение этих свойств в нём штатно.
@implementation MPTileBattery

+ (NSString *)tileID     { return @"mp.widget.battery"; }
+ (NSString *)tileTitle  { return @"Батарея"; }
+ (NSArray *)supportedSizes {
    return @[@(MPLiveTileSizeCell), @(MPLiveTileSizeWide), @(MPLiveTileSizeLarge)];
}
+ (MPLiveTileSize)defaultSize { return MPLiveTileSizeWide; }

- (NSTimeInterval)refreshIntervalForSize:(MPLiveTileSize)size {
    return 30.0;
}

- (NSString *)launchTarget { return @"prefs:root=General&path=Usage"; }

- (void)loadContentForSize:(MPLiveTileSize)size
                completion:(void (^)(MPLiveTileContent *))completion {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    });

    UIDevice *device = [UIDevice currentDevice];
    float raw = device.batteryLevel;                 // 0…1, -1 = нет данных
    if (raw < 0.0f) {
        MPLiveTileContent *err = [[MPLiveTileContent alloc] init];
        err.state = MPLiveTileStateError;
        completion(err);
        return;
    }

    NSInteger percent = (NSInteger)roundf(raw * 100.0f);
    if (percent > 100) percent = 100;

    MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
    c.state = MPLiveTileStateReady;
    c.primaryText = [NSString stringWithFormat:@"%ld%%", (long)percent];

    UIDeviceBatteryState st = device.batteryState;
    if (st == UIDeviceBatteryStateCharging)      c.secondaryText = @"Заряжается";
    else if (st == UIDeviceBatteryStateFull)     c.secondaryText = @"Полностью заряжен";
    else if (size == MPLiveTileSizeWide)         c.secondaryText = @"Батарея";
    else if (size == MPLiveTileSizeLarge)        c.secondaryText = @"Батарея";
    completion(c);
}

#pragma mark - Отрисовка

static UILabel *MPBatteryLabel(NSString *text, UIFont *font, CGFloat alpha) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = font;
    l.textColor = [UIColor colorWithWhite:1.0f alpha:alpha];
    l.backgroundColor = [UIColor clearColor];
    l.userInteractionEnabled = NO;
    return l;
}

// Полосатый индикатор: белая рамка и заливка по уровню (2×2)
- (void)drawLevelBarInView:(UIView *)container percent:(NSInteger)percent {
    CGFloat w = container.bounds.size.width;
    CGFloat inset = (w < 64.0f) ? 6.0f : 12.0f;
    CGFloat barW = w - inset * 2.0f;
    CGFloat barH = 10.0f;
    CGFloat y = container.bounds.size.height - inset - barH;

    UIView *frame = [[UIView alloc] initWithFrame:CGRectMake(inset, y, barW, barH)];
    frame.backgroundColor = [UIColor clearColor];
    frame.layer.borderColor = [[UIColor colorWithWhite:1.0f alpha:0.9f] CGColor];
    frame.layer.borderWidth = 1.5f;
    frame.userInteractionEnabled = NO;
    [container addSubview:frame];

    CGFloat fillW = MAX(2.0f, floorf((barW - 4.0f) * (CGFloat)percent / 100.0f));
    UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(2.0f, 2.0f, fillW, barH - 4.0f)];
    fill.backgroundColor = [UIColor whiteColor];
    fill.userInteractionEnabled = NO;
    [frame addSubview:fill];
}

- (void)renderContent:(MPLiveTileContent *)content
           inTileView:(UIView<MPLiveTileProviderRenderHost> *)tileView {
    UIView *container = [tileView contentContainer];
    CGFloat w = container.bounds.size.width, h = container.bounds.size.height;
    if (w < 8.0f || h < 8.0f) return;

    CGFloat inset = (w < 64.0f) ? 6.0f : 12.0f;
    // "78%" → 78: integerValue читает до первого нецифрового символа
    NSInteger percent = content.primaryText.integerValue;

    if ([tileView liveTileSize] == MPLiveTileSizeCell) {
        // 1×1: только проценты по центру
        UILabel *pct = MPBatteryLabel(content.primaryText,
                                      [MPMetroStyle lightFont:floorf(h * 0.30f)], 1.0f);
        CGSize s = [pct.text sizeWithFont:pct.font];
        pct.frame = CGRectMake(floorf((w - s.width) / 2.0f), floorf((h - s.height) / 2.0f),
                               ceilf(s.width) + 2.0f, ceilf(s.height));
        [container addSubview:pct];
        return;
    }

    UILabel *pct = MPBatteryLabel(content.primaryText,
                                  [MPMetroStyle thinFont:floorf(h * 0.38f)], 1.0f);
    CGSize s = [pct.text sizeWithFont:pct.font];
    pct.frame = CGRectMake(inset, floorf((h - s.height) / 2.0f) - floorf(h * 0.06f),
                           ceilf(s.width) + 2.0f, ceilf(s.height));
    [container addSubview:pct];

    if (content.secondaryText.length > 0) {
        UILabel *sub = MPBatteryLabel(content.secondaryText, [MPMetroStyle lightFont:14.0f], 0.85f);
        CGSize ss = [sub.text sizeWithFont:sub.font];
        sub.frame = CGRectMake(inset + 1.0f, CGRectGetMaxY(pct.frame) + 2.0f,
                               ceilf(ss.width) + 2.0f, ceilf(ss.height));
        [container addSubview:sub];
    }

    if ([tileView liveTileSize] == MPLiveTileSizeLarge) {
        [self drawLevelBarInView:container percent:percent];
    }
}

@end
