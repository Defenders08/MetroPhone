#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// Реестр провайдеров живых плиток. Новая плитка добавляется одним классом
// и одной строкой registerClass: (регистрация встроенных — в MPLiveTileCenter).
@interface MPLiveTileRegistry : NSObject

+ (void)registerClass:(Class)cls;                          // Class, реализующий MPLiveTileProvider

+ (NSArray *)allProviders;                                 // NSArray<id<MPLiveTileProvider>>

+ (id<MPLiveTileProvider>)providerForID:(NSString *)tileID;   // nil, если не зарегистрирован

+ (BOOL)tileID:(NSString *)tileID supportsSize:(MPLiveTileSize)size;

// Следующий поддерживаемый размер по циклу (для кнопки «↕» в редакторе);
// возвращает -1, если у плитки один размер.
+ (MPLiveTileSize)nextSizeAfter:(MPLiveTileSize)size forTileID:(NSString *)tileID;

// Задел на сторонние виджеты: скан папки MP_WIDGETS_DIR. Сейчас только считает
// файлы-кандидаты и пишет в журнал — сторонний код не исполняется. Когда-нибудь
// тело заменит загрузчик (dlopen бандла/dylib + регистрация классов, реализующих
// MPLiveTileProvider). Возвращает число найденных файлов.
+ (NSUInteger)scanExternalWidgetsDirectory:(NSString *)dir;

@end
