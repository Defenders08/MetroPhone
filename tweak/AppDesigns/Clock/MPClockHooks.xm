// MPClockHooks — установка pivot-дизайна в приложении «Часы»
// (com.apple.mobiletimer). Корень — ClockPhoneTabBarController (UITabBarController,
// подтверждено дампом бинаря iOS 6.1): мы прячем нативный таб-бар и кладём
// MPClockPivotView поверх. Нативные контроллеры вкладок живут и получают данные
// из тех же префов — их логика (включая уведомления будильников) не трогается.

#import <UIKit/UIKit.h>
#import "MPClockTheme.h"
#import "MPClockPivotView.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

// Корень приложения (по дампу бинаря iOS 6.1); приватный класс — не линкуем,
// только объявление для компилятора
@interface ClockPhoneTabBarController : UITabBarController
- (void)mp_installPivotSoon;
@end

%group MPClock

%hook ClockPhoneTabBarController

- (void)viewDidLoad {
    %orig;
    [self mp_installPivotSoon];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // повторный показ (возврат из фона, смена вкладки по URL-схеме) — pivot
    // возвращаем наверх и перечитываем данные
    [self mp_installPivotSoon];
}

// Отложенная установка: viewDidLoad ещё не знает финальные границы вьюхи
%new
- (void)mp_installPivotSoon {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UITabBarController *tab = (UITabBarController *)self;
            UIView *root = tab.view;
            if (root == nil || root.bounds.size.width < 100.0f) return;
            tab.tabBar.hidden = YES;
            MPClockPivotView *p = [MPClockPivotView installedPivotInView:root];
            [p reloadData];
            // статус-бар: приложение успевает выставить свой стиль ПОСЛЕ нашего
            // %ctor — перенабираем чёрный непрозрачный при каждом появлении
            [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                        animated:NO];
        } @catch (NSException *e) {
            MPLog(@"[Clock] !! установка pivot: %@ — %@", e.name, e.reason);
        }
    });
}

%end

%end // MPClock

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Вход

// Вызывается из Tweak.xm (%ctor). Хуки живут только в процессе «Часов».
void MPClockInitIfNeeded(void) {
    @try {
        CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle());
        if (bid == nil || CFStringCompare(bid, CFSTR("com.apple.mobiletimer"), 0) != kCFCompareEqualTo) {
            return;                                        // чужой процесс
        }
        if (![MPClockTheme restyleEnabled]) {
            MPLog(@"[Clock] kill-switch: дизайн часов выключен");
            return;
        }
        // класс корня может отсутствовать в будущих iOS — ставим только если есть
        if (objc_getClass("ClockPhoneTabBarController") == nil) {
            MPLog(@"[Clock] ClockPhoneTabBarController не найден — хуки пропущены");
            return;
        }
        %init(MPClock);
        // статус-бар — чёрным непрозрачным: iOS красит бар в синий при активной
        // раздаче («Режим модема»); стиль приложения перекрывает это в Часах
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                    animated:NO];
        MPLog(@"[Clock] хуки часов установлены");
    } @catch (NSException *e) {
        MPLog(@"[Clock] !! init: %@ — %@", e.name, e.reason);
    }
}
