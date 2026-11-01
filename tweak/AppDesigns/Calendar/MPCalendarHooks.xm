// MPCalendarHooks — установка pivot-дизайна в приложении «Календарь»
// (com.apple.mobilecal). Корень — CalendarMainViewController (контейнер
// видов месяц/неделя/день/список, подтверждено дампом бинаря iOS 6.1):
// мы прячем нативный навбар и кладём MPCalendarPivotView в ОКНО приложения
// (fullscreen, поверх всего нативного UI). Нативные контроллеры живут под
// пивотом — их логика не трогается, данные читаем сами через EventKit.

#import <UIKit/UIKit.h>
#import <EventKit/EventKit.h>
#import "MPCalendarTheme.h"
#import "MPCalendarPivotView.h"
#import "MPCalendarData.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

// C-обёртки отладки (реализованы в MPCalendarPivotView.m)
extern "C" void MPCalendarDebugScroll(float fraction);
extern "C" void MPCalendarDebugGoTo(NSInteger page, CGFloat dur);
extern "C" void MPCalendarDebugBurst(void);
extern "C" void MPCalendarDebugFinger(void);
extern "C" void MPCalendarDebugDate(NSString *dateStr);
extern "C" void MPCalendarDebugShot(void);
void MPCalendarDebugWatchStart(void);

// Корни приложения (по дампу бинаря iOS 6.1); приватные классы — не линкуем.
// На iPhone корень — CalendarViewController (currentView/_showViewController:),
// CalendarMainViewController — iPad-контейнер; хукаем оба, каждый логирует
// установку — по журналу видно, кто реально живёт в процессе.
@interface CalendarViewController : UIViewController
- (void)mp_installPivotSoon;
@end
@interface CalendarMainViewController : UIViewController
- (void)mp_installPivotSoon;
@end

// Две группы: корень iPhone (CalendarViewController) и iPad-контейнер
// (CalendarMainViewController) инициализируются независимо — гейт по ОДНОМУ
// классу молча отключал дизайн на системах, где есть только второй корень.
%group MPCalPhone

%hook CalendarViewController

- (void)viewDidLoad {
    %orig;
    MPLog(@"[Calendar] viewDidLoad %@", NSStringFromClass([self class]));
    [self mp_installPivotSoon];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // повторный показ (возврат из фона) — pivot возвращаем наверх
    [self mp_installPivotSoon];
}

// Metro-экраны портретные (лаунчер, локскрин) — календарь не исключение
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)to {
    return UIInterfaceOrientationIsPortrait(to);
}

// Отложенная установка: пивот ставим в ОКНО приложения — поверх любого
// нативного UI. В viewDidLoad окно ещё может не существовать (root.window
// == nil) — тогда придём из viewDidAppear.
%new
- (void)mp_installPivotSoon {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIView *root = self.view;
            if (root == nil || root.bounds.size.width < 100.0f) return;
            UIWindow *w = root.window;
            if (w == nil) return;   // окно ещё не построено — придём из viewDidAppear
            MPCalendarPivotView *p = [MPCalendarPivotView installedPivotInView:w];
            [p reloadData];
            // статус-бар: приложение выставляет свой стиль ПОСЛЕ нашего %ctor —
            // перенабираем чёрный непрозрачный при каждом появлении (как Часы)
            [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                        animated:NO];
        } @catch (NSException *e) {
            MPLog(@"[Calendar] !! установка pivot: %@ — %@", e.name, e.reason);
        }
    });
}

%end

%end // MPCalPhone

%group MPCalPad

%hook CalendarMainViewController

- (void)viewDidLoad {
    %orig;
    MPLog(@"[Calendar] viewDidLoad %@", NSStringFromClass([self class]));
    [self mp_installPivotSoon];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [self mp_installPivotSoon];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)to {
    return UIInterfaceOrientationIsPortrait(to);
}

