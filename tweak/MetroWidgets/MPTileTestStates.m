#import "MPTileTestStates.h"
#import "MPLiveTileView.h"
#import "MetroLauncher/MPMetroStyle.h"

@implementation MPTileTestStates {
    NSInteger _tick;   // номер тика: фаза = тик % 4
}

+ (NSString *)tileID     { return @"mp.widget.test.states"; }
+ (NSString *)tileTitle  { return @"Тест: состояния"; }
+ (NSArray *)supportedSizes {
    return @[@(MPLiveTileSizeCell), @(MPLiveTileSizeWide), @(MPLiveTileSizeLarge)];
}
+ (MPLiveTileSize)defaultSize { return MPLiveTileSizeWide; }

- (NSTimeInterval)refreshIntervalForSize:(MPLiveTileSize)size {
    return 10.0;   // полный цикл состояний — 40 с
}

- (NSString *)launchTarget { return nil; }   // у тестовой плитки действия нет

// Фазы цикла: 1 и 2 — Ready, 3 — Error (вьюха покажет «!», планировщик включит
// бэкофф ×2), 0 — Empty (вьюха покажет подпись «нет данных»)
- (void)loadContentForSize:(MPLiveTileSize)size
                completion:(void (^)(MPLiveTileContent *))completion {
    _tick++;
    NSInteger phase = _tick % 4;

    if (phase == 3) {
        MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
        c.state = MPLiveTileStateError;
        c.primaryText = [NSString stringWithFormat:@"тик %ld — ошибка", (long)_tick];
        completion(c);
        return;
    }
    if (phase == 0) {
        MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
        c.state = MPLiveTileStateEmpty;
        c.footerText = @"нет данных";
        completion(c);
        return;
    }

    MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
    c.state = MPLiveTileStateReady;
    c.primaryText = [NSString stringWithFormat:@"%ld", (long)_tick];
    c.secondaryText = @"тик";
    if (size == MPLiveTileSizeLarge) c.footerText = @"готов";
    completion(c);
}

#pragma mark - Отрисовка (только Ready)

static UILabel *MPStatesLabel(NSString *text, UIFont *font, CGFloat alpha) {
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

    if ([tileView liveTileSize] == MPLiveTileSizeCell) {
        UILabel *num = MPStatesLabel(content.primaryText,
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
    UILabel *num = MPStatesLabel(content.primaryText, [MPMetroStyle thinFont:numSize], 1.0f);
    CGSize ns = [num.text sizeWithFont:num.font];
    num.frame = CGRectMake(inset, floorf((h - ns.height) / 2.0f) - floorf(h * 0.06f),
                           ceilf(ns.width) + 2.0f, ceilf(ns.height));
    [container addSubview:num];

    CGFloat y = CGRectGetMaxY(num.frame);
    if (content.secondaryText.length > 0) {
        UILabel *sub = MPStatesLabel(content.secondaryText, [MPMetroStyle lightFont:14.0f], 0.85f);
        CGSize ss = [sub.text sizeWithFont:sub.font];
        sub.frame = CGRectMake(inset + 1.0f, y + 2.0f, ceilf(ss.width) + 2.0f, ceilf(ss.height));
        [container addSubview:sub];
        y = CGRectGetMaxY(sub.frame);
    }
    if (content.footerText.length > 0) {
        UILabel *foot = MPStatesLabel(content.footerText, [MPMetroStyle lightFont:14.0f], 0.85f);
        CGSize fs = [foot.text sizeWithFont:foot.font];
        foot.frame = CGRectMake(inset + 1.0f, y, ceilf(fs.width) + 2.0f, ceilf(fs.height));
        [container addSubview:foot];
    }
}

@end
