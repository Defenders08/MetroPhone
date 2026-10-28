#import "MPTileTestCounter.h"
#import "MPLiveTileView.h"
#import "MetroLauncher/MPMetroStyle.h"

@implementation MPTileTestCounter

+ (NSString *)tileID     { return @"mp.widget.test.counter"; }
+ (NSString *)tileTitle  { return @"Тест: счётчик"; }
+ (NSArray *)supportedSizes {
    return @[@(MPLiveTileSizeCell), @(MPLiveTileSizeWide), @(MPLiveTileSizeLarge)];
}
+ (MPLiveTileSize)defaultSize { return MPLiveTileSizeLarge; }

- (NSTimeInterval)refreshIntervalForSize:(MPLiveTileSize)size {
    return 5.0;   // частые обновления — кроссфейд видно невооружённым глазом
}

- (NSString *)launchTarget { return nil; }   // тап обрабатывает handleTap

- (BOOL)handleTap {
    MPLog(@"тест-счётчик: тап обработан провайдером (handleTap)");
    return YES;
}

- (void)loadContentForSize:(MPLiveTileSize)size
                completion:(void (^)(MPLiveTileContent *))completion {
    static CFAbsoluteTime startedAt = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (startedAt == 0.0) startedAt = now;   // точка отсчёта — первое обновление
    NSTimeInterval uptime = now - startedAt;

    MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
    c.state = MPLiveTileStateReady;
    c.primaryText = (uptime < 90.0f)
        ? [NSString stringWithFormat:@"%.0f с", uptime]
        : [NSString stringWithFormat:@"%.0f мин", uptime / 60.0f];
    if (size == MPLiveTileSizeWide)  c.secondaryText = @"аптайм";
    if (size == MPLiveTileSizeLarge) {
        c.secondaryText = @"аптайм";
        c.footerText = [NSString stringWithFormat:@"%.0f с всего", uptime];
    }
    completion(c);
}

#pragma mark - Отрисовка

static UILabel *MPTestLabel(NSString *text, UIFont *font, CGFloat alpha) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = font;
    l.textColor = [UIColor colorWithWhite:1.0f alpha:alpha];
    l.backgroundColor = [UIColor clearColor];
    l.userInteractionEnabled = NO;
    return l;
}

- (void)renderContent:(MPLiveTileContent *)content
           inTileView:(UIView<MPLiveTileProviderRenderHost> *)tileView {
    UIView *container = [tileView contentContainer];
    CGFloat w = container.bounds.size.width, h = container.bounds.size.height;
    if (w < 8.0f || h < 8.0f) return;

    // 1×1: только число по центру
    if ([tileView liveTileSize] == MPLiveTileSizeCell) {
        UILabel *num = MPTestLabel(content.primaryText,
                                   [MPMetroStyle thinFont:floorf(h * 0.32f)], 1.0f);
        CGSize s = [num.text sizeWithFont:num.font];
        num.frame = CGRectMake(floorf((w - s.width) / 2.0f), floorf((h - s.height) / 2.0f),
                               ceilf(s.width) + 2.0f, ceilf(s.height));
        [container addSubview:num];
        return;
    }

    CGFloat inset = (w < 64.0f) ? 6.0f : 12.0f;
    CGFloat numSize = ([tileView liveTileSize] == MPLiveTileSizeLarge) ? floorf(h * 0.34f)
                                                                       : floorf(h * 0.40f);
    UILabel *num = MPTestLabel(content.primaryText, [MPMetroStyle thinFont:numSize], 1.0f);
    CGSize ns = [num.text sizeWithFont:num.font];
    num.frame = CGRectMake(inset, floorf((h - ns.height) / 2.0f) - floorf(h * 0.06f),
                           ceilf(ns.width) + 2.0f, ceilf(ns.height));
    [container addSubview:num];

    CGFloat y = CGRectGetMaxY(num.frame);
    if (content.secondaryText.length > 0) {
        UILabel *sub = MPTestLabel(content.secondaryText, [MPMetroStyle lightFont:14.0f], 0.85f);
        CGSize ss = [sub.text sizeWithFont:sub.font];
        sub.frame = CGRectMake(inset + 1.0f, y + 2.0f, ceilf(ss.width) + 2.0f, ceilf(ss.height));
        [container addSubview:sub];
        y = CGRectGetMaxY(sub.frame);
    }
    if (content.footerText.length > 0) {
        UILabel *foot = MPTestLabel(content.footerText, [MPMetroStyle lightFont:14.0f], 0.85f);
        CGSize fs = [foot.text sizeWithFont:foot.font];
        foot.frame = CGRectMake(inset + 1.0f, y, ceilf(fs.width) + 2.0f, ceilf(fs.height));
        [container addSubview:foot];
    }
}

@end
