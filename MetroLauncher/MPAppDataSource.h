#import <UIKit/UIKit.h>

// Одна запись приложения (папки не включаются — только приложения и web-клипы)
@interface MPAppEntry : NSObject
@property (nonatomic, copy)   NSString *bundleID;
@property (nonatomic, copy)   NSString *displayName;  // как есть, БЕЗ смены регистра
@property (nonatomic, assign) NSInteger badge;         // 0 = нет бейджа
@end

@interface MPAppDataSource : NSObject
+ (MPAppDataSource *)sharedDataSource;

// Быстрый список (без иконок — иконки грузятся лениво). Сортировка по displayName.
- (NSArray *)allApps;                                  // NSArray<MPAppEntry *>
- (MPAppEntry *)appWithBundleID:(NSString *)bundleID;

// Иконка декодируется в фоне и кэшируется; completion может прийти на любом потоке.
- (void)iconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion;

- (void)launchAppWithBundleID:(NSString *)bundleID;    // запуск приложения
@end

// Уведомление «список/бейджи изменились» (постится из хуков твика)
extern NSString * const MPAppsChangedNotification;
