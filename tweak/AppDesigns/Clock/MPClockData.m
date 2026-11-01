#import "MPClockData.h"
#import <objc/message.h>
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

// Приватные методы, нужные static-функциям выше @implementation
@interface MPClockData ()
+ (NSString *)newAlarmId;
@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Работа с префами MobileTimer

// Внутри процесса MobileTimer standardUserDefaults == /var/mobile/Library/
// Preferences/com.apple.mobiletimer.plist — тот же файл, что читает родной код.
static NSUserDefaults *MPMT(void) {
    return [NSUserDefaults standardUserDefaults];
}

static void MPMTSync(void) {
    CFPreferencesAppSynchronize(CFSTR("com.apple.mobiletimer"));
}

static NSArray *MPCitiesRaw(void) {
    id v = [MPMT() objectForKey:@"cities"];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static NSArray *MPAlarmsRaw(void) {
    id v = [MPMT() objectForKey:@"Alarms"];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

// Записать массив будильников и пометить время изменения (как родной код)
static void MPSaveAlarmsRaw(NSArray *raw) {
    [MPMT() setObject:raw forKey:@"Alarms"];
    [MPMT() setObject:[NSDate date] forKey:@"AlarmsLastModified"];
    MPMTSync();
}

// Имя города из идентификатора зоны: «America/New_York» → «New York».
// Локализованное имя таймзоны через CF НЕ годится: даёт «Стандартное время…»
// и «GMT+03:00» вместо города. Названия берём из префов (unlocalizedName),
// здесь — фолбэк для новых городов.
static NSString *MPSimpleZoneName(NSTimeZone *zone) {
    NSString *idn = zone.name ?: @"";
    NSString *last = [idn lastPathComponent] ?: idn;
    return [last stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - MPClockCity

@implementation MPClockCity
@synthesize zoneID, name, zone;

+ (MPClockCity *)cityWithZoneID:(NSString *)zid {
    MPClockCity *c = [[MPClockCity alloc] init];
    c.zoneID = zid;
    c.zone = [NSTimeZone timeZoneWithName:zid];
    c.name = MPSimpleZoneName(c.zone);
    return c;
}

// Сколько часов город опережает наше местное время (по прототипу: (ч1−ч0+24)%24,
// затем к диапазону −12..+11)
- (NSInteger)hoursFromLocal {
    if (zone == nil) return 0;
    NSDate *now = [NSDate date];
    NSCalendar *here = [NSCalendar currentCalendar];
    NSCalendar *there = [NSCalendar currentCalendar];
    there.timeZone = zone;
    NSInteger hHere = [here components:NSHourCalendarUnit fromDate:now].hour;
    NSInteger hCity = [there components:NSHourCalendarUnit fromDate:now].hour;
    NSInteger d = (hCity - hHere + 24) % 24;
    if (d > 12) d -= 24;
    return d;
}

- (NSString *)dayWord {
    if (zone == nil) return @"";
    NSDate *now = [NSDate date];
    NSCalendar *here = [NSCalendar currentCalendar];
    NSCalendar *there = [NSCalendar currentCalendar];
    there.timeZone = zone;
    NSInteger localDay = [here components:NSDayCalendarUnit fromDate:now].day;
    NSInteger cityDay = [there components:NSDayCalendarUnit fromDate:now].day;
    if (cityDay == localDay) return @"сегодня";
    // завтра/вчера: разница календарных дней ±1 (города дальше не добавляются,
    // а сдвиг >12 ч уже нормализован)
    return (cityDay == localDay + 1 || (localDay >= 28 && cityDay == 1)) ? @"завтра" : @"вчера";
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - MPClockAlarm

@implementation MPClockAlarm
@synthesize alarmId, title, sound;
@synthesize hour, minute, daySetting, snooze, isNew;

+ (NSString *)labelForDaySetting:(NSInteger)mask {
    if (mask == 0) return @"Однократно";
    if (mask == 62) return @"Будни";        // Пн–Пт
    if (mask == 65) return @"Выходные";     // Вс+Сб
    if (mask == 127) return @"Каждый день";
    static NSString *names[7] = {@"Вс", @"Пн", @"Вт", @"Ср", @"Чт", @"Пт", @"Сб"};
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < 7; i++) {
        if (mask & (1 << i)) [out addObject:names[i]];
    }
    return [out componentsJoinedByString:@", "];
}

- (NSString *)repeatLabel {
    NSString *t = title;   // имя будильника важнее дней (как в родных Часах)
    if (t.length > 0) return t;
    return [MPClockAlarm labelForDaySetting:daySetting];
}

- (BOOL)enabled {
    for (UILocalNotification *n in [[UIApplication sharedApplication] scheduledLocalNotifications]) {
        NSString *aid = n.userInfo[@"alarmId"];
        if ([aid isKindOfClass:[NSString class]] && [aid isEqualToString:alarmId]) return YES;
    }
    return NO;
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Будильники: чтение/запись

static MPClockAlarm *MPAlarmFromDict(NSDictionary *d) {
    MPClockAlarm *a = [[MPClockAlarm alloc] init];
    id v;
    v = d[@"alarmId"];  if ([v isKindOfClass:[NSString class]]) a.alarmId = v;
    v = d[@"title"];    if ([v isKindOfClass:[NSString class]]) a.title = v;
    v = d[@"sound"];    if ([v isKindOfClass:[NSString class]]) a.sound = v;
    v = d[@"hour"];     if ([v respondsToSelector:@selector(integerValue)]) a.hour = [v integerValue];
    v = d[@"minute"];   if ([v respondsToSelector:@selector(integerValue)]) a.minute = [v integerValue];
    v = d[@"daySetting"]; if ([v respondsToSelector:@selector(integerValue)]) a.daySetting = [v integerValue];
    v = d[@"allowsSnooze"]; a.snooze = (v == nil) ? YES : [v boolValue];
    a.isNew = NO;
    return a;
}

static NSDictionary *MPDictFromAlarm(MPClockAlarm *a) {
    // формат записи повторяет родные префы (см. com.apple.mobiletimer.plist)
    return [@{
        @"alarmId": (a.alarmId ?: [MPClockData newAlarmId]),
        @"title": (a.title ?: @""),
        @"sound": (a.sound ?: @"<default>"),
        @"soundType": @1,
        @"allowsSnooze": @(a.snooze),
        @"hour": @(a.hour),
        @"minute": @(a.minute),
        @"daySetting": @(a.daySetting),
        @"lastModified": [NSDate date],
        @"revision": @1,
    } mutableCopy];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Нотификации будильников

// Нотификации одного будильника (мультидневный = несколько)
static NSArray *MPNotificationsForAlarm(MPClockAlarm *alarm) {
    NSMutableArray *out = [NSMutableArray array];
    for (UILocalNotification *n in [[UIApplication sharedApplication] scheduledLocalNotifications]) {
        NSString *aid = n.userInfo[@"alarmId"];
        if ([aid isKindOfClass:[NSString class]] && [aid isEqualToString:alarm.alarmId]) {
            [out addObject:n];
        }
    }
    return out;
}

// Ближайший момент ЧЧ:ММ в заданный день недели (weekday 0 — ближайший любой;
// 1=вс … 7=сб, как в NSCalendar)
static NSDate *MPNextFire(NSInteger hour, NSInteger minute, int weekday) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *today = [cal components:(NSYearCalendarUnit | NSMonthCalendarUnit |
                                               NSDayCalendarUnit | NSWeekdayCalendarUnit)
                                     fromDate:[NSDate date]];
    NSDateComponents *target = [[NSDateComponents alloc] init];
    target.hour = hour;
    target.minute = minute;
    target.second = 0;
    target.year = today.year;
    target.month = today.month;
    target.day = today.day + ((weekday > 0) ? (weekday - today.weekday + 7) % 7 : 0);
    NSDate *fire = [cal dateFromComponents:target];
    if (fire == nil || [fire compare:[NSDate date]] != NSOrderedDescending) {
        NSDateComponents *add = [[NSDateComponents alloc] init];
        add.day = (weekday > 0) ? 7 : 1;
        fire = [cal dateByAddingComponents:add toDate:(fire ?: [NSDate date]) options:0];
    }
    return fire;
}

static void MPRemoveNotifications(MPClockAlarm *alarm) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UILocalNotification *n in MPNotificationsForAlarm(alarm)) {
        [app cancelLocalNotification:n];
    }
}

static void MPScheduleNotifications(MPClockAlarm *alarm) {
    UIApplication *app = [UIApplication sharedApplication];
    // звук и формат берём с любой живой нотификации приложения (образец родного
    // кода); если их нет — дефолт без звука (нативный refresh поправит при случае)
    UILocalNotification *sample = nil;
    for (UILocalNotification *n in app.scheduledLocalNotifications) {
        sample = n;
        break;
    }
    NSMutableArray *days = [NSMutableArray array];
    if (alarm.daySetting == 0) {
        [days addObject:@0];   // однократно
    } else {
        for (int i = 0; i < 7; i++) {
            if (alarm.daySetting & (1 << i)) [days addObject:@(i + 1)];   // 1=вс … 7=сб
        }
    }
    for (NSNumber *wd in days) {
        UILocalNotification *n = [[UILocalNotification alloc] init];
        n.fireDate = MPNextFire(alarm.hour, alarm.minute, wd.intValue);
        n.repeatInterval = (alarm.daySetting == 0) ? 0 : NSWeekdayCalendarUnit;
        n.timeZone = [NSTimeZone defaultTimeZone];
        n.alertBody = alarm.title.length > 0 ? alarm.title : @"";
        n.soundName = sample.soundName;   // nil → системный звук по умолчанию
        n.userInfo = @{@"alarmId": (alarm.alarmId ?: [MPClockData newAlarmId])};
        [app scheduleLocalNotification:n];
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - MPClockData

@implementation MPClockData

+ (NSString *)newAlarmId {
    CFUUIDRef u = CFUUIDCreate(NULL);
    NSString *s = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, u);
    CFRelease(u);
    return s;
}

+ (NSArray *)cities {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *item in MPCitiesRaw()) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *c = item[@"city"];
        NSString *zid = c[@"timeZone"];
        if (![zid isKindOfClass:[NSString class]] || zid.length == 0) continue;
        MPClockCity *city = [MPClockCity cityWithZoneID:zid];
        // родное название города из префов («Moscow», «Omsk») — оно и в родных
        // Часах в списке; localized имя зоны вместо города не показываем
        NSString *prefName = c[@"unlocalizedName"];
        if ([prefName isKindOfClass:[NSString class]] && prefName.length > 0) {
            city.name = prefName;
        }
        [out addObject:city];
    }
    return out;
}

+ (void)addCityWithZoneID:(NSString *)zoneID {
    if (zoneID.length == 0) return;
    NSMutableArray *raw = [MPCitiesRaw() mutableCopy];
    for (NSDictionary *item in raw) {
        if ([item[@"city"][@"timeZone"] isEqualToString:zoneID]) return;   // уже есть
    }
    NSTimeZone *z = [NSTimeZone timeZoneWithName:zoneID];
    NSMutableDictionary *city = [@{
        @"timeZone": zoneID,
        @"unlocalizedName": MPSimpleZoneName(z),
        @"unlocalizedCountryName": @"",
        @"identifier": @0,
        @"latitude": @0.0,
        @"longitude": @0.0,
        @"yahooCode": @"",
        @"localeCode": @"",
    } mutableCopy];
    // погоду родные Часы не покажут (yahooCode пуст) — город и время честные
    [raw addObject:@{@"city": city, @"type": @2}];
    [MPMT() setObject:raw forKey:@"cities"];
    [MPMT() setObject:[NSDate date] forKey:@"citiesLastModified"];
    MPMTSync();
}

+ (void)removeCityWithZoneID:(NSString *)zoneID {
    NSMutableArray *raw = [MPCitiesRaw() mutableCopy];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *item in raw) {
        if ([item[@"city"][@"timeZone"] isEqualToString:zoneID]) continue;
        [out addObject:item];
    }
    [MPMT() setObject:out forKey:@"cities"];
    [MPMT() setObject:[NSDate date] forKey:@"citiesLastModified"];
    MPMTSync();
}

// Новый порядок городов после перетаскивания (порядок префов = порядок строк)
+ (void)moveCityFromIndex:(NSUInteger)from toIndex:(NSUInteger)to {
    NSMutableArray *raw = [MPCitiesRaw() mutableCopy];
    if (from >= raw.count || to >= raw.count || from == to) return;
    id item = [raw objectAtIndex:from];
    [raw removeObjectAtIndex:from];
    [raw insertObject:item atIndex:to];
    [MPMT() setObject:raw forKey:@"cities"];
    [MPMT() setObject:[NSDate date] forKey:@"citiesLastModified"];
    MPMTSync();
    MPLog(@"[Clock] город переставлен: %ld → %ld", (long)from, (long)to);
}

+ (NSArray *)alarms {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in MPAlarmsRaw()) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        MPClockAlarm *a = MPAlarmFromDict(d);
        if (a.alarmId == nil) continue;
        [out addObject:a];
    }
    return out;
}

