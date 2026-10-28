#import "MPTileNowPlaying.h"
#import "MPLiveTileView.h"
#import "MetroLauncher/MPAppDataSource.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <objc/message.h>
#import <objc/runtime.h>

// Обёртки над MPUNowPlayingController без линковки MediaPlayer: класс ищется
// в рантайме, каждый селектор проверяется respondsToSelector — на прошивках,
// где чего-то нет, соответствующая часть просто отсутствует, без крэшей.
static id MPNPController(void) {
    Class cls = objc_getClass("MPUNowPlayingController");
    if (cls == nil) return nil;
    for (NSString *selName in @[@"sharedInstance", @"sharedController"]) {
        SEL s = NSSelectorFromString(selName);
        if ([cls respondsToSelector:s]) {
            id v = ((id (*)(id, SEL))objc_msgSend)(cls, s);
            if (v != nil) return v;
        }
    }
    return [[cls alloc] init];
}

static id MPNPValue(id obj, NSString *selectorName) {
    if (obj == nil) return nil;
    SEL s = NSSelectorFromString(selectorName);
    if (![obj respondsToSelector:s]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(obj, s);
    } @catch (NSException *e) {
        return nil;
    }
}

static NSString *MPNPString(id obj, NSString *selectorName) {
    id v = MPNPValue(obj, selectorName);
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

@implementation MPTileNowPlaying

+ (BOOL)isAvailable {
    return (objc_getClass("MPUNowPlayingController") != nil);
}

+ (NSString *)tileID     { return @"mp.widget.nowplaying"; }
+ (NSString *)tileTitle  { return @"Сейчас играет"; }
+ (NSArray *)supportedSizes {
    return @[@(MPLiveTileSizeCell), @(MPLiveTileSizeWide), @(MPLiveTileSizeLarge)];
}
+ (MPLiveTileSize)defaultSize { return MPLiveTileSizeWide; }

- (NSTimeInterval)refreshIntervalForSize:(MPLiveTileSize)size {
    return 3.0;   // трек может смениться в любой момент
}

- (NSString *)launchTarget { return nil; }   // тап обрабатываем сами (handleTap)

- (BOOL)handleTap {
    // запускаем приложение-плеер, которое сейчас играет (или играло последним)
    NSString *playerID = MPNPString(MPNPController(), @"nowPlayingApplicationDisplayID");
    if (playerID.length == 0) return NO;
    @try {
        [[MPAppDataSource sharedDataSource] launchAppWithBundleID:playerID];
        return YES;
    } @catch (NSException *e) {
        return NO;
    }
}

- (void)loadContentForSize:(MPLiveTileSize)size
                completion:(void (^)(MPLiveTileContent *))completion {
    id info = MPNPValue(MPNPController(), @"nowPlayingInfo");
    if (info == nil) {
        MPLiveTileContent *empty = [[MPLiveTileContent alloc] init];
        empty.state = MPLiveTileStateEmpty;
        completion(empty);
        return;
    }

    NSString *title = MPNPString(info, @"title");
    NSString *artist = MPNPString(info, @"artist");
    UIImage *artwork = MPNPValue(info, @"artwork");
    if (![artwork isKindOfClass:[UIImage class]]) artwork = nil;

    if (title.length == 0 && artwork == nil) {
        // метаданных фактически нет — пустая плитка лучше, чем «(null)»
        MPLiveTileContent *empty = [[MPLiveTileContent alloc] init];
        empty.state = MPLiveTileStateEmpty;
        empty.footerText = @"Сейчас играет";
        completion(empty);
        return;
    }

    MPLiveTileContent *c = [[MPLiveTileContent alloc] init];
    c.state = MPLiveTileStateReady;
    c.primaryText = title ?: @"—";
    c.secondaryText = artist;
    c.image = artwork;
    completion(c);
}

#pragma mark - Отрисовка

static UILabel *MPNPLabel(NSString *text, UIFont *font, CGFloat alpha) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = font;
    l.textColor = [UIColor colorWithWhite:1.0f alpha:alpha];
    l.backgroundColor = [UIColor clearColor];
    l.userInteractionEnabled = NO;
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    return l;
}

