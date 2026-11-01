#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// Виджет «Календарь»: сегодняшняя дата + ближайшие события (EventKit).
// 1×1 — число и месяц; 2×1 — дата + ближайшее событие; 2×2 — дата + 2 события.
// Тап открывает приложение «Календарь».
@interface MPTileCalendar : NSObject <MPLiveTileProvider>
@end