+ (BOOL)setEnabled:(BOOL)on forAlarm:(MPClockAlarm *)alarm {
    if (alarm.alarmId == nil) return NO;
    BOOL was = alarm.enabled;
    if (on == was) return YES;
    if (on) {
        MPScheduleNotifications(alarm);
    } else {
        MPRemoveNotifications(alarm);
    }
    // отметка в префах, чтобы родной код видел изменение (сам флаг он не хранит)
    NSMutableArray *raw = [MPAlarmsRaw() mutableCopy];
    for (NSUInteger i = 0; i < raw.count; i++) {
        NSDictionary *d = raw[i];
        if ([d[@"alarmId"] isKindOfClass:[NSString class]] &&
            [d[@"alarmId"] isEqualToString:alarm.alarmId]) {
            NSMutableDictionary *m = [d mutableCopy];
            m[@"lastModified"] = [NSDate date];
            raw[i] = m;
        }
    }
    MPSaveAlarmsRaw(raw);
    [self notifyNativeRefresh];
    MPLog(@"[Clock] будильник %@: %@", alarm.alarmId, on ? @"включён" : @"выключен");
    return alarm.enabled == on;
}

+ (void)upsertAlarm:(MPClockAlarm *)alarm {
    NSMutableArray *raw = [MPAlarmsRaw() mutableCopy];
    NSUInteger found = NSNotFound;
    if (alarm.alarmId.length > 0) {
        for (NSUInteger i = 0; i < raw.count; i++) {
            if ([raw[i][@"alarmId"] isEqualToString:alarm.alarmId]) { found = i; break; }
        }
    }
    if (alarm.alarmId.length == 0) alarm.alarmId = [self newAlarmId];
    if (found == NSNotFound) {
        [raw addObject:MPDictFromAlarm(alarm)];
    } else {
        raw[found] = MPDictFromAlarm(alarm);
    }
    MPSaveAlarmsRaw(raw);
    // пересобрать нотификации под новое время (только если будильник включён)
    MPRemoveNotifications(alarm);
    if (alarm.enabled || found == NSNotFound) {
        MPScheduleNotifications(alarm);
    }
    [self notifyNativeRefresh];
    MPLog(@"[Clock] будильник %@ сохранён (%ld:%02ld)", alarm.alarmId,
          (long)alarm.hour, (long)alarm.minute);
}