// Обложка вписана в квадрат стороны side (2×1), либо во всю плитку кропом (2×2)
static UIImageView *MPNPArtwork(UIImage *image) {
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
    iv.image = image;
    iv.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    iv.userInteractionEnabled = NO;
    return iv;
}

- (void)renderContent:(MPLiveTileContent *)content
           inTileView:(UIView<MPLiveTileProviderRenderHost> *)tileView {
    UIView *container = [tileView contentContainer];
    CGFloat w = container.bounds.size.width, h = container.bounds.size.height;
    if (w < 8.0f || h < 8.0f) return;

    // 1×1: обложка целиком, без неё — глиф ноты
    if ([tileView liveTileSize] == MPLiveTileSizeCell) {
        if (content.image != nil) {
            UIImageView *iv = MPNPArtwork(content.image);
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.frame = container.bounds;
            [container addSubview:iv];
        } else {
            UILabel *note = MPNPLabel(@"\u266B", [MPMetroStyle lightFont:floorf(h * 0.42f)], 0.9f);
            CGSize s = [note.text sizeWithFont:note.font];
            note.textAlignment = NSTextAlignmentCenter;
            note.frame = CGRectMake(0.0f, floorf((h - s.height) / 2.0f), w, ceilf(s.height));
            [container addSubview:note];
        }
        return;
    }

    BOOL large = ([tileView liveTileSize] == MPLiveTileSizeLarge);

    // 2×2: обложка во всю плитку (кроп), подписи поверх внизу; 2×1: квадрат слева
    if (content.image != nil) {
        UIImageView *iv = MPNPArtwork(content.image);
        if (large) {
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.frame = container.bounds;
        } else {
            CGFloat side = h - 12.0f;
            iv.contentMode = UIViewContentModeScaleAspectFit;
            iv.frame = CGRectMake(6.0f, 6.0f, side, side);
        }
        [container addSubview:iv];
    } else if (large) {
        // без обложки крупная нота на фоне акцента
        UILabel *note = MPNPLabel(@"\u266B", [MPMetroStyle lightFont:floorf(h * 0.5f)], 0.5f);
        note.textAlignment = NSTextAlignmentCenter;
        note.frame = CGRectMake(0.0f, 0.0f, w, floorf(h * 0.7f));
        [container addSubview:note];
    }

    CGFloat inset = (w < 64.0f) ? 6.0f : 12.0f;
    CGFloat textX = large ? inset : (h + 2.0f);
    CGFloat textW = large ? (w - inset * 2.0f) : (w - textX - inset);
    CGFloat titleSize = large ? 18.0f : 15.0f;
    CGFloat y = large ? (h - inset - 40.0f) : floorf(h * 0.22f);

    UILabel *title = MPNPLabel(content.primaryText, [MPMetroStyle mediumFont:titleSize], 1.0f);
    CGSize ts = [title.text sizeWithFont:title.font constrainedToSize:CGSizeMake(textW, 40.0f)
                         lineBreakMode:NSLineBreakByTruncatingTail];
    title.frame = CGRectMake(textX, y, textW, ceilf(ts.height));
    [container addSubview:title];

    if (content.secondaryText.length > 0) {
        UILabel *artist = MPNPLabel(content.secondaryText, [MPMetroStyle lightFont:13.0f], 0.85f);
        CGSize as_ = [artist.text sizeWithFont:artist.font constrainedToSize:CGSizeMake(textW, 40.0f)
                              lineBreakMode:NSLineBreakByTruncatingTail];
        artist.frame = CGRectMake(textX, CGRectGetMaxY(title.frame) + 2.0f, textW, ceilf(as_.height));
        [container addSubview:artist];
    }
}

@end
