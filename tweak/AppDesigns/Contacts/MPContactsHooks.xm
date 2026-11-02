// MPContactsHooks — установка pivot-дизайна в приложении «Контакты»
// (com.apple.MobileAddressBook, бинарь Contacts~iphone — заглушка 20 КБ, вся
// реализация в AddressBookUI). Корень — ABPeoplePickerNavigationController
// (подтверждено дампом бинаря: ivar _peoplePickerController у апп-делегата
// ABAppController). Мы кладём MPContactsPivotView в ОКНО приложения
// (fullscreen, поверх всего нативного UI). Нативные контроллеры живут под
// пивотом — их логика не трогается, данные читаем сами через AddressBook.
//
// Редактирование — нативное: ABPersonViewController (существующий контакт) и
// ABNewPersonViewController (новый) показываются поверх, пивот на это время
// прячется и возвращается на исчезновении редактора.

#import <UIKit/UIKit.h>
#import <AddressBook/AddressBook.h>
#import <objc/runtime.h>
#import "MPContactsTheme.h"
#import "MPContactsPivotView.h"
#import "MPContactsData.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

// C-обёртки отладки (реализованы в MPContactsPivotView.m)
extern "C" void MPContactsDebugScroll(float fraction);
extern "C" void MPContactsDebugGoTo(NSInteger page, CGFloat dur);
extern "C" void MPContactsDebugBurst(void);
extern "C" void MPContactsDebugFinger(void);
extern "C" void MPContactsDebugJump(NSInteger page);
extern "C" void MPContactsDebugShot(void);
void MPContactsDebugWatchStart(void);

// Корень приложения (по дампу бинаря); класс AddressBookUI — не линкуем,
// объявляем интерфейс (наследник UINavigationController, viewDidLoad живёт).
@interface ABPeoplePickerNavigationController : UIViewController
- (void)mp_installPivotSoon;
@end

// Живая ссылка на корневой пикер: window.rootViewController в этом
// приложении может быть не выставлен — пуш редактора ведём в найденный
// хуком навконтроллер
static __weak ABPeoplePickerNavigationController *MPConRootNav = nil;

// Редакторы AddressBookUI — не линкуем, объявляем
@interface ABPersonViewController : UIViewController
@property (nonatomic, assign) ABRecordRef displayedPerson;
@property (nonatomic, assign, getter=isAllowsEditing) BOOL allowsEditing;
@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Хук корня

%group MPContacts

%hook ABPeoplePickerNavigationController

- (void)viewDidLoad {
    %orig;
    MPLog(@"[Contacts] viewDidLoad %@", NSStringFromClass([self class]));
    [self mp_installPivotSoon];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // повторный показ (возврат из фона) — pivot возвращаем наверх
    [self mp_installPivotSoon];
}

// Metro-экраны портретные (лаунчер, локскрин) — контакты не исключение
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
            MPConRootNav = self;
            UIView *root = self.view;
            if (root == nil || root.bounds.size.width < 100.0f) return;
            UIWindow *w = root.window;
            if (w == nil) return;   // окно ещё не построено — придём из viewDidAppear
            MPContactsPivotView *p = [MPContactsPivotView installedPivotInView:w];
            [p reloadData];
            // статус-бар: приложение выставляет свой стиль ПОСЛЕ нашего %ctor —
            // перенабираем чёрный непрозрачный при каждом появлении (как Часы)
            [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                        animated:NO];
        } @catch (NSException *e) {
            MPLog(@"[Contacts] !! установка pivot: %@ — %@", e.name, e.reason);
        }
    });
}

%end

%end // MPContacts

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Хуки нативных редакторов

// Редакторы показываются только из нашего UI — появление означает «прячем
// пивот», исчезновение — «возвращаем» (успевает лечь ПОД уезжающий редактор).
%group MPContactsEditors

%hook ABPersonViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    MPLog(@"[Contacts] нативный редактор появился — пивот прячем");
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    MPContactsPivotView *p = [MPContactsPivotView installedPivotInView:w];
    [p hideForNativeEditor];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    MPLog(@"[Contacts] нативный редактор исчезает — пивот возвращаем");
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    MPContactsPivotView *p = [MPContactsPivotView installedPivotInView:w];
    // установку в окно вызов мог создать пивот ещё скрытым — здесь мы его
    // только возвращаем; если его ещё нет (first run), installed создаст
    [p showAfterNativeEditor];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)to {
    return UIInterfaceOrientationIsPortrait(to);
}