+ (void)removeAlarm:(MPClockAlarm *)alarm {
    NSMutableArray *raw = [MPAlarmsRaw() mutableCopy];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        if ([d[@"alarmId"] isKindOfClass:[NSString class]] &&
            [d[@"alarmId"] isEqualToString:alarm.alarmId]) continue;
        [out addObject:d];
    }
    MPRemoveNotifications(alarm);
    MPSaveAlarmsRaw(out);
    [self notifyNativeRefresh];
    MPLog(@"[Clock] будильник %@ удалён", alarm.alarmId);
}

// Нативный AlarmViewController пересобирает уведомления и планировщик по префам.
// Приложение живое (pivot лежит в его таб-баре) — дёргаем напрямую, но с @try.
+ (void)notifyNativeRefresh {
    @try {
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        NSArray *vcs = [root isKindOfClass:[UITabBarController class]]
                           ? ((UITabBarController *)root).viewControllers : nil;
        for (UIViewController *vc in vcs) {
            SEL sel = NSSelectorFromString(@"handleUserPreferencesChangedWithScheduledLocalNotificationsRefresh:");
            if ([vc respondsToSelector:sel]) {
                void (*send)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
                send(vc, sel);
                MPLog(@"[Clock] нативный refresh: %@", NSStringFromClass([vc class]));
                return;
            }
        }
    } @catch (NSException *e) {
        MPLog(@"[Clock] !! нативный refresh: %@ — %@", e.name, e.reason);
    }
}

@end
