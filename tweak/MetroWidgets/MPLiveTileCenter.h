#import <Foundation/Foundation.h>
#import "MPLiveTile.h"

@class MPLiveTileView;

// Внутреннее уведомление SpringBoard «состав/размеры виджетов изменились»
// (смена настроек, размер из редактора, закрепление со страницы виджетов).
// Слушают страница плиток и страница виджетов.
extern NSString * const MPLiveWidgetsChangedNotification;

// Фасад живых плиток: старт из %ctor, конфигурация (CFPreferences), реестр
// слабых ссылок на вьюхи, действия страниц и редактора.
//
// Отказоустойчивость: start() целиком под @try; при любой ошибке ставится
// флаг «мёртв» и система молча не работает — без повторных попыток и бутлупа.
@interface MPLiveTileCenter : NSObject

+ (MPLiveTileCenter *)sharedCenter;

// Только SpringBoard; повторный вызов — no-op.
- (void)start;
- (BOOL)isRunning;

// Конфигурация (CFPreferences, без кэша — путь не горячий)
- (BOOL)isMasterOn;
- (BOOL)isTileEnabled:(NSString *)tileID;
- (MPLiveTileSize)sizeForTileID:(NSString *)tileID;
- (NSArray *)enabledWidgetIDs;   // NSString tileID; порядок = порядок на страницах
- (NSArray *)homeWidgets;        // @{ @"id": NSString, @"size": NSNumber } для стартовой сетки

// Вьюхи (слабые ссылки; таблица сама чистится при dealloc вьюхи)
- (void)registerView:(MPLiveTileView *)view;

// Действия страниц и редактора
- (void)launchTileView:(MPLiveTileView *)view;                          // тап по виджету
- (void)setSize:(MPLiveTileSize)size forTileID:(NSString *)tileID;      // «↕» в редакторе
- (void)setPinnedToHome:(BOOL)pinned forTileID:(NSString *)tileID;      // страница виджетов
- (void)reloadConfig;                                                   // Darwin-уведомление

@end
