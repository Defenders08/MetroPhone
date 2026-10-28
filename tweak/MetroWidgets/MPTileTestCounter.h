#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// ТЕСТОВАЯ плитка «Счётчик»: аптайм с момента первого обновления, тик каждые 5 с.
// Проверяет живые обновления данных и кроссфейд. Тап обрабатывается самим
// провайдером (демонстрация handleTap — в журнале видно «тап обработан»).
// Убрать перед релизом: регистрация в MPLiveTileCenter, строка в LiveTiles.plist,
// строка в футере размеров.
@interface MPTileTestCounter : NSObject <MPLiveTileProvider>
@end
