#import "MPLayoutModel.h"
#import "MPAppDataSource.h"
#import "MPMetroStyle.h"

static NSString *const MPLayoutFilePath = @"/var/mobile/Library/Preferences/metrophone-layout.plist";

@implementation MPTileItem
@end

NSUInteger MPTileSpanX(MPTileSize size) { return (size == MPTileSizeSmall) ? 1 : (size == MPTileSizeMedium ? 2 : 4); }
NSUInteger MPTileSpanY(MPTileSize size) { return (size == MPTileSizeSmall) ? 1 : 2; }

// ---- Сетка занятости: массив рядов, каждый ряд — NSMutableData из `cols` байт ----
static BOOL MPCellsFree(NSArray *rows, NSInteger r, NSInteger c, NSInteger sx, NSInteger sy, NSInteger cols) {
    for (NSInteger rr = r; rr < r + sy; rr++) {
        if (rr >= (NSInteger)rows.count) continue;          // ряды за пределами — пустые
        const uint8_t *bytes = [[rows objectAtIndex:rr] bytes];
        for (NSInteger cc = c; cc < c + sx && cc < cols; cc++) {
            if (bytes[cc]) return NO;
        }
    }
    return YES;
}

static void MPMarkCells(NSMutableArray *rows, NSInteger r, NSInteger c, NSInteger sx, NSInteger sy, NSInteger cols) {
    while ((NSInteger)rows.count < r + sy) {
        [rows addObject:[NSMutableData dataWithLength:(NSUInteger)cols]];
    }
    for (NSInteger rr = r; rr < r + sy; rr++) {
        uint8_t *bytes = [[rows objectAtIndex:rr] mutableBytes];
        for (NSInteger cc = c; cc < c + sx && cc < cols; cc++) bytes[cc] = 1;
    }
}

@implementation MPLayoutModel {
    NSMutableArray *_items;
    NSMutableArray *_excluded;     // bid откреплённых плиток (живут в списке приложений)
    NSInteger _rowCount;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableArray array];
        _excluded = [NSMutableArray array];
        _rowCount = 0;
    }
    return self;
}

- (NSMutableArray *)items { return _items; }
- (NSInteger)rowCount { return _rowCount; }

+ (NSString *)layoutPath { return MPLayoutFilePath; }

+ (MPLayoutModel *)sharedModel {
    static MPLayoutModel *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[MPLayoutModel alloc] init]; });
    return shared;
}

#pragma mark - Чтение / запись

- (void)load {
    [_items removeAllObjects];
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:MPLayoutFilePath];
    NSArray *tiles = [root isKindOfClass:[NSDictionary class]] ? [root objectForKey:@"tiles"] : nil;
    NSArray *excl = [root isKindOfClass:[NSDictionary class]] ? [root objectForKey:@"excluded"] : nil;
    for (id e in [excl isKindOfClass:[NSArray class]] ? excl : @[]) {
        if ([e isKindOfClass:[NSString class]] && [(NSString *)e length] > 0) [_excluded addObject:e];
    }
    if (![tiles isKindOfClass:[NSArray class]]) {
        MPLog(@"раскладка: файла нет, будет раскладка по умолчанию");
        return;
    }
    NSMutableSet *seen = [NSMutableSet set];
    for (id d in tiles) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        NSString *bid = [d objectForKey:@"bid"];
        if (![bid isKindOfClass:[NSString class]] || bid.length == 0 || [seen containsObject:bid]) continue;
        NSString *size = [d objectForKey:@"size"];
        MPTileItem *it = [[MPTileItem alloc] init];
        it.bundleID = bid;
        // миграция: старый "large" (2×2) — это теперь "medium"
        if (![size isKindOfClass:[NSString class]]) size = @"small";
        if ([size isEqualToString:@"large"]) size = @"medium";
        it.tileSize = ([size isEqualToString:@"medium"]) ? MPTileSizeMedium
                    : ([size isEqualToString:@"wide"]) ? MPTileSizeWide
                    : MPTileSizeSmall;
        [_items addObject:it];
        [seen addObject:bid];
    }
    MPLog(@"раскладка: прочитано тайлов %lu", (unsigned long)_items.count);
}

