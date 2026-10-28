// MetroPhone — контроллер Metro-локскрина (реализация).
//
// Схема работы: своя UIWindow в SpringBoard на iOS 6 НЕ РЕНДЕРИТСЯ (окна
// рисуются мимо UIApplication, [UIApplication windows] пуст), поэтому вьюха
// сажается в ОКНО нативного локскрина (там, где живёт SBAwayView) на весь экран.
// Нативный локскрин (SBAwayView) лежит в том же окне; полагаться на порядок
// вьюх нельзя — iOS при пробуждении и разблокировке переставляет свой контент,
// и родной экран оказывался выше подложки, просвечивая под нашей вьюхой при
// свайпе. Поэтому пока наш экран показан, нативный SBAwayView прячем ЯВНО
// (подстраховка хуком setHidden: в Tweak.xm), при скрытии нашего — возвращаем:
// внутри SBAwayView живёт нативный ввод кода (SBPasscodeViewController). Свайп
// вверх вызывает нативную разблокировку (SBAwayController unlockWithSound: и
// запасные селекторы — какой сработал, видно в журнале).

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
- (void)unlock;                                        // запасные пути разблокировки
- (void)_unlockWithSound:(BOOL)sound animate:(BOOL)animate;
@end

// Запуск приложения с локскрина — тот же путь, что у плиток и свитчера:
// SBIconController → model → leafIconsByIdentifier → [icon launch]
@interface SBIconController : NSObject
+ (id)sharedInstance;
- (id)model;
@end

@interface SBIconModel : NSObject
- (NSDictionary *)leafIconsByIdentifier;
@end

@interface SBLeafIcon : NSObject
- (NSString *)applicationBundleID;
- (void)launch;
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
static MPLockScreenView *MLSView = nil;  // наша вьюха (живёт в окне локскрина)
static UIView *MLSShield = nil;          // подложка: закрывает нативный локскрин под нами
static BOOL MLSPasscodeVisible = NO;     // на экране нативный ввод кода
static BOOL MLSPendingUnlock = NO;       // свайп уже запустил разблокировку
static NSUInteger MLSHideToken = 0;      // отменяет отложенные скрытия
static BOOL MLSReordering = NO;          // защита от рекурсии при перестановке вьюх

static void MLSUnlock(void);     // определение ниже, нужен блоку onUnlock
static void MLSShieldPlace(void); // подложка ровно под нашей вьюхой
static void MLSNativeHidden(BOOL hide, NSString *reason); // нативный локскрин
static void MLSCameraTap(void);  // тап по иконке камеры внизу справа

static BOOL MLSIsLocked(void) {
	id away = [objc_getClass("SBAwayController") sharedAwayController];
	BOOL locked = NO;
	if (away != nil && [away respondsToSelector:@selector(isLocked)]) locked = [away isLocked];
	return locked;
}

// Один раз на сессию: какие селекторы разблокировки реально есть в этой системе.
// Без этого неудачный свайп выглядит как «ничего не произошло».
static void MLSLogUnlockSelectors(void) {
	static BOOL logged = NO;
	if (logged) return;
	logged = YES;
	id away = [objc_getClass("SBAwayController") sharedAwayController];
	MPLog(@"локскрин: SBAwayController = %@ (unlockWithSound:%d unlock:%d _unlockWithSound:animate:%d)",
	      away != nil ? NSStringFromClass([away class]) : @"nil",
	      away != nil && [away respondsToSelector:@selector(unlockWithSound:)],
	      away != nil && [away respondsToSelector:@selector(unlock)],
	      away != nil && [away respondsToSelector:@selector(_unlockWithSound:animate:)]);
}

#pragma mark - Показ и скрытие

// Подложка обязана стоять ровно под нашей вьюхой: iOS при пробуждении и смене
// состояния добавляет/поднимает контент нативного локскрина, и он не должен
// оказаться выше неё. Переставляем только при реальном расхождении — иначе
// insertSubview дёргает didAddSubview и уходим в рекурсию.
static void MLSShieldPlace(void) {
	if (MLSReordering) return;
	if (MLSShield == nil || MLSView == nil || MLSView.superview == nil) return;
	UIView *parent = MLSView.superview;
	NSArray *subviews = parent.subviews;
	NSUInteger shieldIndex = [subviews indexOfObject:MLSShield];
	NSUInteger viewIndex = [subviews indexOfObject:MLSView];
	BOOL placed = (shieldIndex != NSNotFound && viewIndex != NSNotFound && shieldIndex + 1 == viewIndex);
	if (!placed) {
		MLSReordering = YES;
		[parent insertSubview:MLSShield belowSubview:MLSView];
		MLSReordering = NO;
	}
	if (!CGRectEqualToRect(MLSShield.frame, parent.bounds)) MLSShield.frame = parent.bounds;
	MLSShield.hidden = MLSView.hidden;
}

