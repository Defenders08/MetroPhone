// MetroPhone — контроллер Metro-локскрина (реализация).
//
// Схема работы: своя UIWindow в SpringBoard на iOS 6 НЕ РЕНДЕРИТСЯ (окна
// рисуются мимо UIApplication, [UIApplication windows] пуст), поэтому вьюха
// сажается в ГЛАВНОЕ окно SpringBoard (MPSharedHostWindow) на весь экран и
// держится поверх всего хуками SBAppWindow/SBAwayView (MPLockScreenRaise).
// Нативный локскрин остаётся под непрозрачной вьюхой и не виден. Ввод кода
// (SBPasscodeViewController) временно прячет вьюху. Свайп вверх вызывает
// нативную разблокировку SBAwayController unlockWithSound:.

#import "MPLockScreen.h"
#import "MPLockScreenView.h"
#import "../MetroLauncher/MPMetroStyle.h"
#import "../MetroPhoneCommon.h"

#import <objc/runtime.h>
#import <objc/message.h>

// Классы SpringBoard (сверить селекторы с бинарником 6.1 при проблемах в журнале)
@interface SBAwayController : NSObject
+ (id)sharedAwayController;
- (BOOL)isLocked;
- (void)unlockWithSound:(BOOL)sound;
@end

// Настройки: локальная копия чтения CFPreferences (MPFlag из Tweak.xm статический)
static BOOL MLSFlag(NSString *key, BOOL def) {
	CFTypeRef v = CFPreferencesCopyAppValue((CFStringRef)key, CFSTR(MP_PREFS_DOMAIN));
	if (v == NULL) return def;
	BOOL result = def;
	if (CFGetTypeID(v) == CFBooleanGetTypeID()) result = CFBooleanGetValue((CFBooleanRef)v);
	else if (CFGetTypeID(v) == CFNumberGetTypeID()) result = [(__bridge NSNumber *)v boolValue];
	CFRelease(v);
	return result;
}

BOOL MPLockScreenIsOn(void) {
	Class iconClass = objc_getClass("SBIconView");
	if (iconClass == nil) return NO; // не SpringBoard
	BOOL master = MLSFlag(MPKeyEnabled, YES);
	BOOL lockscreen = MLSFlag(MPKeyLockscreen, YES);
	return master && lockscreen;
}

// ---- Состояние (доступ только с главного потока) ----

static UIImage *MLSWallpaper = nil;      // последние нативные обои устройства
static MPLockScreenView *MLSView = nil;  // наша вьюха (живёт в главном окне)
static BOOL MLSPasscodeVisible = NO;     // на экране нативный ввод кода
static BOOL MLSPendingUnlock = NO;       // свайп уже запустил разблокировку

static void MLSUnlock(void); // определение ниже, нужен блоку onUnlock

static BOOL MLSIsLocked(void) {
	id away = [objc_getClass("SBAwayController") sharedAwayController];
	BOOL locked = NO;
	if (away != nil && [away respondsToSelector:@selector(isLocked)]) locked = [away isLocked];
	return locked;
}

// Посадка в ОКНО нативного локскрина. Нативный локскрин — в отдельном окне
// выше главного SBAppWindow (проверено: в главном окне наша вьюха не видна,
// а в SBAlertWindow — видна). SBAwayView didMoveToWindow даёт нам это окно.
// Вызывается из хука, только на главном потоке.
void MPLockScreenAttach(UIWindow *lockWindow) {
	@try {
		if (lockWindow == nil) return;
		if (MLSView != nil && MLSView.superview == lockWindow) {
			MPLockScreenRaise();
			return;
		}

		if (MLSView == nil) {
			MLSView = [[MPLockScreenView alloc] initWithFrame:[UIScreen mainScreen].bounds];
			MLSView.hidden = YES; // показом управляет только sync
			MLSView.onUnlockBlock = ^{
				MLSUnlock();
			};
			MPLog(@"локскрин: вьюха создана");
		}
		[lockWindow addSubview:MLSView];
		MLSView.frame = lockWindow.bounds;
		MPLockScreenRaise();
		MPLog(@"локскрин: в окне %@ (%@)", NSStringFromClass([lockWindow class]),
		      NSStringFromCGSize(lockWindow.bounds.size));
		MPLockScreenSync(); // устройство уже может быть залочено
	} @catch (NSException *e) {
		MPLog(@"!! локскрин: attach — %@ (%@)", e.name, e.reason);
	}
}