%new
- (void)mp_installPivotSoon {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIView *root = self.view;
            if (root == nil || root.bounds.size.width < 100.0f) return;
            UIWindow *w = root.window;
            if (w == nil) return;
            MPCalendarPivotView *p = [MPCalendarPivotView installedPivotInView:w];
            [p reloadData];
            [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                        animated:NO];
        } @catch (NSException *e) {
            MPLog(@"[Calendar] !! установка pivot: %@ — %@", e.name, e.reason);
        }
    });
}

%end

%end // MPCalPad

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Вход

// Вызывается из Tweak.xm (%ctor). Хуки живут только в процессе «Календаря».
void MPCalendarInitIfNeeded(void) {
    @try {
        CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle());
        if (bid == nil || CFStringCompare(bid, CFSTR("com.apple.mobilecal"), 0) != kCFCompareEqualTo) {
            return;                                        // чужой процесс
        }
        if (![MPCalendarTheme restyleEnabled]) {
            MPLog(@"[Calendar] kill-switch: дизайн календаря выключен");
            return;
        }
        // корни могут отсутствовать в других iOS — каждый %init независимо:
        // гейт по одному (iPad) классу пропускал и iPhone-корень
        Class phoneRoot = objc_getClass("CalendarViewController");
        Class padRoot = objc_getClass("CalendarMainViewController");
        if (phoneRoot == nil && padRoot == nil) {
            MPLog(@"[Calendar] корневые классы не найдены — хуки пропущены");
            return;
        }
        if (phoneRoot != nil) %init(MPCalPhone);
        if (padRoot != nil) %init(MPCalPad);
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                    animated:NO];
        MPCalendarDebugWatchStart();
        MPLog(@"[Calendar] хуки календаря установлены");
    } @catch (NSException *e) {
        MPLog(@"[Calendar] !! init: %@ — %@", e.name, e.reason);
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Отладочный канал (Darwin + префы)

// У MobileCal жёсткий sandbox: файл shot.request открывать нельзя (убивает
// процесс). Команды приходят через Darwin «ru.ash.metrophone.caldebug», текст —
// в префах ru.ash.metrophone / ключ caldebugCmd. Снимки пишутся в
// /var/mobile/Library/Preferences/ (запись туда разрешена — там наш журнал).

static void MPCalendarDebugDarwinCB(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef info) {
    CFPreferencesAppSynchronize(CFSTR("ru.ash.metrophone"));
    CFStringRef v = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("caldebugCmd"),
                                                           CFSTR("ru.ash.metrophone"));
    if (v == NULL) return;
    NSString *cmd = [(__bridge NSString *)v copy];
    CFRelease(v);

    void (^run)(void) = ^{
        if ([cmd hasPrefix:@"calscroll"]) {
            MPCalendarDebugScroll([[cmd substringFromIndex:9] floatValue]);
        } else if ([cmd hasPrefix:@"calslow"]) {
            NSArray *parts = [cmd componentsSeparatedByString:@" "];
            NSInteger page = [parts.count > 1 ? parts[1] : @0 integerValue];
            CGFloat dur = parts.count > 2 ? [parts[2] floatValue] : 2.5;
            MPCalendarDebugGoTo(page, dur);
        } else if ([cmd hasPrefix:@"caldate"]) {
            NSArray *parts = [cmd componentsSeparatedByString:@" "];
            MPCalendarDebugDate(parts.count > 1 ? parts[1] : @"");
        } else if ([cmd caseInsensitiveCompare:@"calburst"] == NSOrderedSame) {
            MPCalendarDebugBurst();
        } else if ([cmd caseInsensitiveCompare:@"calfinger"] == NSOrderedSame) {
            MPCalendarDebugFinger();
        } else if ([cmd caseInsensitiveCompare:@"calshot"] == NSOrderedSame) {
            MPCalendarDebugShot();
        } else if ([cmd caseInsensitiveCompare:@"caltest"] == NSOrderedSame) {
            // тестовое событие на завтра 14:00–15:00 (проверка блоков дня/точек)
            MPCalendarData *d = [MPCalendarData sharedData];
            EKEvent *ev = [EKEvent eventWithEventStore:d.store];
            ev.title = @"Тест WP-календаря";
            ev.startDate = [d.cal dateFromComponents:({
                NSDateComponents *c = [d.cal components:NSYearCalendarUnit | NSMonthCalendarUnit
                                                     | NSDayCalendarUnit fromDate:
                    [d dayStartByAddingDays:1 toDayStart:[d todayStart]]];
                c.hour = 14; c.minute = 0; c;
            })];
            ev.endDate = [ev.startDate dateByAddingTimeInterval:3600.0];
            ev.calendar = [d writableCalendars].firstObject ?: [d.store defaultCalendarForNewEvents];
            [d saveEvent:ev];
            MPLog(@"[Calendar] тестовое событие создано: %@", ev.startDate);
        } else if ([cmd caseInsensitiveCompare:@"caltest0"] == NSOrderedSame) {
            MPCalendarData *d = [MPCalendarData sharedData];
            NSDate *tom = [d dayStartByAddingDays:1 toDayStart:[d todayStart]];
            for (MPCalendarEvent *ev in [d eventsForDayStart:tom]) {
                if ([ev.title hasPrefix:@"Тест WP"]) [d deleteEvent:ev.sourceEvent];
            }
            MPLog(@"[Calendar] тестовые события удалены");
        } else if ([cmd caseInsensitiveCompare:@"caldump"] == NSOrderedSame) {
            // дамп дерева окна с фреймами (renderInContext слеп к contentOffset
            // пейджера — реальную вёрстку верифицировать дампом)
            NSMutableString *out = [NSMutableString string];
            NSMutableArray *stack = [NSMutableArray arrayWithObject:
                                     [UIApplication sharedApplication].keyWindow];
            NSMutableArray *depths = [NSMutableArray arrayWithObject:@0];
            while (stack.count > 0) {
                UIView *v = [stack lastObject];
                NSInteger dep = [depths.lastObject integerValue];
                [stack removeLastObject];
                [depths removeLastObject];
                NSString *lbl = @"";
                if ([v isKindOfClass:[UIScrollView class]]) {
                    CGPoint co = [(UIScrollView *)v contentOffset];
                    lbl = [NSString stringWithFormat:@" off(%.0f,%.0f)",
                           co.x, co.y];
                }
                [out appendFormat:@"%*s%@ (%.0f,%.0f %.0fx%.0f)%@ hidden=%d\n",
                 (int)dep, "", NSStringFromClass([v class]),
                 v.frame.origin.x, v.frame.origin.y,
                 v.frame.size.width, v.frame.size.height, lbl, v.isHidden];
                for (UIView *s in v.subviews) {
                    [stack addObject:s];
                    [depths addObject:@(dep + 1)];
                }
            }
            [out writeToFile:@"/var/mobile/Library/Preferences/caldump.txt" atomically:YES];
            MPLog(@"[Calendar] дамп дерева → caldump.txt");
        } else {
            MPLog(@"[Calendar] отладка: неизвестная команда %@", cmd);
        }
    };
    if ([NSThread isMainThread]) run();
    else dispatch_async(dispatch_get_main_queue(), run);
}

void MPCalendarDebugWatchStart(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    &MPCalendarDebugDarwinCB, CFSTR("ru.ash.metrophone.caldebug"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    // Возврат в уже запущенный календарь (тап по плитке/свитчер): viewDidAppear
    // НЕ вызывается, а нативный UI поднимается поверх пивота — юзер видел
    // нативный календарь. На каждую активацию возвращаем пивот наверх.
    [[NSNotificationCenter defaultCenter] addObserverForName:
     UIApplicationDidBecomeActiveNotification object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            UIWindow *w = [UIApplication sharedApplication].keyWindow;
            if (w == nil) return;
            MPCalendarPivotView *p = [MPCalendarPivotView installedPivotInView:w];
            [p reloadData];
            [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                        animated:NO];
            MPLog(@"[Calendar] активация — пивот поднят наверх");
        }];
    MPLog(@"[Calendar] отладочный канал (Darwin) готов");
}
