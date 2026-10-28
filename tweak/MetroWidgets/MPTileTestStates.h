#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

// ТЕСТОВАЯ плитка «Состояния»: каждый тик (10 с) циклически меняет состояние
// Ready → Ready → Error → Empty → … Проверяет изоляцию сбоев (после Error плитка
// сама возвращается в Ready), бэкофф планировщика (после ошибки интервал ×2),
// отрисовку «!» при ошибке и подписи при Empty. Убрать перед релизом — см.
// MPTileTestCounter.h.
@interface MPTileTestStates : NSObject <MPLiveTileProvider>
@end
