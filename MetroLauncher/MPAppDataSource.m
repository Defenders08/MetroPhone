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

@implementation MPAppEntry
@end

// Кэш списка приложений.
//
// Сборка списка — самый дорогой вызов датасорса: обход всех листовых иконок
// SpringBoard (leafIconsByIdentifier отдаёт новый словарь при каждом вызове)
// плюс чтение Info.plist каждого приложения. А спрашивают его часто — показ
// лаунчера, обновление бейджей, каждая карточка свитчера (appWithBundleID:).
// Поэтому: результат держим до 2 с и сбрасываем по MPAppsChangedNotification,
// вердикт по SBAppTags запоминаем навсегда (на приложение), а пути бандлов
// собираем за один проход — загрузчику иконок они нужны без повторных обходов.
static const CFTimeInterval MPDsAppsCacheTTL = 2.0;

@implementation MPAppDataSource {
    NSArray             *_cachedApps;
    NSMutableDictionary *_entryByID;     // bundleID → MPAppEntry
    NSMutableDictionary *_pathByID;      // bundleID → путь к .app ("" = не нашли)
    NSMutableDictionary *_hiddenByID;    // bundleID → @YES/@NO (скрыто через SBAppTags)
    CFAbsoluteTime       _cachedAt;
}

+ (MPAppDataSource *)sharedDataSource {
    static MPAppDataSource *ds = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ds = [[MPAppDataSource alloc] init]; });
    return ds;
}

- (id)init {
    self = [super init];
    if (self) {
        _entryByID  = [[NSMutableDictionary alloc] init];
        _pathByID   = [[NSMutableDictionary alloc] init];
        _hiddenByID = [[NSMutableDictionary alloc] init];
        // любое изменение списка/бейджей делает кэш недействительным
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appsDidChange:)
                                                     name:MPAppsChangedNotification
                                                   object:nil];
        MPLog(@"[DataSource] создан");
    }
    return self;
}

- (void)appsDidChange:(NSNotification *)note {
    @synchronized (self) {
        _cachedApps = nil;
        _cachedAt = 0;
    }
}

#pragma mark - Сборка списка

// Путь бандла для иконки. Первый раз спрашиваем SpringBoard, дальше — из карты.
- (NSString *)cachedPathForIcon:(id)icon bundleID:(NSString *)bid {
    NSString *cached = [_pathByID objectForKey:bid];
    if (cached != nil) return cached.length > 0 ? cached : nil;

    NSString *path = nil;
    @try {
        id app = ([icon respondsToSelector:@selector(application)]) ? [icon application] : nil;
        path = ([app respondsToSelector:@selector(path)]) ? [app path] : nil;
    } @catch (NSException *ex) {
        path = nil;
    }
    [_pathByID setObject:(path ?: @"") forKey:bid];   // промах тоже кэшируем
    return path;
}

// Скрыто ли приложение через SBAppTags в Info.plist. Читаем plist один раз
// на приложение за всё время жизни процесса.
- (BOOL)isHiddenByAppTags:(NSString *)bid path:(NSString *)path {
    NSNumber *known = [_hiddenByID objectForKey:bid];
    if (known != nil) return [known boolValue];

    BOOL hidden = NO;
    if (path.length > 0) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                              [path stringByAppendingPathComponent:@"Info.plist"]];
        NSArray *sbTags = [info objectForKey:@"SBAppTags"];
        hidden = [sbTags isKindOfClass:[NSArray class]] && [sbTags containsObject:@"hidden"];
    }
    [_hiddenByID setObject:@(hidden) forKey:bid];
    return hidden;
}

