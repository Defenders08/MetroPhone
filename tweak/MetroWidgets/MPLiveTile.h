#import <UIKit/UIKit.h>
#import "MetroLauncher/MPLayoutModel.h"   // MPTileSize — виджеты живут в общей сетке плиток

// Ядро живых плиток (виджетов): размеры, состояния, модель данных и протокол провайдера.
// Новая плитка = один класс с реализацией MPLiveTileProvider + одна строка регистрации
// в MPLiveTileCenter (см. registerBuiltInProviders).

// Размеры виджета в ячейках базовой сетки (4 или 6 колонок — ключ smallTiles).
// 2×1 добавлен специально для виджетов; плитки приложений его не получают.
typedef enum {
    MPLiveTileSizeCell   = 0,   // 1×1 — квадрат с одну ячейку
    MPLiveTileSizeWide   = 1,   // 2×1 — две ячейки шириной, одна высотой
    MPLiveTileSizeLarge  = 2,   // 2×2 — как MPTileSizeMedium у приложений
} MPLiveTileSize;

// Размеры виджета ↔ размеры элементов общей сетки (MPTileSize).
static inline MPTileSize MPLiveGridSize(MPLiveTileSize s) {
    switch (s) {
        case MPLiveTileSizeWide:  return MPTileSizeHalf;
        case MPLiveTileSizeLarge: return MPTileSizeMedium;
        default:                  return MPTileSizeSmall;
    }
}
static inline MPLiveTileSize MPLiveSizeFromGrid(MPTileSize g) {
    switch (g) {
        case MPTileSizeHalf:   return MPLiveTileSizeWide;
        case MPTileSizeMedium: return MPLiveTileSizeLarge;
        default:               return MPLiveTileSizeCell;
    }
}

// Состояние виджета. Рисование Loading/Error/Empty/Stale берёт на себя базовая
// вьюха (MPLiveTileView), провайдер рисует только Ready.
typedef enum {
    MPLiveTileStateLoading = 0,   // данных ещё нет (первый запуск)
    MPLiveTileStateReady   = 1,   // данные получены, отрисованы провайдером
    MPLiveTileStateError   = 2,   // провайдер упал или не ответил за отведённое время
    MPLiveTileStateEmpty   = 3,   // данных нет по смыслу (например, ничего не играет)
    MPLiveTileStateStale   = 4,   // показано старое Ready, обновление просрочено
} MPLiveTileState;

// Результат одного обновления виджета. Маленький короткоживущий объект:
// пара строк и картинка — никаких накоплениях кэшей на стороне провайдеров.
@interface MPLiveTileContent : NSObject
@property (nonatomic, assign) MPLiveTileState state;
@property (nonatomic, copy)   NSString *primaryText;    // главная строка (время, проценты)
@property (nonatomic, copy)   NSString *secondaryText;  // вторая строка (день, «Заряжается»)
@property (nonatomic, copy)   NSString *tertiaryText;   // третья строка (исполнитель)
@property (nonatomic, copy)   NSString *footerText;     // нижняя подпись (альбом, «Сейчас играет»)
@property (nonatomic, strong) UIImage  *image;          // картинка (обложка), вписывает вьюха
@end

// Минимальный хост для отрисовки: провайдер кладёт subviews сюда,
// за рамки виджета не выходит.
@protocol MPLiveTileProviderRenderHost <NSObject>
- (UIView *)contentContainer;         // контейнер контента (координаты = bounds виджета)
- (MPLiveTileSize)liveTileSize;       // текущий размер (1×1 / 2×1 / 2×2)
@end

// Провайдер виджета — источник данных и отрисовки. Живёт в единственном
// экземпляре (реестр создаёт его один раз), поэтому никакого состояния на
// экземпляр: всё, что зависит от размера, передаётся параметрами.
@protocol MPLiveTileProvider <NSObject>

// Устойчивый идентификатор («mp.widget.clock») — по нему живут настройки,
// раскладка и реестр вьюх.
+ (NSString *)tileID;

// Человекочитаемое название («Часы») — страница виджетов и Настройки.
+ (NSString *)tileTitle;

// Поддерживаемые размеры: NSArray<NSNumber *>(MPLiveTileSize). Размер по
// умолчанию в конфиге не может не входить в этот список.
+ (NSArray *)supportedSizes;

// Свой интервал обновления под размер (секунды).
- (NSTimeInterval)refreshIntervalForSize:(MPLiveTileSize)size;

// Получение данных. Вызывается на ФОНОВОЙ серийной очереди планировщика.
// completion нужно вызвать ровно один раз (можно с любого потока) —
// планировщик вернёт на главный поток; если провайдер не ответил за
// отведённое время, вьюха уйдёт в Error без него.
- (void)loadContentForSize:(MPLiveTileSize)size
                completion:(void (^)(MPLiveTileContent *content))completion;

// Отрисовка под размер. Главный поток, content.state == Ready.
// Провайдер строит свои subviews в контейнере виджета (см. MPLiveTileView
// contentContainer); старые subviews вьюха снимает сама.
- (void)renderContent:(MPLiveTileContent *)content
           inTileView:(UIView<MPLiveTileProviderRenderHost> *)tileView;

// Что открыть по тапу: bundleID приложения или prefs-URL. nil — без действия.
- (NSString *)launchTarget;

@optional
// Размер по умолчанию, если в настройках не задан или не поддерживается
// (без метода — 1×1).
+ (MPLiveTileSize)defaultSize;

// Тап по плитке: обработать самому (например, запустить текущий плеер).
// YES — тап обработан, launchTarget не используется. Вызывается на главном потоке.
- (BOOL)handleTap;

@end
