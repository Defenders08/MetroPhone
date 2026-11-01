#import <UIKit/UIKit.h>
#import "MPAppDataSource.h"

// ---- Загрузчик иконок для UI ----
// Контракт MPAppDataSource декодирует иконки на конкурентной глобальной очереди, а железное
// правило №3 требует серийности. Поэтому UI запрашивает иконки ТОЛЬКО через этот загрузчик:
// запросы выстраиваются в очередь и уходят в датасорс строго по одному; результат кэшируется в памяти.
// completion всегда вызывается на главном потоке (icon == nil → рисуй заглушку).
@interface MPIconLoader : NSObject
+ (void)loadIconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion;
+ (void)clearCache;   // сброс при смене темы иконок
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
@property (nonatomic, assign) BOOL fillsIcon;   // YES: иконка на всю плитку (тема иконок, fill-режим)

- (void)configureWithEntry:(MPAppEntry *)entry;   // буква-заглушка, бейдж, цвет, запрос иконки
- (void)updateWithEntry:(MPAppEntry *)entry;      // обновить заглушку/бейдж (без перезагрузки иконки)
- (void)applyStyle;                               // перечитать цвет плитки
- (void)startFloating;                            // парение WP8.1: боб с рандомной фазой (режим правки)
- (void)stopFloating;

- (void)pressTiltAtPoint:(CGPoint)pointInTile;    // tilt-нажатие WP: наклон к пальцу (3D, живой)
- (void)releaseTilt;                              // плавный возврат из наклона (0.2 с)

// Диагностика/сплэш запуска: текущая иконка плитки (nil — заглушка-буква)
- (UIImage *)mpIconImage;
// ДИАГНОСТИКА (временная): строка про фон RGBA, картинку и fill-режим —
// охота на «белые плитки» при въезде (снимается вместе с дампом в MPHomeController)
- (NSString *)mpLayerDiag;
@end
