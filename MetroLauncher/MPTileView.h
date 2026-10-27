#import <UIKit/UIKit.h>
#import "MPAppDataSource.h"

// ---- Загрузчик иконок для UI ----
// Контракт MPAppDataSource декодирует иконки на конкурентной глобальной очереди, а железное
// правило №3 требует серийности. Поэтому UI запрашивает иконки ТОЛЬКО через этот загрузчик:
// запросы выстраиваются в очередь и уходят в датасорс строго по одному; результат кэшируется в памяти.
// completion всегда вызывается на главном потоке (icon == nil → рисуй заглушку).
@interface MPIconLoader : NSObject
+ (void)loadIconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion;
@end

// ---- Красный кружок с числом (#E51400). Скрыт при count <= 0. ----
// Размер берётся из sizeThatFits:, позицию задаёт владелец.
@interface MPBadgeView : UIView
@property (nonatomic, readonly) NSInteger count;   // текущее число (readonly: ставится setCount:)
- (void)setCount:(NSInteger)count;
@end

// ---- Плитка ----
// userInteractionEnabled = NO: все касания обрабатывает страница плиток (touchesBegan/Moved/Ended).
@interface MPTileView : UIView
@property (nonatomic, copy) NSString *bundleID;

- (void)configureWithEntry:(MPAppEntry *)entry;   // имя, бейдж, цвет, запрос иконки
- (void)updateWithEntry:(MPAppEntry *)entry;      // обновить имя/бейдж (без перезагрузки иконки)
- (void)applyStyle;                               // перечитать цвет плитки
- (void)startShaking;                             // дрожание ±1° (режим правки)
- (void)stopShaking;
@end
