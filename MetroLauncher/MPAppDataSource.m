#import "MPAppDataSource.h"
#import "MPMetroStyle.h"
#import <objc/runtime.h>

NSString * const MPAppsChangedNotification = @"MPAppsChanged";

// ---- Приватные классы SpringBoard iOS 6.1 (сверены с дампом MP0w/iOS-Headers) ----
@interface SBIconController : NSObject
+ (id)sharedInstance;
- (id)model;
@end
@interface SBIconModel : NSObject
- (NSDictionary *)leafIconsByIdentifier;   // все листовые иконки (приложения + web-клипы)
@end
@interface SBIcon : NSObject
- (void)launch;                            // запуск приложения
- (int)badgeValue;
- (id)displayName;
- (NSString *)applicationBundleID;
- (id)application;                         // SBApplication (только у SBApplicationIcon)
- (UIImage *)getIconImage:(int)format;     // готовая иконка (для Weather/Calc/Clock/Clock и др.)
- (NSArray *)tags;                          // теги видимости: содержит "hidden" — приложение скрыто
@end
@interface SBApplication : NSObject
- (NSString *)path;                        // путь к .app бандлу
@end

// ---- Исходный квадратный PNG иконки из бандла (в iOS 6 иконки в бандлах — квадраты) ----
static NSCache *MPDsPngCache = nil;

static UIImage *MPDsIconForBundlePath(NSString *bundlePath) {
    if (bundlePath.length == 0) return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ MPDsPngCache = [[NSCache alloc] init]; });

    id cached = [MPDsPngCache objectForKey:bundlePath];
    if (cached != nil) return [cached isKindOfClass:[UIImage class]] ? cached : nil;

    UIImage *best = nil;
    @autoreleasepool {
        NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        if (info != nil) {
            NSMutableDictionary *candidates = [NSMutableDictionary dictionary];
            void (^consider)(NSString *) = ^(NSString *p) {
                if (p.length == 0 || [candidates objectForKey:p] != nil) return;
                if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                    UIImage *img = [UIImage imageWithContentsOfFile:p];
                    if (img != nil) [candidates setObject:img forKey:p];
                }
            };
            NSArray *iconFiles = nil;
            NSDictionary *primary = [info objectForKey:@"CFBundleIcons"][@"CFBundlePrimaryIcon"];
            if (primary != nil) iconFiles = [primary objectForKey:@"CFBundleIconFiles"];
            if (iconFiles == nil) iconFiles = [info objectForKey:@"CFBundleIconFiles"];
            NSMutableArray *names = [NSMutableArray arrayWithArray:iconFiles ?: @[]];
            NSString *legacy = [info objectForKey:@"CFBundleIconFile"];
            if (legacy != nil) [names addObject:legacy];
            for (NSString *name in names) {
                consider([bundlePath stringByAppendingPathComponent:name]);
                consider([bundlePath stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]]);
                consider([bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x.png", name]]);
                consider([bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x", name]]);
            }
            CGFloat bestPx = 0;
            for (UIImage *img in candidates.allValues) {
                CGFloat px = img.size.width * img.scale;
                if (px > bestPx) { bestPx = px; best = img; }
            }
        }
    }
    [MPDsPngCache setObject:(best ?: (id)[NSNull null]) forKey:bundlePath];
    return best;
}

static id MPDsFindIcon(NSString *bundleID); // объявление до использования ниже

static NSArray *MPDsCollectApps(void) {
    NSMutableArray *result = [NSMutableArray array];
    @try {
        id controller = [objc_getClass("SBIconController") sharedInstance];
        id model = [controller respondsToSelector:@selector(model)] ? [controller model] : nil;
        NSDictionary *leafs = [model respondsToSelector:@selector(leafIconsByIdentifier)]
            ? [model leafIconsByIdentifier] : nil;
        for (id icon in leafs.allValues) {
            if (![icon respondsToSelector:@selector(applicationBundleID)]) continue; // папки пропускаются
            NSString *bid = [icon applicationBundleID];
            if (bid.length == 0) continue;

            // скрытые системные (DemoApp, FieldTest и т.п.) не показываем:
            // SpringBoard помечает их тегом "hidden"
            NSArray *tags = ([icon respondsToSelector:@selector(tags)]) ? [(SBIcon *)icon tags] : nil;
            if ([tags containsObject:@"hidden"]) continue;

            MPAppEntry *e = [[MPAppEntry alloc] init];
            e.bundleID = bid;
            e.displayName = ([icon respondsToSelector:@selector(displayName)] && [icon displayName])
                ? [icon displayName] : bid;
            e.badge = [icon respondsToSelector:@selector(badgeValue)] ? [(SBIcon *)icon badgeValue] : 0;
            [result addObject:e];
        }
    } @catch (NSException *ex) {
        MPLog(@"[DataSource] сборка списка: %@ (%@)", ex.name, ex.reason);
    }
    // подстраховка: скрытые через SBAppTags в Info.plist (теги иконки могли не сказать)
    NSMutableArray *visible = [NSMutableArray array];
    for (MPAppEntry *e in result) {
        id sbIcon = MPDsFindIcon(e.bundleID);
        id app = ([sbIcon respondsToSelector:@selector(application)]) ? [sbIcon application] : nil;
        NSString *path = ([app respondsToSelector:@selector(path)]) ? [app path] : nil;
        NSDictionary *info = (path.length > 0)
            ? [NSDictionary dictionaryWithContentsOfFile:
                  [path stringByAppendingPathComponent:@"Info.plist"]]
            : nil;
        NSArray *sbTags = [info objectForKey:@"SBAppTags"];
        if ([sbTags containsObject:@"hidden"]) continue; // скрытое — мимо
        [visible addObject:e];
    }
    result = visible;

    [result sortUsingComparator:^(MPAppEntry *a, MPAppEntry *b) {
        return [a.displayName compare:b.displayName options:NSCaseInsensitiveSearch];
    }];
    return result;
}

static id MPDsFindIcon(NSString *bundleID) {
    id controller = [objc_getClass("SBIconController") sharedInstance];
    id model = [controller respondsToSelector:@selector(model)] ? [controller model] : nil;
    NSDictionary *leafs = [model respondsToSelector:@selector(leafIconsByIdentifier)]
        ? [model leafIconsByIdentifier] : nil;
    for (id icon in leafs.allValues) {
        if ([[icon applicationBundleID] isEqualToString:bundleID]) return icon;
    }
    return nil;
}

@implementation MPAppEntry
@end

@implementation MPAppDataSource

+ (MPAppDataSource *)sharedDataSource {
    static MPAppDataSource *ds = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ds = [[MPAppDataSource alloc] init]; });
    return ds;
}

