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
#import "../MetroLauncher/MPHomeController.h" // MPHomePrepare/Start/CancelUnlockEntry (свайп-анлок)
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
static BOOL MLSSliding = NO;             // вьюха летит вверх (анлок в слайде)
static BOOL MLSUnlockReady = NO;         // анлок подтвердился, слайд ещё не доиграл
static BOOL MLSUnlockDone = NO;          // анлок подтверждён: нативный контент окна не возвращать
static NSUInteger MLSHideToken = 0;      // отменяет отложенные скрытия
static BOOL MLSReordering = NO;          // защита от рекурсии при перестановке вьюх

static void MLSUnlock(void);     // определение ниже, нужен блоку onUnlock
static void MLSShieldPlace(void); // подложка ровно под нашей вьюхой
static void MLSNativeHidden(BOOL hide, NSString *reason); // нативный локскрин
static void MLSCameraTap(void);  // тап по иконке камеры внизу справа
static void MLSNotifyDidHide(NSString *reason); // сигнал лаунчеру «локскрин ушёл»
static void MLSPollUnlock(int attempt);        // опрос состояния после анлока
static void MLSFinishUnlockSlide(void);        // completion слайда-разблокировки
static void MLSSlideStartReveal(void);         // снять непрозрачные слои окна при старте слайда

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
	// Во время слайда-разблокировки подложка снята (лаунчер виден под вьюхой) —
	// Raise не должен вернуть её посреди анимации
	MLSShield.hidden = MLSView.hidden || MLSSliding;
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

BOOL MPLockScreenNotCovering(void) {
	return MLSView == nil || MLSView.hidden;
}

// Сигнал лаунчеру «локскрин ушёл»: Turnstile-въезд играется только теперь
// (не по lockstate). Постится и при раннем анлоке (вьюха ещё в слайде) —
// повторный пост из MLSHideNow лаунчер съедает гвардом _deferEnterForLockscreen.
static void MLSNotifyDidHide(NSString *reason) {
	[[NSNotificationCenter defaultCenter] postNotificationName:MPMetroLockscreenDidHideNotification
	                                                        object:nil];
	MPLog(@"локскрин: сигнал лаунчеру (%@)", reason);
}

static void MLSHideNow(NSString *reason) {
	MLSHideToken++;
	if (MLSView != nil && !MLSView.hidden) {
		MLSView.hidden = YES;
		MPLog(@"локскрин: скрыт (%@)", reason);
	}
	[MLSView stopClockUpdates];
	if (MLSShield != nil) MLSShield.hidden = YES;
	if (MLSUnlockDone) {
		// Анлок подтверждён: нативный локскрин (с зелёным индикатором зарядки)
		// НЕ возвращаем — система сейчас уберёт окно блокировки целиком, а
		// возвращённый контент на эти кадры закрыл бы лаунчер «батарейкой»
		MPLog(@"локскрин: нативный контент оставлен скрытым (анлок подтверждён)");
	} else {
		MLSNativeHidden(NO, reason);
	}
	MLSNotifyDidHide(reason);
}

