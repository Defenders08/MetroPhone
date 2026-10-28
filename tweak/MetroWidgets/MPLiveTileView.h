#import <UIKit/UIKit.h>
#import "MetroLauncher/MPTileView.h"
#import "MPLiveTile.h"

// Вьюха живой плитки — наследник MPTileView, поэтому сетка, редактор и правка
// работают с ней без правок типов (draggingView и host-протокол — MPTileView).
// От провайдера здесь только отрисовка: состояния Loading/Error/Empty/Stale
// и кроссфейд смены данных берёт на себя база.
//
// userInteractionEnabled = NO, как у MPTileView: касания обрабатывает страница,
// тап по виджету она маршрутизирует в MPLiveTileCenter (запуск приложения).
@interface MPLiveTileView : MPTileView <MPLiveTileProviderRenderHost>

@property (nonatomic, copy, readonly)    NSString       *tileID;
@property (nonatomic, assign, readonly)  MPLiveTileSize  liveTileSize;
@property (nonatomic, assign, readonly)  MPLiveTileState state;
@property (nonatomic, copy)              NSString       *launchTarget;   // тап: bundleID/prefs-URL

- (instancetype)initWithTileID:(NSString *)tileID size:(MPLiveTileSize)size;

// Смена размера (редактор «↕»): виджет перерисовывается под новый размер сам.
- (void)setLiveTileSize:(MPLiveTileSize)size;

// Новый контент от планировщика (главный поток). Ready → рисует провайдер
// (с кроссфейдом, если Reduce Motion выключен); остальные состояния рисует база.
- (void)applyContent:(MPLiveTileContent *)content provider:(id<MPLiveTileProvider>)provider;

// Данные просрочены (планировщик был на паузе): приглушить показанное, не трогая его.
// YES — если приглушать было что (был Ready).
- (BOOL)markStale;

@end