- (NSArray *)allApps {
    return MPDsCollectApps();
}

- (MPAppEntry *)appWithBundleID:(NSString *)bundleID {
    for (MPAppEntry *e in [self allApps]) {
        if ([e.bundleID isEqualToString:bundleID]) return e;
    }
    return nil;
}

- (void)iconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion {
    if (entry == nil || completion == NULL) return;
    // СТРОГО серийная очередь: параллельные декодирования PNG на iOS 6/512 МБ
    // дают скачок памяти, и jetsam прибивает SpringBoard.
    static dispatch_queue_t MPDsIconQueue = nil;
    static dispatch_once_t MPDsIconOnce;
    dispatch_once(&MPDsIconOnce, ^{
        MPDsIconQueue = dispatch_queue_create("ru.ash.metrophone.icons", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(MPDsIconQueue, ^{
        @autoreleasepool {
            UIImage *icon = nil;
            @try {
                id sbIcon = MPDsFindIcon(entry.bundleID);
                id app = ([sbIcon respondsToSelector:@selector(application)]) ? [sbIcon application] : nil;
                NSString *path = ([app respondsToSelector:@selector(path)]) ? [app path] : nil;
                icon = MPDsIconForBundlePath(path);

                // У Погоды/Калькулятора/Часов/Календаря PNG-иконок в бандле нет —
                // их рисует код SpringBoard (SBIconClass). Просим готовую у SBIcon.
                if (icon == nil && sbIcon != nil) {
                    if ([sbIcon respondsToSelector:@selector(getIconImage:)]) {
                        icon = [(SBIcon *)sbIcon getIconImage:2];
                        if (icon == nil) icon = [(SBIcon *)sbIcon getIconImage:0];
                        if (icon != nil) {
                            MPLog(@"[DataSource] иконка от SpringBoard: %@ (%@)",
                                  entry.bundleID, NSStringFromCGSize(icon.size));
                        }
                    }
                }
            } @catch (NSException *ex) {
                MPLog(@"[DataSource] иконка %@: %@", entry.bundleID, ex);
            }
            completion(icon); // nil = рисуй заглушку (первая буква имени)
        }
    });
}

- (void)launchAppWithBundleID:(NSString *)bundleID {
    @try {
        id icon = MPDsFindIcon(bundleID);
        if ([icon respondsToSelector:@selector(launch)]) [icon launch];
    } @catch (NSException *ex) {
        MPLog(@"[DataSource] запуск %@: %@", bundleID, ex);
    }
}

@end
