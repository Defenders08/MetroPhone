#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// Планировщик живых плиток: у каждого виджета свой интервал, обновления
// запускаются только когда виджет виден, а при выключенном экране тик
// встаёт на паузу целиком.
//
// Изоляция: получение данных — на ФОНОВОЙ серийной очереди (в @autoreleasepool
// и @try); отрисовка и все решения — на главном потоке; провайдер, не
// ответивший за 15 с, помечается ошибкой (сторож), его поздний ответ
// отбрасывается по счётчику поколений; после подряд трёх сбоев — бэкофф
// до 10 минут. Таймер один, живёт в процессе (ссылка держится в ivar,
// как MPHeartbeatSource в Tweak.xm) — утечек нет.
@interface MPLiveTileScheduler : NSObject

+ (MPLiveTileScheduler *)sharedScheduler;

// Создаёт тик (1 с на главном потоке). Повторный вызов ничего не делает.
- (void)start;

// Регистрация виджета. Все блоки вызываются на главном потоке:
//   visible — виден ли сейчас хоть один экземпляр виджета (решает центр по вьюхам);
//   apply    — применить контент ко всем вьюхам виджета; content == nil значит
//              «данные просрочены» (приглушить показанное).
- (void)registerTile:(NSString *)tileID
            provider:(id<MPLiveTileProvider>)provider
                size:(MPLiveTileSize)size
            interval:(NSTimeInterval)interval
       visibleBlock:(BOOL (^)(void))visibleBlock
          applyBlock:(void (^)(MPLiveTileContent *content))applyBlock;

- (void)unregisterTile:(NSString *)tileID;
- (void)unregisterAll;

// Экран погас/зажёгся (Darwin displayStatus): пауза без пробуждений.
- (void)setDisplayOn:(BOOL)on;

@end
