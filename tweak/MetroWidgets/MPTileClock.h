#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// Виджет «Часы»: время, день недели и дата. 1×1 — время; 2×1 — время + день;
// 2×2 — крупные часы + день + дата. Тап открывает приложение «Часы».
@interface MPTileClock : NSObject <MPLiveTileProvider>
@end
