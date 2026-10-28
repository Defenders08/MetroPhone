// MPLiveTileSizeView — размер живых плиток на странице «Виджеты» настроек:
// строки «Название — 1×1 / 2×1 / 2×2», тап циклит размер. Пишет ключ
// liveTile.<id>.size (домен ru.ash.metrophone) и рассылает Darwin-уведомление
// «ru.ash.metrophone.livetiles-changed» — SpringBoard применяет на лету.

#import <UIKit/UIKit.h>

@interface MPLiveTileSizeView : UIView

+ (CGFloat)heightForWidth:(CGFloat)width;   // высота футера для ширины таблицы

- (void)refreshValues;                      // перечитать размеры из настроек

@end
