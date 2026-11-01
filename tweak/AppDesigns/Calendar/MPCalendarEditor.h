// MPCalendarEditor — полноэкранный оверлей добавления/редактирования события.
// Живёт на КОРНЕ пивота (не в ленте — иначе уедет со свайпом), по раскладке
// редактора будильника «Часов»: шапка light 52, поля, «сохранить/отмена/
// удалить». Поля MVP: название, начало, конец, весь день, календарь.

#import <UIKit/UIKit.h>
#import <EventKit/EventKit.h>

@class MPCalendarPivotView;

@interface MPCalendarEditor : UIView

+ (MPCalendarEditor *)sharedEditor;

// event == nil — новое событие; иначе правка существующего
- (void)presentInPivot:(MPCalendarPivotView *)pivot event:(EKEvent *)event;

@end
