// MPClockEditor — всплывающие редакторы pivot-часов: правка/создание будильника
// (пикер времени + дни недели + имя) и список добавления города мировых часов.

#import <UIKit/UIKit.h>
#import "MPClockData.h"

@interface MPClockEditor : UIView

+ (MPClockEditor *)sharedEditor;

// Показать редактор будильника поверх страницы (alarm == nil — новый).
// После закрытия страница перечитывается.
- (void)presentInPage:(UIView *)host alarm:(MPClockAlarm *)alarm;

// Список всех таймзон для добавления города
- (void)presentCityPickerInPage:(UIView *)host;

@end
