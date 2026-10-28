#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// Виджет «Батарея»: уровень заряда и состояние (заряжается / от сети).
// 1×1 — проценты; 2×1 — проценты + состояние; 2×2 — + индикатор-полоса.
// Тап открывает «Настройки → Основные → Использование».
@interface MPTileBattery : NSObject <MPLiveTileProvider>
@end
