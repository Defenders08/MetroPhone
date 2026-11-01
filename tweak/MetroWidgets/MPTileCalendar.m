#import "MPTileCalendar.h"
#import "MPLiveTileView.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <EventKit/EventKit.h>

// Данные читаются в фоновой очереди планировщика (контракт loadContentForSize),
// поэтому EKEventStore создаём лениво прямо там — потокобезопасно, провайдер
// существует в единственном экземпляре.
@implementation MPTileCalendar {
    EKEventStore *_store;
}

+ (NSString *)tileID     { return @"mp.widget.calendar"; }
+ (NSString *)tileTitle  { return @"Календарь"; }
+ (NSArray *)supportedSizes {
    return @[@(MPLiveTileSizeCell), @(MPLiveTileSizeWide), @(MPLiveTileSizeLarge)];
}
+ (MPLiveTileSize)defaultSize { return MPLiveTileSizeWide; }

- (NSTimeInterval)refreshIntervalForSize:(MPLiveTileSize)size {
    return 60.0;   // минута: дата меняется редко, события — не чаще
}

- (NSString *)launchTarget { return @"com.apple.mobilecal"; }

- (void)loadContentForSize:(MPLiveTileSize)size
                completion:(void (^)(MPLiveTileContent *))completion {
    @try {
        if (_store == nil) _store = [[EKEventStore alloc] init];
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDate *now = [NSDate date];
        NSDateComponents *c = [cal components:NSDayCalendarUnit | NSMonthCalendarUnit
                                         | NSWeekdayCalendarUnit fromDate:now];
        NSArray *monthNames = [[NSDateFormatter alloc] init].standaloneMonthSymbols;
        NSArray *dayNames = [[NSDateFormatter alloc] init].weekdaySymbols;

        MPLiveTileContent *content = [[MPLiveTileContent alloc] init];
        content.state = MPLiveTileStateReady;
        content.primaryText = [NSString stringWithFormat:@"%ld",
                               (long)c.day];
        content.secondaryText = [NSString stringWithFormat:@"%@, %@",
                                 dayNames[c.weekday - 1],
                                 monthNames[c.month - 1]];

        // ближайшие события на 48 часов вперёд (начиная с текущей минуты)
        NSDate *from = now;
        NSDate *to = [now dateByAddingTimeInterval:48.0 * 3600.0];
        NSPredicate *p = [_store predicateForEventsWithStartDate:from endDate:to
                                                      calendars:nil];
        NSArray *events = [[_store eventsMatchingPredicate:p]
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id ev, NSDictionary *b) {
                EKEvent *e = (EKEvent *)ev;
                // аллдей показываем и когда он УЖЕ идёт (старт в прошлом,
                // но диапазон покрывает текущий момент)
                if (!e.allDay) return YES;
                return [e.startDate compare:from] != NSOrderedDescending &&
                       [e.endDate compare:from] == NSOrderedDescending;
            }]];
        events = [events sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [((EKEvent *)a).startDate compare:((EKEvent *)b).startDate];
        }];
        if (events.count > 0) {
            EKEvent *ev = events[0];
            NSDateFormatter *tf = [[NSDateFormatter alloc] init];
            [tf setDateStyle:NSDateFormatterNoStyle];
            [tf setTimeStyle:NSDateFormatterShortStyle];
            NSString *when = [tf stringFromDate:ev.startDate];
            content.footerText = ev.title.length
                ? [NSString stringWithFormat:@"%@ · %@", when, ev.title]
                : when;
        } else {
            content.footerText = @"нет событий";
        }
        completion(content);
    }
    @catch (NSException *e) {
        // EventKit недоступен — показываем хотя бы дату
        MPLiveTileContent *content = [[MPLiveTileContent alloc] init];
        content.state = MPLiveTileStateReady;
        NSDateComponents *c = [[NSCalendar currentCalendar] components:
                               NSDayCalendarUnit | NSMonthCalendarUnit fromDate:[NSDate date]];
        content.primaryText = [NSString stringWithFormat:@"%ld", (long)c.day];
        content.secondaryText = [[NSDateFormatter alloc] init].standaloneMonthSymbols[c.month - 1];
        completion(content);
    }
}

#pragma mark - Отрисовка

static UILabel *MPCalTileLabel(NSString *text, UIFont *font, CGFloat alpha) {
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
        // 1×1: число + месяц под ним
        UILabel *day = MPCalTileLabel(content.primaryText,
                                      [MPMetroStyle thinFont:floorf(h * 0.34f)], 1.0f);
        CGSize ds = [day.text sizeWithFont:day.font];
        day.frame = CGRectMake(floorf((w - ds.width) / 2.0f), floorf(h * 0.22f),
                               ceilf(ds.width) + 2.0f, ceilf(ds.height));
        [container addSubview:day];
        UILabel *month = MPCalTileLabel(content.secondaryText,
                                        [MPMetroStyle lightFont:13.0f], 0.85f);
        month.frame = CGRectMake(inset, CGRectGetMaxY(day.frame) + 2.0f,
                                 w - inset * 2.0f, 18.0f);
        month.textAlignment = NSTextAlignmentCenter;
        [container addSubview:month];
        return;
    }

    // 2×1 и 2×2: слева крупная дата, справа день недели + ближайшее событие
    CGFloat numSize = ([tileView liveTileSize] == MPLiveTileSizeLarge) ? floorf(h * 0.30f)
                                                                        : floorf(h * 0.42f);
    UILabel *num = MPCalTileLabel(content.primaryText, [MPMetroStyle thinFont:numSize], 1.0f);
    CGSize ns = [num.text sizeWithFont:num.font];
    num.frame = CGRectMake(inset, floorf((h - ns.height) / 2.0f) - floorf(h * 0.04f),
                           ceilf(ns.width) + 2.0f, ceilf(ns.height));
    [container addSubview:num];

    CGFloat x = CGRectGetMaxX(num.frame) + 12.0f;
    CGFloat tw = w - x - inset;
    if (tw < 30.0f) return;

    UILabel *wd = MPCalTileLabel(content.secondaryText, [MPMetroStyle lightFont:14.0f], 0.85f);
    wd.frame = CGRectMake(x, inset + 2.0f, tw, 18.0f);
    [container addSubview:wd];

    if (content.footerText.length > 0) {
        UILabel *ev = MPCalTileLabel(content.footerText,
                                     [MPMetroStyle lightFont:14.0f], 1.0f);
        ev.frame = CGRectMake(x, CGRectGetMaxY(wd.frame) + 4.0f, tw,
                              h - CGRectGetMaxY(wd.frame) - inset - 4.0f);
        ev.numberOfLines = ([tileView liveTileSize] == MPLiveTileSizeLarge) ? 3 : 2;
        ev.lineBreakMode = NSLineBreakByWordWrapping;
        [container addSubview:ev];
    }
}

@end