%end

%hook ABNewPersonViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // нативный «новый контакт» больше не открываем (свой WP-редактор),
    // но если вдруг открылся чужим путём — ведём себя как с редактором
    MPLog(@"[Contacts] нативный новый контакт появился — пивот прячем");
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    MPContactsPivotView *p = [MPContactsPivotView installedPivotInView:w];
    [p hideForNativeEditor];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    MPLog(@"[Contacts] нативный новый контакт исчезает — пивот возвращаем");
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    MPContactsPivotView *p = [MPContactsPivotView installedPivotInView:w];
    [p showAfterNativeEditor];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)to {
    return UIInterfaceOrientationIsPortrait(to);
}

%end

%end // MPContactsEditors

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Нативный редактор (C-интерфейс для пивота)

BOOL MPContactsEditorCovering(void) {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return NO;
    for (UIView *v in w.subviews) {
        if ([v isKindOfClass:[MPContactsPivotView class]]) {
            return [(MPContactsPivotView *)v isCoveringEditor];
        }
    }
    return NO;
}

// Правка существующего: пушим ABPersonViewController в родной навконтроллер
// (модально ему нечего показывать — нет навбара с «назад»)
void MPContactsPresentNativeEditor(NSInteger recordID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            MPContactsData *d = [MPContactsData sharedData];
            ABRecordRef rec = [d personRefForRecordID:recordID];
            if (rec == NULL) {
                MPLog(@"[Contacts] !! запись %ld не найдена в хранилище", (long)recordID);
                return;
            }
            // displayedPerson — assign: ссылку удерживаем ассоциацией с VC,
            // ARC отпустит её вместе с контроллером
            ABPersonViewController *vc = [[ABPersonViewController alloc] init];
            vc.displayedPerson = rec;
            vc.allowsEditing = YES;
            objc_setAssociatedObject(vc, "mpRecord", CFBridgingRelease(rec),
                                     OBJC_ASSOCIATION_RETAIN);

            // пивот прячем ДО показа — всплытие редактора из-под него незаметно
            UIWindow *w = [UIApplication sharedApplication].keyWindow;
            MPContactsPivotView *p = [MPContactsPivotView installedPivotInView:w];
            [p hideForNativeEditor];

            // пушим в родной навконтроллер (window.rootViewController здесь
            // может быть не выставлен — используем найденный хуком пикер)
            UIViewController *nav = MPConRootNav;
            if (nav == nil) nav = w.rootViewController;
            if ([nav respondsToSelector:@selector(pushViewController:animated:)]) {
                [nav performSelector:@selector(pushViewController:animated:)
                          withObject:vc withObject:@YES];
            } else if ([nav respondsToSelector:@selector(presentModalViewController:animated:)]) {
                UINavigationController *wrap = [[UINavigationController alloc]
                                                initWithRootViewController:vc];
                [nav performSelector:@selector(presentModalViewController:animated:)
                          withObject:wrap withObject:@YES];
            }
            MPLog(@"[Contacts] нативный редактор показан (запись %ld)", (long)recordID);
        } @catch (NSException *e) {
            MPLog(@"[Contacts] !! редактор: %@ — %@", e.name, e.reason);
        }
    });
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Вход

