// MPCalcHooks — установка WP-дизайна в приложении «Калькулятор»
// (com.apple.calculator). По дампу бинаря iOS 6.1 — ГРАБЛИ, подтверждённые
// двумя неработающими версиями хуков:
//   1) CalculatorController наследуется ПРЯМО ОТ NSObject (ни UIView, ни
//      UIViewController): жизненного цикла UIKit у него нет вообще, хуки
//      viewDidLoad/viewDidAppear и layoutSubviews/didMoveToWindow не срабатывали.
//   2) Калькулятор строит UI по-старинке: Application (свой делегат) в
//      applicationDidFinishLaunching: кладёт CalcDisplayView/CalcKeypadView
//      ПРЯМО В ОКНО (у контроллера есть свойство window, вьюхи — дети окна).
// Поэтому: ставимся на Application applicationDidFinishLaunching: (первый
// показ) и на собственные _layout*Subviews CalculatorController (нативные
// перелайауты — прячем новых нативных детей и держим нашу вьюху наверху).

#import <UIKit/UIKit.h>
#import "MPCalcTheme.h"
#import "MPCalcView.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

// Приватные классы калькулятора (дамп бинаря) — не линкуем, только декларации
@interface Application : NSObject
@end
@interface CalculatorController : NSObject
@end

// Общая установка (C-функция: вызывается из хуков двух классов).
// Оптимизация: после первой удачной установки ничего не делаем — нативные
// дети остаются спрятанными (ротация заблокирована, новых не появляется),
// а хуки _layout*Subviews дёргают нас на каждом кадре нативной раскладки.
static BOOL MPCalcInstalledOnce = NO;

static void MPCalcInstallToWindow(void) {
    if (MPCalcInstalledOnce) return;
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        UIWindow *w = [app keyWindow];
        if (w == nil) {
            NSArray *ws = [app windows];
            w = [ws count] ? [ws objectAtIndex:0] : nil;
        }
        if (w == nil || w.bounds.size.width < 100.0f) return;
        // прячем нативный UI (дисплей, клавиатуру) — дети окна
        for (UIView *v in [w.subviews copy]) {
            if (v.tag != MPCalcViewTag) v.hidden = YES;
        }
        w.backgroundColor = [UIColor blackColor];
        MPCalcView *c = [MPCalcView installedCalcInView:w];
        [c applyOrientation];   // ориентация + пересчёт сетки по актуальным границам
        MPCalcInstalledOnce = YES;
        // статус-бар: приложение выставляет свой стиль ПОСЛЕ нашего %ctor —
        // перенабираем чёрный непрозрачный при каждом появлении (как Часы)
        [app setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];
    } @catch (NSException *e) {
        MPLog(@"[Calc] !! установка: %@ — %@", e.name, e.reason);
    }
}

static void MPCalcInstallSoon(void) {
    if (MPCalcInstalledOnce) return;   // установлены — хуки больше не работают
    dispatch_async(dispatch_get_main_queue(), ^{
        MPCalcInstallToWindow();
    });
}

%group MPCalc

%hook Application

// Первый показ: UI построен внутри %orig — наша вьюха ставится следом
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    MPLog(@"[Calc] applicationDidFinishLaunching — установка WP-вёрстки");
    MPCalcInstallSoon();
}

// Возврат из фона — наша вьюха возвращается наверх
- (void)applicationDidEnterBackground:(id)application {
    %orig;
    MPCalcInstallSoon();
}

%end

%hook CalculatorController

// Нативные перелайауты (свои методы класса, дамп): после каждого прячем
// нативных детей заново — ротация/статус-бар могли подложить новые вьюхи
- (void)_layoutPortraitSubviews {
    %orig;
    MPCalcInstallSoon();
}

- (void)_layoutLandscapeSubviews {
    %orig;
    MPCalcInstallSoon();
}

// Нативную ротацию блокируем целиком (и событие устройства, и прямой вызов):
// она трансформировала бы окно со старым UI, а поворачиваемся мы сами —
// MPCalcView слушает UIDeviceOrientationDidChange (см. MPCalcView)
- (void)_handleDeviceOrientationChange {
}

- (void)_rotateToOrientation:(NSUInteger)to {
}

%end

%end // MPCalc

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Вход

// Вызывается из Tweak.xm (%ctor). Хуки живут только в процессе «Калькулятора».
void MPCalcInitIfNeeded(void) {
    @try {
        CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle());
        if (bid == nil || CFStringCompare(bid, CFSTR("com.apple.calculator"), 0) != kCFCompareEqualTo) {
            return;                                        // чужой процесс
        }
        if (![MPCalcTheme restyleEnabled]) {
            MPLog(@"[Calc] kill-switch: дизайн калькулятора выключен");
            return;
        }
        // оба приватных класса должны существовать — иначе дизайн не ставить
        if (objc_getClass("Application") == nil || objc_getClass("CalculatorController") == nil) {
            MPLog(@"[Calc] Application/CalculatorController не найдены — хуки пропущены");
            return;
        }
        %init(MPCalc);
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque
                                                    animated:NO];
        MPLog(@"[Calc] хуки калькулятора установлены");
    } @catch (NSException *e) {
        MPLog(@"[Calc] !! init: %@ — %@", e.name, e.reason);
    }
}
