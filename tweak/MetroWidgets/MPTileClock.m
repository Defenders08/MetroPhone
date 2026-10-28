#import "MPTileClock.h"
#import "MPLiveTileView.h"
#import "MetroLauncher/MPMetroStyle.h"

// Форматирование времени как на локскрине: шаблон j:mm даёт 12/24-часовой
// формат по локали. NSDateFormatter дорог в создании — формат-строки кэшируются,
// сами форматтеры создаются один раз на провайдер (он существует в единственном
// экземпляре, данные идут с одной серийной фоновой очереди — потокобезопасно).
@implementation MPTileClock {
    NSDateFormatter *_timeFmt;
    NSDateFormatter *_cellTimeFmt;   // 1×1: без AM/PM
    NSDateFormatter *_weekdayFmt;
    NSDateFormatter *_dateFmt;
}

+ (NSString *)tileID     { return @"mp.widget.clock"; }
+ (NSString *)tileTitle  { return @"Часы"; }
+ (NSArray *)supportedSizes {
    return @[@(MPLiveTileSizeCell), @(MPLiveTileSizeWide), @(MPLiveTileSizeLarge)];
}
+ (MPLiveTileSize)defaultSize { return MPLiveTileSizeLarge; }

- (NSTimeInterval)refreshIntervalForSize:(MPLiveTileSize)size {
    return 15.0;   // минута никогда не «зависает» дольше 15 с
}

- (NSString *)launchTarget { return @"com.apple.mobiletimer"; }

- (void)ensureFormatters {
    if (_timeFmt != nil) return;
    NSLocale *locale = [NSLocale currentLocale];
    _timeFmt = [[NSDateFormatter alloc] init];
    _timeFmt.locale = locale;
    _timeFmt.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"j:mm" options:0 locale:locale];
    // 1×1 узкая (~75 pt): без дневного периода, иначе в 12-часовой локали
    // «12:45 PM» не влезает в ячейку
    _cellTimeFmt = [[NSDateFormatter alloc] init];
    _cellTimeFmt.locale = locale;
    _cellTimeFmt.dateFormat = [[NSDateFormatter dateFormatFromTemplate:@"j:mm" options:0 locale:locale]
        stringByReplacingOccurrencesOfString:@"a" withString:@""];
    _weekdayFmt = [[NSDateFormatter alloc] init];
    _weekdayFmt.locale = locale;
    _weekdayFmt.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEE" options:0 locale:locale];
    _dateFmt = [[NSDateFormatter alloc] init];
    _dateFmt.locale = locale;
    _dateFmt.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"dMMMM" options:0 locale:locale];
}

- (void)loadContentForSize:(MPLiveTileSize)size
                completion:(void (^)(MPLiveTileContent *))completion {
    [self ensureFormatters];
    NSDate *now = [NSDate date];

    MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
    c.state = MPLiveTileStateReady;
    c.primaryText = (size == MPLiveTileSizeCell) ? [_cellTimeFmt stringFromDate:now]
                                                 : [_timeFmt stringFromDate:now];
    if (size != MPLiveTileSizeCell) {
        c.secondaryText = [_weekdayFmt stringFromDate:now];
        if (size == MPLiveTileSizeLarge) c.footerText = [_dateFmt stringFromDate:now];
    }
    completion(c);
}

#pragma mark - Отрисовка

// Плоская типографика WP: крупное тонкое время слева, подписи светлым ниже
static UILabel *MPClockLabel(NSString *text, UIFont *font, CGFloat alpha) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = font;
    l.textColor = [UIColor colorWithWhite:1.0f alpha:alpha];
    l.backgroundColor = [UIColor clearColor];
    l.userInteractionEnabled = NO;
    l.lineBreakMode = NSLineBreakByClipping;
    return l;
}

- (void)renderContent:(MPLiveTileContent *)content
           inTileView:(UIView<MPLiveTileProviderRenderHost> *)tileView {
    UIView *container = [tileView contentContainer];
    CGFloat w = container.bounds.size.width, h = container.bounds.size.height;
    if (w < 8.0f || h < 8.0f) return;

    CGFloat inset = (w < 64.0f) ? 6.0f : 12.0f;

    if ([tileView liveTileSize] == MPLiveTileSizeCell) {
        // 1×1: только время по центру
        UILabel *time = MPClockLabel(content.primaryText,
                                     [MPMetroStyle thinFont:floorf(h * 0.34f)], 1.0f);
        CGSize s = [time.text sizeWithFont:time.font];
        time.frame = CGRectMake(floorf((w - s.width) / 2.0f), floorf((h - s.height) / 2.0f),
                                ceilf(s.width) + 2.0f, ceilf(s.height));
        [container addSubview:time];
        return;
    }

    // 2×1 и 2×2: время слева сверху, под ним день, ниже дата
    CGFloat timeSize = ([tileView liveTileSize] == MPLiveTileSizeLarge) ? floorf(h * 0.30f)
                                                                        : floorf(h * 0.40f);
    UILabel *time = MPClockLabel(content.primaryText, [MPMetroStyle thinFont:timeSize], 1.0f);
    CGSize ts = [time.text sizeWithFont:time.font];
    time.frame = CGRectMake(inset, floorf((h - ceilf(ts.height)) / 2.0f) - floorf(h * 0.06f),
                            ceilf(ts.width) + 2.0f, ceilf(ts.height));
    [container addSubview:time];

    CGFloat y = CGRectGetMaxY(time.frame);
    UILabel *weekday = MPClockLabel(content.secondaryText, [MPMetroStyle lightFont:14.0f], 0.85f);
    CGSize ws = [weekday.text sizeWithFont:weekday.font];
    weekday.frame = CGRectMake(inset + 1.0f, y + 2.0f, ceilf(ws.width) + 2.0f, ceilf(ws.height));
    [container addSubview:weekday];

    if (content.footerText.length > 0) {
        UILabel *date = MPClockLabel(content.footerText, [MPMetroStyle lightFont:14.0f], 0.85f);
        CGSize ds = [date.text sizeWithFont:date.font];
        date.frame = CGRectMake(inset + 1.0f, CGRectGetMaxY(weekday.frame),
                                ceilf(ds.width) + 2.0f, ceilf(ds.height));
        [container addSubview:date];
    }
}

@end
