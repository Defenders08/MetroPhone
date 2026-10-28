#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// Виджет «Сейчас играет»: обложка, название, исполнитель из MPUNowPlayingController
// (частный API iOS 6, доступ только через objc_getClass + respondsToSelector).
// 1×1 — обложка или глиф ноты; 2×1 — обложка + название; 2×2 — обложка
// во всю плитку + название/исполнитель. Тап запускает приложение-плеер.
// Если MPUNowPlayingController в системе нет, плитка не регистрируется вовсе.
@interface MPTileNowPlaying : NSObject <MPLiveTileProvider>
+ (BOOL)isAvailable;   // YES — контроллер now playing есть в этом процессе
@end