// Родной локскрин — это НЕ одна вьюха: SBAwayView только верхняя зона с часами,
// слайдер/батарея/камера живут в других контейнерах того же окна. Поэтому прячем
// ВСЕХ соседей нашей вьюхи, кроме подложки; ссылки не храним. Скрытие уходит
// через Logos-хук setHidden: (SBAwayView) — конфликтов нет: хук гасит только
// показ (аргумент NO), когда наш экран уже накрывает.
static void MLSNativeHidden(BOOL hide, NSString *reason) {
	if (MLSView == nil || MLSView.superview == nil) return;
	int changed = 0;
	for (UIView *sub in [MLSView.superview subviews]) {
		if (sub == MLSView || sub == MLSShield) continue;
		if (sub.hidden != hide) {
			[sub setHidden:hide];
			changed++;
		}
	}
	if (changed > 0) {
		MPLog(@"локскрин: нативный контент (%d вьюх) %@ (%@)", changed,
		      hide ? @"скрыт" : @"показан", reason);
	}
}

// Хук setHidden: дёргает это при каждой попытке iOS показать нативный локскрин:
// пока наш экран накрывает окно (и ввод кода не показан — он живёт внутри
// SBAwayView), нативный обязан оставаться скрытым, иначе просвечивает под нами.
BOOL MPLockScreenCoversNative(void) {
	return MLSView != nil && !MLSView.hidden && !MLSPasscodeVisible;
}

static void MLSHideNow(NSString *reason) {
	MLSHideToken++;
	if (MLSView != nil && !MLSView.hidden) {
		MLSView.hidden = YES;
		MPLog(@"локскрин: скрыт (%@)", reason);
	}
	[MLSView stopClockUpdates];
	if (MLSShield != nil) MLSShield.hidden = YES;
	// Нативный возвращаем строго после скрытия нашего: хук setHidden: смотрит
	// на флаг и не станет тут же гасить его обратно
	MLSNativeHidden(NO, reason);
}

static void MLSShowNow(void) {
	[MLSView setWallpaperImage:MLSWallpaper];
	[MLSView resetSlide];
	// Экран зажигаем сразу, контент собираем после показа: refreshContent — это
	// скан бейджей по всем приложениям и запрос батареи, на A4 это ощутимая
	// задержка пробуждения. Лейблы дозаполняются в следующем же проходе layout.
	MLSView.hidden = NO;
	MPLockScreenRaise(); // подложка встанет ровно под вьюхой и покажется
	MLSNativeHidden(YES, @"показ"); // родной локскрин не должен просвечивать
	[MLSView refreshContent];
	[MLSView startClockUpdates];
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

		if (MLSShield == nil) {
			MLSShield = [[UIView alloc] initWithFrame:lockWindow.bounds];
			MLSShield.backgroundColor = [UIColor blackColor];
			MLSShield.userInteractionEnabled = NO;
			MLSShield.hidden = YES;
			MLSShield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			MPLog(@"локскрин: подложка создана");
		}

		if (MLSView == nil) {
			MLSView = [[MPLockScreenView alloc] initWithFrame:[UIScreen mainScreen].bounds];
			MLSView.hidden = YES; // показом управляет только sync
			MLSView.onUnlockBlock = ^{
				MLSUnlock();
			};
			MLSView.onCameraBlock = ^{
				MLSCameraTap();
			};
			MPLog(@"локскрин: вьюха создана");
			MLSLogUnlockSelectors();
		}

		// Подложка — первой, наша вьюха — поверх неё
		[lockWindow addSubview:MLSShield];
		[lockWindow addSubview:MLSView];
		MLSView.frame = lockWindow.bounds;
		MLSShield.frame = lockWindow.bounds;
		MLSShield.hidden = MLSView.hidden;
		MPLockScreenRaise();
		MPLog(@"локскрин: в окне %@ (%@), подложка под вьюхой",
		      NSStringFromClass([lockWindow class]), NSStringFromCGSize(lockWindow.bounds.size));
		MPLockScreenSync(); // устройство уже может быть залочено
	} @catch (NSException *e) {
		MPLog(@"!! локскрин: attach — %@ (%@)", e.name, e.reason);
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
	MLSShieldPlace(); // подложка — сразу под нами, выше любого нативного контента
	MLSNativeHidden(YES, @"raise"); // iOS мог показать нативный после нас
	if ([parent.subviews lastObject] != MLSView) {
		[parent bringSubviewToFront:MLSView];
	}
	if (!CGRectEqualToRect(MLSView.frame, parent.bounds)) {
		MLSView.frame = parent.bounds;
	}
}

#pragma mark - Разблокировка