- (BOOL)save {
    NSMutableArray *tiles = [NSMutableArray arrayWithCapacity:_items.count];
    for (MPTileItem *it in _items) {
        NSString *sz = (it.tileSize == MPTileSizeMedium) ? @"medium"
                     : (it.tileSize == MPTileSizeWide) ? @"wide" : @"small";
        [tiles addObject:@{ @"bid": it.bundleID, @"size": sz }];
    }
    NSDictionary *root = @{ @"tiles": tiles, @"excluded": [NSArray arrayWithArray:_excluded] };
    BOOL ok = [root writeToFile:MPLayoutFilePath atomically:YES];
    MPLog(@"раскладка: сохранение %@ (тайлов %lu)",
          ok ? @"OK" : @"ОШИБКА", (unsigned long)tiles.count);
    return ok;
}

#pragma mark - Сверка с приложениями

- (BOOL)syncWithApps:(NSArray *)apps {
    if (apps.count == 0) return NO;   // модель SpringBoard ещё не готова — не трогаем раскладку

    NSMutableSet *appIDs = [NSMutableSet set];
    for (MPAppEntry *e in apps) [appIDs addObject:e.bundleID];

    BOOL changed = NO;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:apps.count];
    NSMutableSet *have = [NSMutableSet set];
    for (MPTileItem *it in _items) {
        if ([appIDs containsObject:it.bundleID]) {
            [kept addObject:it];
            [have addObject:it.bundleID];
        } else {
            changed = YES;                       // приложение удалено
        }
    }
    for (MPAppEntry *e in apps) {                // apps отсортирован по имени → новые по алфавиту
        if ([have containsObject:e.bundleID]) continue;
        if ([_excluded containsObject:e.bundleID]) continue;   // откреплённые не возвращаем
        MPTileItem *it = [[MPTileItem alloc] init];
        it.bundleID = e.bundleID;
        it.tileSize = MPTileSizeSmall;
        [kept addObject:it];
        [have addObject:e.bundleID];
        changed = YES;
    }
    if (changed) [_items setArray:kept];
    [self packWithColumns:MPMetroColumns];
    return changed;
}

#pragma mark - Упаковка «первое подходящее место»

- (void)packWithColumns:(NSInteger)cols {
    if (cols < 1) cols = 1;
    NSMutableArray *rows = [NSMutableArray array];
    for (MPTileItem *it in _items) {
        NSInteger sx = (NSInteger)MPTileSpanX(it.tileSize);
        NSInteger sy = (NSInteger)MPTileSpanY(it.tileSize);
        if (sx > cols) sx = cols;                     // узкий контейнер — деградация ширины
        BOOL placed = NO;
        for (NSInteger r = 0; !placed; r++) {
            for (NSInteger c = 0; c + sx <= cols; c++) {
                if (MPCellsFree(rows, r, c, sx, sy, cols)) {
                    MPMarkCells(rows, r, c, sx, sy, cols);
                    it.row = r;
                    it.col = c;
                    placed = YES;
                    break;
                }
            }
        }
    }
    _rowCount = (NSInteger)rows.count;
}

#pragma mark - Правка

- (void)moveItemFromIndex:(NSInteger)from toIndex:(NSInteger)to {
    NSInteger n = (NSInteger)_items.count;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    MPTileItem *it = [_items objectAtIndex:from];
    [_items removeObjectAtIndex:from];
    [_items insertObject:it atIndex:to];
    [self packWithColumns:MPMetroColumns];
}

#pragma mark - Открепление / закрепление

- (void)excludeBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return;
    for (MPTileItem *it in _items) {
        if ([it.bundleID isEqualToString:bundleID]) {
            [_items removeObject:it];
            break;
        }
    }
    if (![_excluded containsObject:bundleID]) [_excluded addObject:bundleID];
    [self packWithColumns:MPMetroColumns];
}

- (void)pinBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return;
    [_excluded removeObject:bundleID];
    BOOL have = NO;
    for (MPTileItem *it in _items) {
        if ([it.bundleID isEqualToString:bundleID]) { have = YES; break; }
    }
    if (!have) {
        MPTileItem *it = [[MPTileItem alloc] init];
        it.bundleID = bundleID;
        it.tileSize = MPTileSizeSmall;
        [_items addObject:it];
    }
    [self packWithColumns:MPMetroColumns];
}

- (BOOL)isBundleIDExcluded:(NSString *)bundleID {
    return [_excluded containsObject:bundleID];
}

- (BOOL)cycleSizeAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_items.count) return NO;
    MPTileItem *it = [_items objectAtIndex:index];
    // small → medium → wide → small
    it.tileSize = (it.tileSize == MPTileSizeSmall) ? MPTileSizeMedium
               : (it.tileSize == MPTileSizeMedium) ? MPTileSizeWide
               : MPTileSizeSmall;
    [self packWithColumns:MPMetroColumns];
    return YES;
}

@end