static void MLSShowNow(void) {
	MLSUnlockDone = NO; // новый показ = новое состояние блокировки
	[MLSView setWallpaperImage:MLSWallpaper];
	[MLSView resetSlide];
	// Экран зажигаем сразу, контент собираем после показа: refreshContent — это
	// скан бейджей по всем приложениям и запрос батареи, на A4 это ощутимая
	// задержка пробуждения. Лейблы дозаполняются в следующем же проходе layout.
	// Появление мягкое (WP): таем из чёрной подложки. Сдвигом transform не
	// пользуемся сознательно: MPLockScreenRaise сверяет frame с bounds родителя,
	// а frame при нетождественном transform в UIKit не определён — Raise в
	// середине fade сбил бы вьюху. Подложка чёрная и мгновенная, за fade ничего
	// не просвечивает; гварды setHidden: смотрят на hidden, а не на alpha.
	MLSView.alpha = 0.0;
	MLSView.hidden = NO;
	MPLockScreenRaise(); // подложка встанет ровно под вьюхой и покажется
	MLSNativeHidden(YES, @"показ"); // родной локскрин не должен просвечивать
	[MLSView refreshContent];
	[MLSView startClockUpdates];
	[UIView animateWithDuration:0.18
	                      delay:0.0
	                    options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
	                 animations:^{
		MLSView.alpha = 1.0;
	}
	                 completion:NULL];
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
			MLSView.onDragBeginBlock = ^{
				MPHomePrepareUnlockEntry(); // прогрев лаунчера: слайд и Turnstile перекроются
			};
			MLSView.onDragAbortBlock = ^{
				MPHomeCancelUnlockEntry(); // свайп не дотянут — прогрев уже не нужен
			};
			MLSView.onUnlockBlock = ^{
				MLSSliding = YES; // анлок идёт параллельно со слайдом
				MLSUnlock();
			};
			MLSView.onSlideDoneBlock = ^{
				MLSFinishUnlockSlide();
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
	// Во время слайда frame уезжает с анимацией center: возврат к bounds родителя
	// здесь сломал бы анимацию (вьюха прыгнула бы обратно) — пропускаем
	if (!MLSSliding && !CGRectEqualToRect(MLSView.frame, parent.bounds)) {
		MLSView.frame = parent.bounds;
	}
}

#pragma mark - Разблокировка

// Запуск камеры с локскрина: тап по иконке внизу справа или свайп влево
// (как в оригинале). Разблокировку отправляем сразу, запуск камеры — следом
// через полсекунды: пока устройство залочено, SpringBoard может придушить
// [icon launch]. Если разблокировка не прошла или появился код-пароль —
// камеру не открываем.
static void MLSCameraTap(void) {
	MPLog(@"локскрин: камера (тап/свайп)");
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

// Свайп прошёл порог (запрос приходит В НАЧАЛЕ слайда) или тап по камере.
// Синхронно — только дешёвое: pending-флаг, стоп часов, reveal, старт turnstile.
// ТЯЖЁЛОЕ (нативный запрос анлока может блокировать главный поток) — в
// dispatch_after 0.03 с: анимации к этому моменту уже закоммичены (flush во
// вьюхе) и ушли в рендер-процесс. Опрос подтверждает анлок для закрытия окна
// в конце слайда (MLSUnlockReady → слайд доиграл). Пасскод и провал отменяют
// прогретый лаунчер.
static void MLSUnlock(void) {
	@try {
		if (MLSPendingUnlock) return;
		MLSPendingUnlock = YES;
		[MLSView stopClockUpdates];
		MPLog(@"анлок-хроника: отпускание (слайд=%d) t=%.3f", MLSSliding ? 1 : 0, CACurrentMediaTime());
		if (MLSSliding) MLSSlideStartReveal(); // дёшево, нужен визуально в первом кадре
		MPHomeStartUnlockEntry();              // turnstile-анимации в этот же коммит

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			if (!MLSPendingUnlock) return;
			NSTimeInterval t0 = CACurrentMediaTime();
			BOOL ok = MLSRequestUnlock();
			MPLog(@"анлок-хроника: MLSRequestUnlock занял %.0f мс (ok=%d)",
			      (CACurrentMediaTime() - t0) * 1000.0, ok ? 1 : 0);
			if (!ok) MPLog(@"!! локскрин: ни один селектор разблокировки не найден");
			MLSPollUnlock(0);
		});
	} @catch (NSException *e) {
		MPLog(@"!! локскрин: unlock — %@ (%@)", e.name, e.reason);
		MLSPendingUnlock = NO;
	}
}

// Потолок ожидания: 12 попыток × 60 мс ≈ 0.72 с (на A4 нативный анлок укладывается)
#define MLS_UNLOCK_POLL_ATTEMPTS 12