// Вызывается из Tweak.xm (%ctor). Хуки живут только в процессе «Контактов».
void MPContactsInitIfNeeded(void) {
    @try {
        CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle());
        if (bid == nil || CFStringCompare(bid, CFSTR("com.apple.MobileAddressBook"), 0) != kCFCompareEqualTo) {
            return;                                        // чужой процесс
        }
        if (![MPContactsTheme restyleEnabled]) {
            MPLog(@"[Contacts] kill-switch: дизайн контактов выключен");
            return;
        }
        // корни могут отсутствовать в других iOS — каждый %init независимо:
        // гейт по одному классу молча отключал дизайн (урок «Календаря»)
        Class rootClass = objc_getClass("ABPeoplePickerNavigationController");
        Class editorClass = objc_getClass("ABPersonViewController");
        Class newClass = objc_getClass("ABNewPersonViewController");
        if (rootClass == nil) {
            MPLog(@"[Contacts] корневой класс не найден — хуки пропущены");
            return;
        }
        %init(MPContacts);
        if (editorClass != nil || newClass != nil) %init(MPContactsEditors);
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                    animated:NO];
        MPContactsDebugWatchStart();
        MPLog(@"[Contacts] хуки контактов установлены");
    } @catch (NSException *e) {
        MPLog(@"[Contacts] !! init: %@ — %@", e.name, e.reason);
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Отладочный канал (Darwin + префы)

// Канал как у «Календаря»: Darwin «ru.ash.metrophone.condebug», текст команды
// в префах ru.ash.metrophone / ключ condebugCmd. Снимки и дамп — в
// /var/mobile/Library/Preferences/ (запись туда разрешена — там наш журнал).

static void MPContactsDebugDarwinCB(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef info) {
    CFPreferencesAppSynchronize(CFSTR("ru.ash.metrophone"));
    CFStringRef v = (CFStringRef)CFPreferencesCopyAppValue(CFSTR("condebugCmd"),
                                                           CFSTR("ru.ash.metrophone"));
    if (v == NULL) return;
    NSString *cmd = [(__bridge NSString *)v copy];
    CFRelease(v);

    void (^run)(void) = ^{
        if ([cmd hasPrefix:@"conscroll"]) {
            MPContactsDebugScroll([[cmd substringFromIndex:9] floatValue]);
        } else if ([cmd hasPrefix:@"conslow"]) {
            NSArray *parts = [cmd componentsSeparatedByString:@" "];
            NSInteger page = [parts.count > 1 ? parts[1] : @1 integerValue];
            CGFloat dur = parts.count > 2 ? [parts[2] floatValue] : 2.5;
            MPContactsDebugGoTo(page, dur);
        } else if ([cmd hasPrefix:@"conjump"]) {
            NSArray *parts = [cmd componentsSeparatedByString:@" "];
            MPContactsDebugJump(parts.count > 1 ? [parts[1] integerValue] : 1);
        } else if ([cmd caseInsensitiveCompare:@"conburst"] == NSOrderedSame) {
            MPContactsDebugBurst();
        } else if ([cmd caseInsensitiveCompare:@"confinger"] == NSOrderedSame) {
            MPContactsDebugFinger();
        } else if ([cmd caseInsensitiveCompare:@"conshot"] == NSOrderedSame) {
            MPContactsDebugShot();
        } else if ([cmd caseInsensitiveCompare:@"condump"] == NSOrderedSame) {
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
            [out writeToFile:@"/var/mobile/Library/Preferences/condump.txt" atomically:YES];
            MPLog(@"[Contacts] дамп дерева → condump.txt");
        } else {
            MPLog(@"[Contacts] отладка: неизвестная команда %@", cmd);
        }
    };
    if ([NSThread isMainThread]) run();
    else dispatch_async(dispatch_get_main_queue(), run);
}

void MPContactsDebugWatchStart(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    &MPContactsDebugDarwinCB, CFSTR("ru.ash.metrophone.condebug"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    // Возврат в уже запущенные контакты (тап по плитке/свитчер): viewDidAppear
    // НЕ вызывается, а нативный UI поднимается поверх пивота — на каждую
    // активацию возвращаем пивот наверх (если не открыт нативный редактор)
    [[NSNotificationCenter defaultCenter] addObserverForName:
     UIApplicationDidBecomeActiveNotification object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            if (MPContactsEditorCovering()) return;   // редактор поверх — не мешаем
            UIWindow *w = [UIApplication sharedApplication].keyWindow;
            if (w == nil) return;
            MPContactsPivotView *p = [MPContactsPivotView installedPivotInView:w];
            [p reloadData];
            [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                        animated:NO];
            MPLog(@"[Contacts] активация — пивот поднят наверх");
        }];
    MPLog(@"[Contacts] отладочный канал (Darwin) готов");
}
