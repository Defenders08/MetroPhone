#import <UIKit/UIKit.h>

@class MPTileView;

// Хост редактора — страница плиток. Все индексы — позиции в массиве плиток (= порядок в модели).
// Все точки — в координатах содержимого вертикального скролла (locationInView: скролла).
@protocol MPTileEditorHost <NSObject>
- (NSInteger)editorTileCount;
- (MPTileView *)editorTileViewAtIndex:(NSInteger)index;
- (NSInteger)editorIndexOfTileAtPoint:(CGPoint)point excluding:(NSInteger)excluded;   // -1 если нет
- (CGRect)editorFrameForTileAtIndex:(NSInteger)index;
- (void)editorMoveTileFromIndex:(NSInteger)from toIndex:(NSInteger)to;                // модель + вьюхи + перепаковка
- (BOOL)editorCycleSizeAtIndex:(NSInteger)index;                                      // small → medium → wide (+ анимация)
- (void)editorRemoveTileAtIndex:(NSInteger)index;                                     // открепить плитку (excluded + анимация)
- (void)editorSetScrollLocked:(BOOL)locked;                                           // вкл/выкл скролл страницы
- (UIScrollView *)editorScrollView;
- (UIView *)editorTilesContainer;                                                     // контейнер плиток (маркеры поверх)
- (void)editorSave;                                                                   // запись plist
- (void)editorDidChangeEditing:(BOOL)editing;
@end

// Режим редактирования в стиле Windows Phone 8: выбранная плитка сжимается,
// у её нижних углов — круглые маркеры (слева размер, справа открепление).
// Остальные плитки стоят на местах; перетаскивание двигает выбранную,
// соседние плавно расступаются. Выход — тап по фону или повторный тап по выбранной.
@interface MPTileEditor : NSObject

@property (nonatomic, weak) id<MPTileEditorHost> host;
@property (nonatomic, readonly) BOOL editing;
@property (nonatomic, readonly, strong) MPTileView *draggingView;   // плитка под пальцем (страница не трогает её frame)

// Долгое нажатие на плитке: вход в режим правки с выбором этой плитки.
// Палец ещё держит плитку — её уже можно перетаскивать, не отпуская.
- (void)beginEditingSelectingTileAtIndex:(NSInteger)index point:(CGPoint)point;
- (void)endEditingAndSave;

// Страница сообщает после перепаковки/анимаций — маркеры едут за плиткой
- (void)hostDidLayoutTiles;

// Касания (страница пробрасывает сюда touchesBegan/Moved/Ended)
- (void)touchBeganAtPoint:(CGPoint)p;
- (void)touchMovedToPoint:(CGPoint)p;
- (void)touchEndedAtPoint:(CGPoint)p;
- (void)touchCancelled;

@end