// Старт слайда-разблокировки. Под уезжающей вьюхой в том же окне блокировки
// остаются непрозрачные слои: чёрная подложка MLSShield, фон самого окна, а
// после скрытия вьюхи — нативный локскрин с индикатором зарядки. Они закрывали
// лаунчер (SBAppWindow ниже по уровню): на видео под слайдом «тёмная яма»,
// после ухода вьюхи — вспышка батарейки. Дампаем иерархию (кто непрозрачный,
// есть ли вторая копия локскрина) и снимаем подложку + фон окна — наша вьюха
// остаётся единственным непрозрачным слоем и открывает лаунчер.
static void MLSSlideStartReveal(void) {
	if (MLSView == nil) return;
	UIWindow *w = MLSView.window;
	if (w == nil) return;

	MPLog(@"анлок-хроника: дамп окна блокировки t=%.3f: %@ level=%.0f opaque=%d bg=%@, вьюх=%lu",
	      CACurrentMediaTime(), NSStringFromClass([w class]), (double)w.windowLevel,
	      w.opaque ? 1 : 0,
	      w.backgroundColor == nil ? @"nil" : @"есть",
	      (unsigned long)w.subviews.count);
	int idx = 0;
	for (UIView *sub in w.subviews) {
		MPLog(@"анлок-хроника:   [%d] %@ frame=%@ hidden=%d alpha=%.2f bg=%@%@",
		      idx++, NSStringFromClass([sub class]), NSStringFromCGRect(sub.frame),
		      sub.hidden ? 1 : 0, sub.alpha,
		      sub.backgroundColor == nil ? @"nil" : @"цвет",
		      sub == MLSView ? @" <- наш экран" : (sub == MLSShield ? @" <- подложка" : @""));
	}

	if (MLSShield != nil && MLSShield.superview == w) MLSShield.hidden = YES;
	if (![w.backgroundColor isEqual:[UIColor clearColor]]) w.backgroundColor = [UIColor clearColor];
	MPLog(@"анлок-хроника: лаунчер реально виден (подложка и фон окна сняты) t=%.3f",
	      CACurrentMediaTime());
}

static void MLSPollUnlock(int attempt) {
	if (!MLSPendingUnlock) return;

	// Код: нативный экран ввода уже показан, нашу вьюху прячет sync — ждать нечего
	if (MLSPasscodeVisible) {
		MLSPendingUnlock = NO;
		MPHomeCancelUnlockEntry(); // прогретый лаунчер под экраном кода не нужен
		MPLog(@"локскрин: разблокировка ждёт код");
		return;
	}

	if (!MLSIsLocked()) {
		MLSPendingUnlock = NO;
		MLSUnlockDone = YES; // нативный контент окна после скрытия не возвращать
		MPLog(@"анлок-хроника: анлок подтвердился (попытка %d) t=%.3f", attempt + 1, CACurrentMediaTime());
		if (MLSSliding) {
			// Вьюха ещё в слайде: скрытие и возврат нативного контента — по
			// завершении слайда; въезд лаунчера стартует независимо (по прогрессу)
			MLSUnlockReady = YES;
			return;
		}
		MLSHideNow(@"разблокировано");
		return;
	}

	if (attempt >= MLS_UNLOCK_POLL_ATTEMPTS - 1) {
		MLSPendingUnlock = NO;
		MPHomeCancelUnlockEntry(); // въезд по прогрессу мог уже играть — прячем
		MPLog(@"!! локскрин: разблокировка не прошла (locked=1) — экран возвращается");
		[MLSView springBack];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			MPLockScreenSync();
		});
		return;
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		MLSPollUnlock(attempt + 1);
	});
}

// Слайд-разблокировка доиграла: вьюха за верхним краем. Анлок уже подтвердился —
// завершаем скрытие (вьюха, нативный контент); нет — ждём опрос: успех вызовет
// MLSHideNow сам, провал вернёт вьюху пружиной с верхнего края.
static void MLSFinishUnlockSlide(void) {
	MLSSliding = NO;
	MPLog(@"анлок-хроника: слайд доиграл t=%.3f", CACurrentMediaTime());
	if (!MLSUnlockReady) {
		// Пасскод успел показаться, пока вьюха летела: прячемся перед экраном кода
		if (MLSPasscodeVisible) MLSHideNow(@"экран ввода кода");
		return;
	}
	MLSUnlockReady = NO;
	MLSHideNow(@"разблокировано (слайд доиграл)");
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

			if (MLSSliding) {
				// Слайд-разблокировка управляет скрытием сама (MLSFinishUnlockSlide):
				// прятать вьюху посреди слайда нельзя — «срез» анимации и досрочный
				// сигнал «локскрин скрыт», запускавший въезд раньше времени
				return;
			}

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