// Один проход по иконкам: записи, пути бандлов и признак скрытости — за раз.
// Вызывать под @synchronized(self).
- (NSArray *)rebuildLocked {
    NSMutableArray *result = [NSMutableArray array];
    [_entryByID removeAllObjects];

    @try {
        id controller = [objc_getClass("SBIconController") sharedInstance];
        id model = [controller respondsToSelector:@selector(model)] ? [controller model] : nil;
        NSDictionary *leafs = [model respondsToSelector:@selector(leafIconsByIdentifier)]
            ? [model leafIconsByIdentifier] : nil;

        for (id icon in leafs.allValues) {
            @autoreleasepool {
                if (![icon respondsToSelector:@selector(applicationBundleID)]) continue; // папки пропускаются
                NSString *bid = [icon applicationBundleID];
                if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;

                // скрытые системные (DemoApp, FieldTest и т.п.) не показываем:
                // SpringBoard помечает их тегом "hidden"
                NSArray *tags = ([icon respondsToSelector:@selector(tags)]) ? [(SBIcon *)icon tags] : nil;
                if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) continue;

                NSString *path = [self cachedPathForIcon:icon bundleID:bid];
                if ([self isHiddenByAppTags:bid path:path]) continue;

                MPAppEntry *e = [[MPAppEntry alloc] init];
                e.bundleID = bid;
                e.displayName = ([icon respondsToSelector:@selector(displayName)] && [icon displayName])
                    ? [icon displayName] : bid;
                e.badge = [icon respondsToSelector:@selector(badgeValue)] ? [(SBIcon *)icon badgeValue] : 0;
                [result addObject:e];
                [_entryByID setObject:e forKey:bid];
            }
        }
    } @catch (NSException *ex) {
        MPLog(@"[DataSource] сборка списка: %@ (%@)", ex.name, ex.reason);
    }

    [result sortUsingComparator:^(MPAppEntry *a, MPAppEntry *b) {
        return [a.displayName compare:b.displayName options:NSCaseInsensitiveSearch];
    }];
    return result;
}

- (NSArray *)allApps {
    @synchronized (self) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (_cachedApps != nil && (now - _cachedAt) < MPDsAppsCacheTTL) return _cachedApps;
        _cachedApps = [self rebuildLocked];
        _cachedAt = CFAbsoluteTimeGetCurrent();
        return _cachedApps;
    }
}

- (MPAppEntry *)appWithBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return nil;
    @synchronized (self) {
        [self allApps];          // @synchronized рекурсивен: карта и список — под одной блокировкой
        return [_entryByID objectForKey:bundleID];
    }
}

- (NSString *)bundlePathForBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return nil;
    @synchronized (self) {
        NSString *cached = [_pathByID objectForKey:bundleID];
        if (cached != nil) return cached.length > 0 ? cached : nil;
    }
    // приложение появилось после сборки списка — ищем один раз
    id icon = MPDsFindIcon(bundleID);
    if (icon == nil) return nil;
    @synchronized (self) {
        return [self cachedPathForIcon:icon bundleID:bundleID];
    }
}

#pragma mark - Иконки и запуск

- (void)iconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion {
    if (entry == nil || completion == NULL) return;
    // Путь резолвим на потоке вызывающего: карта путей защищена @synchronized,
    // но в фоновой очереди нам нужен уже готовый NSString.
    NSString *path = [self bundlePathForBundleID:entry.bundleID];
    NSString *bundleID = [entry.bundleID copy];

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
                icon = MPDsIconForBundlePath(path);

                // У Погоды/Калькулятора/Часов/Календаря PNG-иконок в бандле нет —
                // их рисует код SpringBoard (SBIconClass). Просим готовую у SBIcon.
                if (icon == nil) {
                    id sbIcon = MPDsFindIcon(bundleID);
                    if (sbIcon != nil && [sbIcon respondsToSelector:@selector(getIconImage:)]) {
                        icon = [(SBIcon *)sbIcon getIconImage:2];
                        if (icon == nil) icon = [(SBIcon *)sbIcon getIconImage:0];
                        if (icon != nil) {
                            MPLog(@"[DataSource] иконка от SpringBoard: %@ (%@)",
                                  bundleID, NSStringFromCGSize(icon.size));
                        }
                    }
                }
            } @catch (NSException *ex) {
                MPLog(@"[DataSource] иконка %@: %@", bundleID, ex);
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

// Поиск иконки по bundleID (обход всех листовых). Нужен для запуска приложения
// и как редкий запасной путь для иконок — в горячих местах не используется.
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
