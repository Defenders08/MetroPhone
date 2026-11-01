// MPClockData — данные «Часов». Родное приложение хранит всё в префах
// com.apple.mobiletimer (внутри процесса это [NSUserDefaults standardUserDefaults]):
//   cities  — массив {city:{timeZone, unlocalizedName, ...}, type}
//   Alarms  — массив {alarmId, title, hour, minute, daySetting, sound,
//                     soundType, allowsSnooze, lastModified, revision}
// Включённость будильника в префах НЕ хранится: звонят только
// UILocalNotification с userInfo[@"alarmId"] == alarmId — ими и управляем.
// После правок дёргаем у живого AlarmViewController
// handleUserPreferencesChangedWithScheduledLocalNotificationsRefresh: —
// нативный код пересобирает уведомления по префам.

#import <UIKit/UIKit.h>

@interface MPClockCity : NSObject
@property (nonatomic, copy) NSString *zoneID;   // «Europe/Moscow»
@property (nonatomic, copy) NSString *name;     // локализованное («Москва»)
@property (nonatomic, retain) NSTimeZone *zone;
+ (MPClockCity *)cityWithZoneID:(NSString *)zoneID;
- (NSInteger)hoursFromLocal;                    // сдвиг в часах от местного времени
- (NSString *)dayWord;                          // «сегодня»/«завтра»/«вчера» (для города)
@end

@interface MPClockAlarm : NSObject
@property (nonatomic, copy) NSString *alarmId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *sound;
@property (nonatomic, assign) NSInteger hour, minute, daySetting;
@property (nonatomic, assign) BOOL snooze;
@property (nonatomic, assign) BOOL isNew;       // ещё не записан в префы
- (BOOL)enabled;                                // есть живые нотификации
- (NSString *)repeatLabel;                      // «Однократно»/«Будни»/«Пн, Вт»
+ (NSString *)labelForDaySetting:(NSInteger)mask;
@end

@interface MPClockData : NSObject

// Мировые часы (порядок префов)
+ (NSArray *)cities;                            // MPClockCity
+ (void)addCityWithZoneID:(NSString *)zoneID;
+ (void)removeCityWithZoneID:(NSString *)zoneID;
+ (void)moveCityFromIndex:(NSUInteger)from toIndex:(NSUInteger)to;   // перетаскивание

// Будильники (порядок префов)
+ (NSArray *)alarms;                            // MPClockAlarm
+ (BOOL)setEnabled:(BOOL)on forAlarm:(MPClockAlarm *)alarm;
+ (void)upsertAlarm:(MPClockAlarm *)alarm;      // новый или правка существующего
+ (void)removeAlarm:(MPClockAlarm *)alarm;

// Нативный пересбор уведомлений (если AlarmViewController жив)
+ (void)notifyNativeRefresh;

@end