static void MLSUnlock(void) {
	@try {
		MPLog(@"локскрин: свайп — разблокировка (кода нет или сразу за ним клавиатура)");
		MLSView.hidden = YES;
		[MLSView stopClockUpdates];
		MLSPendingUnlock = YES;

		id away = [objc_getClass("SBAwayController") sharedAwayController];
		if (away != nil && [away respondsToSelector:@selector(unlockWithSound:)]) {
			((void (*)(id, SEL, BOOL))objc_msgSend)(away, @selector(unlockWithSound:), NO);
			MPLog(@"локскрин: unlockWithSound отправлен");
		} else {
			MPLog(@"!! локскрин: SBAwayController.unlockWithSound: недоступен — селектор сверить с бинарником");
		}

		// Если разблокировка не прошла (например, селектор не сработал) — через
		// секунду вернём вьюху вместо мёртвого экрана
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			MLSPendingUnlock = NO;
			MPLockScreenSync();
		});
	} @catch (NSException *e) {
		MPLog(@"!! локскрин: unlock — %@ (%@)", e.name, e.reason);
		MLSPendingUnlock = NO;
	}
}

// Вьюха обязана быть поверх всего окна и на весь экран: iOS при пробуждении
// добавляет/поднимает контент нативного локскрина после нас — хуки
// SBAppWindow/SBAwayView дёргают эту функцию при каждой перестановке.
// Guard-и делают её безопасной для частых вызовов: когда вьюха скрыта или уже
// сверху с правильным размером, здесь ничего не происходит.
void MPLockScreenRaise(void) {
	if (MLSView == nil || MLSView.superview == nil || MLSView.hidden) return;
	UIView *parent = MLSView.superview;
	if ([parent.subviews lastObject] != MLSView) {
		[parent bringSubviewToFront:MLSView];
	}
	if (!CGRectEqualToRect(MLSView.frame, parent.bounds)) {
		MLSView.frame = parent.bounds;
	}
}

void MPLockScreenSync(void) {
	if (objc_getClass("SBIconView") == nil) return; // только SpringBoard
	dispatch_async(dispatch_get_main_queue(), ^{
		@try {
			if (MLSView == nil || MLSView.superview == nil) return; // ждём attach из хука

			BOOL show = MPLockScreenIsOn()
			             && MLSIsLocked()
			             && !MLSPasscodeVisible
			             && !MLSPendingUnlock;

			if (show) {
				[MLSView setWallpaperImage:MLSWallpaper];
				[MLSView resetSlide];
				[MLSView refreshContent];
				MLSView.hidden = NO;
				MPLockScreenRaise();
				[MLSView startClockUpdates];
				MPLog(@"локскрин: показан %@ в %@", NSStringFromCGSize(MLSView.bounds.size),
				      NSStringFromClass([MLSView.superview class]));
				// Страховка: iOS может поднять свой контент позже — через полсекунды
				// проверяем, что мы всё ещё сверху
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
				               dispatch_get_main_queue(), ^{
					MPLockScreenRaise();
				});
			} else if (!MLSView.hidden) {
				MLSView.hidden = YES;
				[MLSView stopClockUpdates];
				MPLog(@"локскрин: скрыт (locked=%d код=%d)", MLSIsLocked(), MLSPasscodeVisible);
			}
		} @catch (NSException *e) {
			MPLog(@"!! локскрин: sync — %@ (%@)", e.name, e.reason);
		}
	});
}

void MPLockScreenNoteWallpaper(UIImage *image) {
	if (image == nil) return;
	MLSWallpaper = image;
	// Картинку в вьюху подтягивает MPLockScreenSync (при каждом показе)
}

void MPLockScreenPasscodeUI(BOOL visible) {
	if (MLSPasscodeVisible == visible) return;
	MLSPasscodeVisible = visible;
	MPLog(@"локскрин: нативный ввод кода %@", visible ? @"появился — прячемся" : @"закрылся");
	MPLockScreenSync();
}

// Окно локскрина для отладочного снимка (см. MPDebugShotTake в Tweak.xm)
UIWindow *MPLockScreenWindow(void) {
	if (MLSView == nil || MLSView.hidden || MLSView.superview == nil) return nil;
	return MLSView.superview.window;
}