// Тап по иконке камеры (как в WP 8.1 — камера открывается с локскрина).
// Разблокировку отправляем сразу, запуск камеры — следом через полсекунды:
// пока устройство залочено, SpringBoard может придушить [icon launch].
// Если разблокировка не прошла или появился код-пароль — камеру не открываем.
static void MLSCameraTap(void) {
	MPLog(@"локскрин: тап — камера");
	MLSUnlock();
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		if (MLSPasscodeVisible) return; // ждём код — камеру не открываем
		if (MLSIsLocked()) {
			MPLog(@"локскрин: камера отменена (не разлочилось)");
			return;
		}
		@try {
			id ctrl = [objc_getClass("SBIconController") sharedInstance];
			id model = [ctrl respondsToSelector:@selector(model)] ? [ctrl model] : nil;
			NSDictionary *leafs = [model respondsToSelector:@selector(leafIconsByIdentifier)]
			    ? [model leafIconsByIdentifier] : nil;
			for (SBLeafIcon *icon in leafs.allValues) {
				if ([[icon applicationBundleID] isEqualToString:@"com.apple.camera"]) {
					[icon launch];
					MPLog(@"локскрин: камера запущена");
					return;
				}
			}
			MPLog(@"!! локскрин: иконка камеры не найдена в leafIcons");
		} @catch (NSException *e) {
			MPLog(@"!! локскрин: запуск камеры — %@ (%@)", e.name, e.reason);
		}
	});
}

// Отправляем нативное «разблокировать». unlockWithSound: есть в дампах 6.1,
// остальные — запасные: если он не сработает, в журнале будет видно, что
// отправили, и следующий раз можно опереться на рабочий путь.
static BOOL MLSRequestUnlock(void) {
	id away = [objc_getClass("SBAwayController") sharedAwayController];
	if (away == nil) return NO;

	if ([away respondsToSelector:@selector(unlockWithSound:)]) {
		((void (*)(id, SEL, BOOL))objc_msgSend)(away, @selector(unlockWithSound:), NO);
		MPLog(@"локскрин: unlockWithSound: отправлен");
		return YES;
	}
	if ([away respondsToSelector:@selector(unlock)]) {
		((void (*)(id, SEL))objc_msgSend)(away, @selector(unlock));
		MPLog(@"локскрин: unlock отправлен (запасной селектор)");
		return YES;
	}
	if ([away respondsToSelector:@selector(_unlockWithSound:animate:)]) {
		((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(away, @selector(_unlockWithSound:animate:), NO, YES);
		MPLog(@"локскрин: _unlockWithSound:animate: отправлен (запасной селектор)");
		return YES;
	}
	return NO;
}

// Свайп прошёл порог. Свой слайд не играем: окно блокировки уходит вместе с
// нашей вьюхой, поэтому нативный локскрин не показывается ни в один момент.
// Если разблокировка не прошла — через полсекунды возвращаем экран на место.
static void MLSUnlock(void) {
	@try {
		if (MLSPendingUnlock) return;
		MLSPendingUnlock = YES;
		[MLSView stopClockUpdates];
		MPLog(@"локскрин: свайп — разблокировка");

		if (!MLSRequestUnlock()) {
			MPLog(@"!! локскрин: ни один селектор разблокировки не найден");
		}

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			if (!MLSPendingUnlock) return;
			MLSPendingUnlock = NO;

			// Код: нативный экран ввода уже показан, наша вьюха спрятана
			if (MLSPasscodeVisible) {
				MPLog(@"локскрин: разблокировка ждёт код");
				return;
			}
			if (MLSIsLocked()) {
				MPLog(@"!! локскрин: разблокировка не прошла (locked=1) — экран возвращается");
				[MLSView springBack];
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
				               dispatch_get_main_queue(), ^{
					MPLockScreenSync();
				});
				return;
			}
			MLSHideNow(@"разблокировано");
		});
	} @catch (NSException *e) {
		MPLog(@"!! локскрин: unlock — %@ (%@)", e.name, e.reason);
		MLSPendingUnlock = NO;
	}
}

#pragma mark - Синхронизация с состоянием блокировки

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
				MLSHideToken++; // отменяем отложенные скрытия
				if (MLSView.hidden) {
					MLSShowNow();
					MPLog(@"локскрин: показан %@ в %@", NSStringFromCGSize(MLSView.bounds.size),
					      NSStringFromClass([MLSView.superview class]));
					// Страховка: iOS может поднять свой контент позже — через полсекунды
					// проверяем, что мы всё ещё сверху
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
					               dispatch_get_main_queue(), ^{
						MPLockScreenRaise();
					});
				} else {
					// Уже на экране (пробуждение, смена статуса) — только держим верх
					MPLockScreenRaise();
				}
				return;
			}

			if (MLSView.hidden) return; // и так не видно

			if (MLSPasscodeVisible) {
				MLSHideNow(@"экран ввода кода");
				return;
			}

			if (MLSPendingUnlock) {
				// Разблокировка в процессе: окно блокировки должно унести нашу
				// вьюху с собой. Прячем только если окно почему-то осталось.
				MLSHideToken++;
				NSUInteger token = MLSHideToken;
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
				               dispatch_get_main_queue(), ^{
					if (token != MLSHideToken || MLSPendingUnlock) return;
					MLSHideNow(@"разблокировано");
				});
				return;
			}

			MLSHideNow(@"не залочено");
		} @catch (NSException *e) {
			MPLog(@"!! локскрин: sync — %@ (%@)", e.name, e.reason);
		}
	});
}

void MPLockScreenNoteWallpaper(UIImage *image) {
	if (image == nil) return;
	MLSWallpaper = image;
	// Картинку в вьюху подтягивает MLSShowNow (при каждом показе)
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
