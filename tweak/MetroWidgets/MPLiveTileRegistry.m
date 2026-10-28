#import "MPLiveTileRegistry.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

// Регистрация идёт в потоке %ctor, чтение — из main; статические коллекции
// защищаем общим локом (пути холодные, цена блокировки нулевая).
static id MPRegistryLock = nil;      // id(NSObject) как мьютекс
static NSMutableArray *MPClasses  = nil;   // Class, реализующий MPLiveTileProvider
static NSMutableArray *MPInstaces = nil;   // id<MPLiveTileProvider>, параллельно классам

@implementation MPLiveTileRegistry

+ (void)initialize {
    if (self == [MPLiveTileRegistry class]) {
        MPRegistryLock = [[NSObject alloc] init];
        MPClasses  = [[NSMutableArray alloc] init];
        MPInstaces = [[NSMutableArray alloc] init];
    }
}

+ (void)registerClass:(Class)cls {
    if (cls == Nil) return;
    if (![cls conformsToProtocol:@protocol(MPLiveTileProvider)]) return;
    NSString *tileID = [cls tileID];
    if (tileID.length == 0) return;
    @synchronized (MPRegistryLock) {
        for (Class existing in MPClasses) {
            if ([[existing tileID] isEqualToString:tileID]) return;   // уже зарегистрирован
        }
        id<MPLiveTileProvider> provider = [[cls alloc] init];
        if (provider == nil) return;
        [MPClasses addObject:cls];
        [MPInstaces addObject:provider];
    }
}

+ (NSArray *)allProviders {
    @synchronized (MPRegistryLock) {
        return [NSArray arrayWithArray:MPInstaces];
    }
}

+ (id<MPLiveTileProvider>)providerForID:(NSString *)tileID {
    if (tileID.length == 0) return nil;
    @synchronized (MPRegistryLock) {
        for (id<MPLiveTileProvider> p in MPInstaces) {
            if ([[p tileID] isEqualToString:tileID]) return p;
        }
    }
    return nil;
}

+ (NSArray *)supportedSizesForTileID:(NSString *)tileID {
    id<MPLiveTileProvider> p = [self providerForID:tileID];
    if (p == nil) return @[];
    NSArray *sizes = [p supportedSizes] ?: @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:sizes.count];
    for (NSNumber *n in sizes) {
        if (![n isKindOfClass:[NSNumber class]]) continue;
        NSInteger v = [n integerValue];
        if (v < MPLiveTileSizeCell || v > MPLiveTileSizeLarge) continue;
        [out addObject:n];
    }
    return [out copy];
}

+ (BOOL)tileID:(NSString *)tileID supportsSize:(MPLiveTileSize)size {
    return [[self supportedSizesForTileID:tileID]
        containsObject:[NSNumber numberWithInteger:(NSInteger)size]];
}

+ (MPLiveTileSize)nextSizeAfter:(MPLiveTileSize)size forTileID:(NSString *)tileID {
    NSArray *sizes = [self supportedSizesForTileID:tileID];
    if (sizes.count < 2) return (MPLiveTileSize)-1;
    NSUInteger idx = [sizes indexOfObject:[NSNumber numberWithInteger:(NSInteger)size]];
    if (idx == NSNotFound || idx + 1 >= sizes.count) idx = 0;
    else idx += 1;
    return (MPLiveTileSize)[[sizes objectAtIndex:idx] integerValue];
}

+ (NSUInteger)scanExternalWidgetsDirectory:(NSString *)dir {
    // Точка расширения: сторонние виджеты (dylib/бандл в MP_WIDGETS_DIR) пока
    // только пересчитываются. Никакого dlopen: исполнение чужого кода в
    // SpringBoard — отдельное решение, загрузчик появится здесь же.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
    if (files.count > 0) {
        MPLog(@"живые плитки: в %@ найдено файлов %lu — загрузка сторонних виджетов пока не реализована",
              dir, (unsigned long)files.count);
    }
    return files.count;
}

@end
