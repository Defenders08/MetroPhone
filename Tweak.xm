// MetroPhone — твик-тема Windows Phone (Metro) для iOS 6.
//
// Две группы хуков:
//   MPUikit       — работает в любом процессе с UIKit (плоские панели, статус-бар, шрифты заголовков);
//   MPSpringBoard — только в SpringBoard (плитки, чёрный фон, док, подписи иконок).
//
// Имена классов SpringBoard сверены с дампом заголовков iOS 6.1 (MP0w/iOS-Headers).
// Примечания:
//   - %orig всегда последним оператором или отдельным statement'ом — конструкции
//     вида `{ %orig; return; }` препроцессор Logos обрабатывает неверно;
//   - всё рискованное обложено MPLog-«хлебными крошками» и @try: если SpringBoard
//     упадёт, последняя строка в /var/mobile/Library/Preferences/metrophone.log
//     укажет виновный хук.

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <time.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <objc/message.h>
#import "MetroPhoneCommon.h"
#import "MetroLauncher/MPMetroStyle.h"
#import "MetroLockScreen/MPLockScreen.h"

#define MP_VERSION @"0.21.64"
#define MP_LOG_PATH "/var/mobile/Library/Preferences/metrophone.log"

#pragma mark - Журналирование

// MPLog — общий журнал, реализация в MetroLauncher/MPMetroStyle.m

// Для часто срабатывающих хуков: пишем только первый вызов по ключу.
static void MPLogOnce(NSString *key, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static void MPLogOnce(NSString *key, NSString *format, ...) {
	static NSMutableSet *seen = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ seen = [[NSMutableSet alloc] init]; });
	@synchronized (seen) {
		if ([seen containsObject:key]) return;
		[seen addObject:key];
	}
	va_list args;
	va_start(args, format);
	NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	MPLog(@"[первый раз] %@", line);
}

#pragma mark - Чтение настроек

// CFPreferences сам отслеживает изменения из настроек между процессами,
// поэтому читаем значения на лету, без кэша и Darwin-уведомлений.

static BOOL MPFlag(NSString *key, BOOL def) {
	CFTypeRef v = CFPreferencesCopyAppValue((CFStringRef)key, CFSTR(MP_PREFS_DOMAIN));
	if (v == NULL) return def;
	BOOL result = def;
	if (CFGetTypeID(v) == CFBooleanGetTypeID()) result = CFBooleanGetValue((CFBooleanRef)v);
	else if (CFGetTypeID(v) == CFNumberGetTypeID()) result = [(__bridge NSNumber *)v boolValue];
	CFRelease(v);
	return result;
}

static NSString *MPString(NSString *key, NSString *def) {
	NSString *v = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)key, CFSTR(MP_PREFS_DOMAIN)));
	return v ?: def;
}


#pragma mark - Состояние

static BOOL MPOn(void)        { return MPFlag(MPKeyEnabled, YES); }
static BOOL MPFlatPanels(void){ return MPOn() && MPFlag(MPKeyFlatPanels, YES); }
static BOOL MPTilesOn(void)   { return MPOn() && MPFlag(MPKeyTiles, YES); }
static BOOL MPWallOn(void)    { return MPOn() && MPFlag(MPKeyBlackWallpaper, YES); }
static BOOL MPLabelsOn(void)  { return MPOn() && MPFlag(MPKeyMetroLabels, YES); }
static BOOL MPUpperOn(void)   { return MPOn() && MPFlag(MPKeyUppercase, YES); }
static BOOL MPTileAccent(void){ return YES; }   // режим тёмных плиток убран

#pragma mark - Цвета и шрифты

// Палитра Windows Phone: имя из настроек → HEX.
static NSDictionary *MPAccentHexes(void) {
	static NSDictionary *map = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			@"blue":    @"1BA1E2",
			@"purple":  @"A200FF",
			@"magenta": @"D80073",
			@"green":   @"008A00",
			@"lime":    @"A4C400",
			@"orange":  @"F09609",
			@"red":     @"E51400",
			@"teal":    @"00ABA9",
		};
	});
	return map;
}

static UIColor *MPColorFromHex(NSString *hex) {
	if (hex.length != 6) return [UIColor colorWithRed:0.106 green:0.631 blue:0.886 alpha:1.0]; // #1BA1E2
	unsigned value = 0;
	NSScanner *scanner = [NSScanner scannerWithString:hex];
	[scanner scanHexInt:&value];
	return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0
	                           green:((value >> 8) & 0xFF) / 255.0
	                            blue:(value & 0xFF) / 255.0
	                           alpha:1.0];
}

static UIColor *MPAccentColor(void) {
	NSString *hex = MPAccentHexes()[MPString(MPKeyAccent, @"blue")];
	return MPColorFromHex(hex ?: @"1BA1E2");
}

// Цвет подложки плиток: тёмно-серый (по умолчанию) или акцентный.
static UIColor *MPTileColor(void) {
	if (MPTileAccent()) return MPAccentColor();
	return [UIColor colorWithWhite:0.12 alpha:1.0];
}

// Шрифт в духе Segoe WP. Thin/UltraLight/Light/Medium есть в iOS 6;
// у «обычного» начертания имя без суффикса — просто HelveticaNeue.
// Результат кэшируется: UIFont fontWithName: в момент раннего старта процесса
// на iOS 6 может дедлочить главный поток (CoreText ещё не инициализирован),
// поэтому внутрь конструктора твика он не попадает никогда.
static UIFont *MPFont(NSString *postfix, CGFloat size) {
	static NSMutableDictionary *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [[NSMutableDictionary alloc] init]; });

	NSString *name = [postfix isEqualToString:@"Regular"]
	    ? @"HelveticaNeue"
	    : [@"HelveticaNeue-" stringByAppendingString:postfix];
	NSString *key = [NSString stringWithFormat:@"%@@%.0f", name, size];

	@synchronized (cache) {
		UIFont *cached = [cache objectForKey:key];
		if (cached != nil) return cached;
		UIFont *f = [UIFont fontWithName:name size:size] ?: [UIFont systemFontOfSize:size];
		[cache setObject:f forKey:key];
		MPLog(@"шрифт: %@ → %@", name, f.fontName);
		return f;
	}
}

static UIImage *MPSolidImage(CGFloat w, CGFloat h, UIColor *color) {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, h), NO, 1.0);
	[color setFill];
	UIRectFill(CGRectMake(0, 0, w, h));
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

// Растяжимая чёрная полоска для панелей через UIAppearance.
static UIImage *MPBlackStretchImage(void) {
	UIImage *img = MPSolidImage(1, 1, [UIColor blackColor]);
	return [img resizableImageWithCapInsets:UIEdgeInsetsZero];
}

#pragma mark - Плитки (SpringBoard)

// Холодная загрузка SpringBoard — самое уязвимое окно (вотчдог/память):
// первые 60 секунд после запуска плитки не строим вовсе,
// на тёплых запусках они мгновенно берутся из дискового кэша.
static CFAbsoluteTime MPSBLaunchTime = 0;
static BOOL MPBootWarmupActive(void) {
	if (MPSBLaunchTime == 0) return NO;
	return (CFAbsoluteTimeGetCurrent() - MPSBLaunchTime) < 60.0;
}

// Ищем исходный квадратный PNG иконки в бандле приложения.
// В iOS 6 иконки в бандлах — полные квадраты; скругления и глянец накладывает SpringBoard.
static NSCache *MPPngCache(void) {
	static NSCache *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
	return cache;
}

static UIImage *MPRawAppIcon(NSString *bundlePath) {
	if (bundlePath.length == 0) return nil;

	id cached = [MPPngCache() objectForKey:bundlePath];
	if (cached != nil) return [cached isKindOfClass:[UIImage class]] ? cached : nil;

	UIImage *best = nil;
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
		[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
	if (info != nil) {
		NSMutableDictionary *candidates = [NSMutableDictionary dictionary];
		void (^consider)(NSString *) = ^(NSString *path) {
			if (path.length == 0 || [candidates objectForKey:path] != nil) return;
			if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
				UIImage *img = [UIImage imageWithContentsOfFile:path];
				if (img != nil) [candidates setObject:img forKey:path];
			}
		};
		NSString *bundle = bundlePath;
		NSArray *iconFiles = nil;
		NSDictionary *primary = [info objectForKey:@"CFBundleIcons"][@"CFBundlePrimaryIcon"];
		if (primary != nil) iconFiles = [primary objectForKey:@"CFBundleIconFiles"];
		if (iconFiles == nil) iconFiles = [info objectForKey:@"CFBundleIconFiles"];

		NSMutableArray *names = [NSMutableArray arrayWithArray:iconFiles ?: @[]];
		NSString *legacy = [info objectForKey:@"CFBundleIconFile"];
		if (legacy != nil) [names addObject:legacy];

		for (NSString *name in names) {
			// как есть и в вариантах масштаба/расширения — выбираем потом самый крупный
			consider([bundle stringByAppendingPathComponent:name]);
			consider([bundle stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]]);
			consider([bundle stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x.png", name]]);
			consider([bundle stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x", name]]);
		}

		CGFloat bestPx = 0;
		for (UIImage *img in candidates.allValues) {
			CGFloat px = img.size.width * img.scale;
			if (px > bestPx) { bestPx = px; best = img; }
		}
	}

	// промахи тоже кэшируем, чтобы не перечитывать Info.plist на каждый вызов
	[MPPngCache() setObject:(best ?: (id)[NSNull null]) forKey:bundlePath];
	MPLog(@"  raw-иконка %@: %@", bundlePath.lastPathComponent, best ? [NSString stringWithFormat:@"%@@%.0fx", NSStringFromCGSize(best.size), best.scale] : @"не найден, подложка");
	return best;
}

// Собираем квадратную плитку: исходная квадратная иконка на весь размер,
// а если не нашли PNG — подложка + оригинальная (уже скруглённая) иконка.
static UIImage *MPTileImage(UIImage *orig, NSString *bundlePath) {
	if (orig == nil) return nil;

	__block UIImage *tile = nil;
	@try {
		CGFloat scale = orig.scale > 0 ? orig.scale : 1.0;
		UIGraphicsBeginImageContextWithOptions(orig.size, NO, scale);

		UIImage *raw = MPRawAppIcon(bundlePath);
		if (raw != nil) {
			// вписываем с сохранением пропорций и обрезкой краёв (aspect fill)
			CGFloat ratio = MAX(orig.size.width / raw.size.width, orig.size.height / raw.size.height);
			CGSize drawn = CGSizeMake(raw.size.width * ratio, raw.size.height * ratio);
			[raw drawInRect:CGRectMake((orig.size.width - drawn.width) / 2.0,
			                           (orig.size.height - drawn.height) / 2.0,
			                           drawn.width, drawn.height)];
		} else {
			[MPTileColor() setFill];
			UIRectFill(CGRectMake(0, 0, orig.size.width, orig.size.height));
			[orig drawAtPoint:CGPointZero];
		}

		tile = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	} @catch (NSException *e) {
		MPLog(@"!! MPTileImage исключение: %@ (%@)", e.name, e.reason);
		tile = orig; // при любой ошибке возвращаем оригинал
	}
	return tile;
}

// Дозапуск плиток после прогрева: SpringBoard кэширует иконки и сам больше
// не переспрашивает generateIconImage:, просим каждую иконку перезагрузиться.
@interface SBIconController : NSObject
+ (id)sharedInstance;
- (id)model;
@end

@interface SBIconModel : NSObject
- (NSDictionary *)leafIconsByIdentifier;
@end

static void MPScheduleTileKick(void) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(70 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			@try {
				id controller = [objc_getClass("SBIconController") sharedInstance];
				id model = [controller respondsToSelector:@selector(model)] ? [controller model] : nil;
				NSDictionary *leafs = [model respondsToSelector:@selector(leafIconsByIdentifier)]
					? [model leafIconsByIdentifier] : nil;
				NSArray *icons = leafs.allValues;
				MPLog(@"дозапуск: перезагружаю %lu иконок", (unsigned long)icons.count);
				for (id icon in icons) {
					if ([icon respondsToSelector:@selector(reloadIconImage)]) {
						[icon performSelector:@selector(reloadIconImage)];
					}
				}
			} @catch (NSException *e) {
				MPLog(@"!! дозапуск: %@ (%@)", e.name, e.reason);
			}
		});
}

// Дисковый кэш готовых плиток (переживает respring; ключ включает настройки темы).
// Имя файла содержит @2x — UIImage сам подберёт масштаб при чтении.
static NSString *MPTileCachePath(NSString *bid, int format, CGFloat scale) {
	static NSString *dir = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dir = @"/var/mobile/Library/Caches/metrophone";
		[[NSFileManager defaultManager] createDirectoryAtPath:dir
		                          withIntermediateDirectories:YES attributes:nil error:NULL];
	});
	NSString *style = [NSString stringWithFormat:@"%@-%ld", MPString(MPKeyAccent, @"blue"), (long)1];
	NSString *suffix = scale > 2.5 ? @"@3x" : (scale > 1.5 ? @"@2x" : @"");
	return [dir stringByAppendingPathComponent:
		[NSString stringWithFormat:@"tile-%@-f%d-%@v6%@.png", bid, format, style, suffix]];
}

// Декодированные плитки с диска, чтобы не читать PNG повторно на главном потоке.
// Ключ — полный путь (в нём уже есть формат, акцент и масштаб), поэтому старых
// записей при смене темы не остаётся: сменилась тема — сменился путь.
static NSCache *MPTileDiskCache(void) {
	static NSCache *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [[NSCache alloc] init];
		cache.countLimit = 120;          // ~45 приложений × форматы, с запасом
	});
	return cache;
}

// Защита от повторного планирования фоновой сборки для одной иконки
static BOOL MPMarkPending(NSString *bid, int format) {
	static NSMutableSet *pending = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ pending = [[NSMutableSet alloc] init]; });
	NSString *key = [NSString stringWithFormat:@"%@@%d", bid, format];
	@synchronized (pending) {
		if ([pending containsObject:key]) return NO;
		[pending addObject:key];
		return YES;
	}
}

static void MPUnmarkPending(NSString *bid, int format) {
	static NSMutableSet *pending = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ pending = [[NSMutableSet alloc] init]; });
	NSString *key = [NSString stringWithFormat:@"%@@%d", bid, format];
	@synchronized (pending) { [pending removeObject:key]; }
}

#pragma mark - Заголовки навигационных панелей

// На iOS 6 заголовок UINavigationBar — UILabel во внутренних вьюхах.
// Рекурсивно находим и один раз оформляем каждый лейбл.
static void *MPMetroTitleKey = &MPMetroTitleKey;
static void *MPHeartbeatKey = &MPHeartbeatKey;
static dispatch_source_t MPHeartbeatSource = nil; // сердцебиение SpringBoard

static void MPApplyTitleToLabel(UILabel *label) {
	if (objc_getAssociatedObject(label, MPMetroTitleKey) != nil) return;
	objc_setAssociatedObject(label, MPMetroTitleKey, @YES, OBJC_ASSOCIATION_RETAIN);

	label.font = MPFont(@"Thin", 22);
	label.textColor = [UIColor whiteColor];
	label.shadowColor = nil;
	label.shadowOffset = CGSizeZero;
	if (MPUpperOn()) label.text = [label.text uppercaseStringWithLocale:[NSLocale currentLocale]];
	MPLogOnce(@"navbar-label", @"первый заголовок оформлен: %@", label.text);
}

static void MPApplyMetroTitle(UIView *view) {
	for (UIView *sub in view.subviews) {
		// Кнопки панели (UINavigationButton/UIButton) — НЕ заголовок: их подпись
		// нельзя красить и раздувать до 22 pt (иначе «Изменить» режется в «Из…ть»)
		if ([sub isKindOfClass:[UIControl class]]) continue;
		if ([sub isKindOfClass:[UILabel class]]) {
			MPApplyTitleToLabel((UILabel *)sub);
		} else {
			MPApplyMetroTitle(sub);
		}
	}
}

#pragma mark - Приватные классы SpringBoard (iOS 6.1)

// Минимальные объявления по дампу заголовков iOS 6.1 (MP0w/iOS-Headers):
// Logos даёт только @class, а ARC требует знать селекторы.
// Селекторы SBApplication сверены с бинарником SpringBoard 6.1.3 (python-дамп):
// displayIdentifier, isRunning, pid, _pid — есть; runningApplications у
// контроллера на этой прошивке нет (см. MPRunningAppIDs ниже).
@interface SBApplication : NSObject
- (NSString *)path;
- (NSString *)displayIdentifier;   // идентификатор запущенного приложения
- (BOOL)isRunning;                 // жив ли процесс приложения
- (pid_t)_pid;
- (pid_t)pid;
@end

// Список приложений (свитчер многозадачности). runningApplications на iOS 6 нет —
// только allApplications (все установленные), состояние берём у SBApplication.
@interface SBApplicationController : NSObject
+ (id)sharedInstance;
- (NSArray *)allApplications;
- (id)applicationWithDisplayIdentifier:(NSString *)identifier;
@end

// Живые снимки приложений (механизм системного жеста «предыдущее приложение» iOS 6.1)
@interface SBUIController : NSObject
+ (id)sharedInstance;
- (id)systemGestureSnapshotForApp:(id)app includeStatusBar:(BOOL)includeStatusBar decodeImage:(BOOL)decodeImage;
@end

// Модель родного бара многозадачности: недавние приложения (порядок для свитчера)
@interface SBAppSwitcherModel : NSObject
+ (id)sharedInstance;
- (NSArray *)identifiers;
@end

@interface SBApplicationIcon : NSObject
- (id)application;
- (NSString *)applicationBundleID;
- (void)reloadIconImage;
@end

@interface SBWallpaperView : UIImageView
@end

// Главное окно SpringBoard: в нём живёт Metro-локскрин, и его надо держать
// поверх любых добавлений (базовый класс нужен ARC-конверсии self в хуках)
@interface SBAppWindow : UIWindow
@end

// Нативный экран блокировки: из его вьюхи узнаём окно локскрина; пока показан
// наш Metro-локскрин, сам прячем (иначе просвечивает под нашей вьюхой)
@interface SBAwayView : UIView
@end

// Окно нативного локскрина (наш Metro-локскрин живёт в нём же) — в нём надо
// держать нашу вьюху поверх всего и гасить контент, который iOS поднимает сам
@interface SBAlertWindow : UIWindow
@end

@interface SBIconView : UIView
@end

#pragma mark - Ленивая настройка UIAppearance

// Вызывается при первой отрисовке панели — к этому моменту CoreText прогрет,
// и UIFont fontWithName: безопасен. Dispatch-once гарантирует однократность.
static void MPConfigureAppearanceIfNeeded(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		@try {
			MPLog(@"appearance: начинаю настройку");
			UIColor *accent = MPAccentColor();
			NSDictionary *buttonAttrs = @{
				UITextAttributeFont: MPFont(@"Medium", 12),
				UITextAttributeTextColor: accent,
				UITextAttributeTextShadowColor: [UIColor clearColor],
			};
			[[UIBarButtonItem appearance] setTitleTextAttributes:buttonAttrs forState:UIControlStateNormal];
			MPLog(@"appearance: UIBarButtonItem готов");
			// setTitleTextAttributes у UITabBarItem в SDK нет — цвет выделения задаём тинтом
			[[UITabBar appearance] setSelectedImageTintColor:accent];
			MPLog(@"appearance: UITabBar tint готов");
			[[UISearchBar appearance] setBackgroundImage:MPBlackStretchImage()];
			MPLog(@"appearance: UISearchBar фон готов (акцент %@)", accent);
		} @catch (NSException *e) {
			MPLog(@"!! appearance: %@ (%@)", e.name, e.reason);
		}
	});
}

#pragma mark - Хуки: UIKit (все процессы)

%group MPUikit

%hook UINavigationBar
- (void)drawRect:(CGRect)rect {
	if (MPFlatPanels()) {
		MPConfigureAppearanceIfNeeded();
		MPLogOnce(@"navbar-drawrect", @"UINavigationBar: плоский чёрный фон");
		[[UIColor blackColor] setFill];
		UIRectFill(rect);
		return;
	}
	%orig;
}

- (void)layoutSubviews {
	%orig;
	if (MPFlatPanels()) MPApplyMetroTitle(self);
}

// Заголовок панели в стиле WP: тонкий шрифт и белый цвет даже при явных атрибутах приложения
- (void)setTitleTextAttributes:(NSDictionary *)attributes {
	if (!MPFlatPanels()) {
		%orig;
		return;
	}
	MPLogOnce(@"navbar-titleattrs", @"UINavigationBar: подмена titleTextAttributes");
	NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:attributes ?: @{}];
	merged[UITextAttributeFont] = MPFont(@"Thin", 22);
	merged[UITextAttributeTextColor] = [UIColor whiteColor];
	merged[UITextAttributeTextShadowColor] = [UIColor clearColor];
	%orig(merged);
}
%end

%hook UIToolbar
- (void)drawRect:(CGRect)rect {
	if (MPFlatPanels()) {
		MPConfigureAppearanceIfNeeded();
		MPLogOnce(@"toolbar-drawrect", @"UIToolbar: плоский чёрный фон");
		[[UIColor blackColor] setFill];
		UIRectFill(rect);
		return;
	}
	%orig;
}
%end

%hook UITabBar
- (void)drawRect:(CGRect)rect {
	if (MPFlatPanels()) {
		MPConfigureAppearanceIfNeeded();
		MPLogOnce(@"tabbar-drawrect", @"UITabBar: плоский чёрный фон");
		[[UIColor blackColor] setFill];
		UIRectFill(rect);
		return;
	}
	%orig;
}
%end

// Светлый текст статус-бара везде, как в Windows Phone
%hook UIApplication
- (void)setStatusBarStyle:(UIStatusBarStyle)style animated:(BOOL)animated {
	if (MPFlatPanels()) {
		static NSInteger lastLogged = -1;
		if ((NSInteger)style != lastLogged) {
			lastLogged = style;
			MPLog(@"статус-бар: стиль %ld → BlackOpaque", (long)style);
		}
		style = UIStatusBarStyleBlackOpaque;
	}
	%orig(style, animated);
}
%end

%end // MPUikit

#pragma mark - Хуки: SpringBoard

%group MPSpringBoard

// Квадратные плитки вместо скруглённых иконок с глянцем
%hook SBApplicationIcon
// Плитки строятся НЕ в главном потоке: 45 иконок за раз на iPhone 4 занимают ~30 с
// и убивают SpringBoard лаунч-вотчдогом. Схема как в настоящем Windows Phone:
// 1) готовая плитка из дискового кэша — мгновенно;
// 2) иначе отдаём обычную иконку и строим плитку в фоне;
// 3) по готовности пишем PNG в кэш и просим SpringBoard перезагрузить иконку.
- (UIImage *)generateIconImage:(int)format {
	UIImage *orig = %orig;
	if (!MPTilesOn() || orig == nil) return orig;

	NSString *bid = [self applicationBundleID] ?: @"?";
	NSString *tilePath = MPTileCachePath(bid, format, orig.scale);

	// 1) готовая плитка: сначала из памяти, иначе с диска
	// Декодирование PNG на главном потоке стоит несколько миллисекунд на иконку,
	// а SpringBoard спрашивает одни и те же иконки повторно (reloadIconImage).
	UIImage *disk = [MPTileDiskCache() objectForKey:tilePath];
	if (disk == nil) {
		disk = [UIImage imageWithContentsOfFile:tilePath];
		if (disk != nil) [MPTileDiskCache() setObject:disk forKey:tilePath];
	}
	if (disk != nil) {
		MPLogOnce([@"disk-" stringByAppendingString:bid], @"плитка из кэша: %@", bid);
		return disk;
	}

	// 2) на холодной загрузке плитки не строим — только после прогрева
	if (MPBootWarmupActive()) return orig;

	// 3) фон-сборка (по одной на иконку)
	if (MPMarkPending(bid, format)) {
		NSString *bundlePath = nil;
		@try {
			id app = [self application];
			if ([app respondsToSelector:@selector(path)]) bundlePath = [app path];
		} @catch (NSException *e) {
			MPLog(@"!! application/path: %@ (%@)", e.name, e.reason);
		}

		__block UIImage *origImage = orig;
		__block NSString *bPath = bundlePath;
		__block NSString *bBid = bid;
		__block int bFormat = format;
		__block NSString *bPath2 = tilePath;

		// СТРОГО по одной плитке за раз: 45 параллельных декодирований PNG
		// на холодном старте дают скачок памяти, и iOS прибивает SpringBoard.
		static dispatch_queue_t tileQueue = nil;
		static dispatch_once_t onceQueue;
		dispatch_once(&onceQueue, ^{
			tileQueue = dispatch_queue_create("ru.ash.metrophone.tiles", DISPATCH_QUEUE_SERIAL);
		});

		dispatch_async(tileQueue, ^{
			@autoreleasepool {
				MPLog(@"плитка фоном: %@ формат=%d", bBid, bFormat);
				UIImage *tile = MPTileImage(origImage, bPath);
				if (tile != nil) {
					BOOL saved = [UIImagePNGRepresentation(tile) writeToFile:bPath2 atomically:YES];
					MPLog(@"  фоном %@: %@ → диск %@", bBid, NSStringFromCGSize(tile.size), saved ? @"ок" : @"НЕ записан");
				} else {
					MPLog(@"  фоном %@: пусто", bBid);
				}
				MPUnmarkPending(bBid, bFormat);
				dispatch_async(dispatch_get_main_queue(), ^{
					@try {
						[(SBApplicationIcon *)self reloadIconImage];
					} @catch (NSException *e) {
						MPLog(@"!! reloadIconImage: %@ (%@)", e.name, e.reason);
					}
				});
			}
		});
	}

	// 3) пока плитки нет — обычная иконка
	return orig;
}
%end

%hook SBFolderIcon
- (UIImage *)generateIconImage:(int)format {
	MPLog(@"папка: формат=%d", format);
	UIImage *orig = %orig;
	if (!MPTilesOn() || orig == nil) return orig;
	if (MPBootWarmupActive()) return orig;
	UIImage *tile = MPTileImage(orig, nil);
	MPLog(@"  папка-плитка: orig %@ → %@", NSStringFromCGSize(orig.size), tile ? NSStringFromCGSize(tile.size) : @"nil");
	return tile ?: orig;
}
%end

// Тени и отражения под иконками убираем, но не возвращаем nil —
// nil-вьюхи SpringBoard может добавить через addSubview: и упасть.
%hook SBIconView
- (id)createShadowImageView {
	UIImageView *view = %orig;
	if ((MPTilesOn() || MPWallOn()) && view != nil) {
		view.hidden = YES;
		view.alpha = 0.0;
	}
	MPLogOnce(@"sbi-shadow", @"SBIconView: тень %@ (скрыта=%d)", view ? @"создана" : @"нет", (MPTilesOn() || MPWallOn()));
	return view;
}

- (void)_updateShadow {
	if (MPTilesOn() || MPWallOn()) return; // без тени
	%orig;
}

- (BOOL)showsReflection {
	if (MPTilesOn()) return NO;
	return %orig;
}

- (void)updateReflection {
	if (MPTilesOn()) return; // без отражения
	%orig;
}

- (void)setFrame:(struct CGRect)frame {
	MPSetHostWindow(self.window); // второй источник главного окна (иконки видны = окно живо)
	%orig;
	// Селектор вызывается постоянно (лейаут и скролл иконок), поэтому журналируем
	// ровно один раз простым флагом: без @synchronized и словаря MPLogOnce.
	static BOOL mpFrameLogged = NO;
	if (!mpFrameLogged) {
		mpFrameLogged = YES;
		MPLog(@"SBIconView.setFrame: %@", NSStringFromCGRect(frame));
	}
}

- (void)didMoveToWindow {
	%orig;
	// иконок сотни — как только хоть одна получила окно, запоминаем его
	MPSetHostWindow(self.window);
}
%end

// Подписи иконок в стиле Segoe WP
%hook SBIconLabelImageParameters
- (UIFont *)font {
	UIFont *orig = %orig;
	if (!MPLabelsOn()) return orig;
	UIFont *f = MPFont(@"Regular", orig.pointSize);
	MPLogOnce(@"label-font", @"подпись: шрифт %@ → %@", orig.fontName, f.fontName);
	return f;
}

- (UIColor *)textColor {
	if (!MPLabelsOn()) return %orig;
	MPLogOnce(@"label-textcolor", @"подпись: цвет → белый");
	return [UIColor whiteColor];
}

- (UIColor *)shadowColor {
	if (!MPLabelsOn()) return %orig;
	MPLogOnce(@"label-shadowcolor", @"подпись: тень убрана");
	return nil;
}

- (float)shadowBlur {
	if (!MPLabelsOn()) return %orig;
	MPLogOnce(@"label-shadowblur", @"подпись: blur → 0");
	return 0.0;
}

- (CGSize)shadowOffset {
	if (!MPLabelsOn()) return %orig;
	MPLogOnce(@"label-shadowoffset", @"подпись: offset → 0");
	return CGSizeZero;
}

- (NSString *)text {
	NSString *orig = %orig;
	if (!MPLabelsOn() || orig == nil || !MPUpperOn()) return orig;
	NSString *up = [orig uppercaseStringWithLocale:[NSLocale currentLocale]];
	MPLogOnce(@"label-text", @"подпись: «%@» → «%@» (и все остальные)", orig, up);
	return up;
}
%end

// Чёрный фон вместо обоев (дома и на экране блокировки)
%hook SBWallpaperView
- (void)didMoveToWindow {
	%orig;
	// sharedApplication.windows пуст в iOS 6 — окно берём отсюда;
	// в didMoveToWindow self.window гарантированно установлен
	MPSetHostWindow(self.window);
}

- (void)setImage:(UIImage *)image {
	MPSetHostWindow(self.window); // дублируем на случай пропуска didMoveToWindow
	// Оригинальные обои нужны Metro-локскрину; 1×1 — наша же чёрная подмена
	// (из blackWallpaper и resetCurrentImageToWallpaper), её не запоминаем
	if (image == nil || image.size.width > 2.0) MPLockScreenNoteWallpaper(image);
	MPLog(@"обои setImage: %@ → %@", image ? NSStringFromCGSize(image.size) : @"nil",
	      MPWallOn() ? @"чёрный" : @"как есть");
	if (MPWallOn()) {
		%orig(MPSolidImage(1, 1, [UIColor blackColor]));
		return;
	}
	%orig;
}

- (void)resetCurrentImageToWallpaper {
	MPLog(@"обои resetCurrentImageToWallpaper");
	%orig;
	if (MPWallOn()) {
		[(UIImageView *)self setImage:MPSolidImage(1, 1, [UIColor blackColor])];
		MPLog(@"обои: подменено на чёрный после reset");
	}
}

- (void)replaceWallpaperWithImage:(UIImage *)image {
	MPLog(@"обои replaceWallpaperWithImage: %@", image ? NSStringFromCGSize(image.size) : @"nil");
	if (MPWallOn()) {
		%orig(MPSolidImage(1, 1, [UIColor blackColor]));
		return;
	}
	%orig;
}

- (void)_setGradientImagesWithOrientation:(int)orientation {
	if (MPWallOn()) {
		MPLogOnce(@"wallpaper-gradient", @"обои: градиенты пропущены");
		return; // без градиентов поверх фона
	}
	%orig;
}
%end

// Metro-локскрин занимает главное окно целиком; всё, что iOS добавляет или
// поднимает после нас (контент нативного локскрина), немедленно оказывается
// под нашей непрозрачной вьюхой
%hook SBAppWindow
- (void)didAddSubview:(UIView *)subview {
	%orig;
	MPLockScreenRaise();
}

- (void)layoutSubviews {
	%orig;
	MPLockScreenRaise();
}
%end

// Контент локскрина появляется в СВОЁМ окне (выше главного) — из его вьюхи
// узнаём само окно и садим наш локскрин туда же, поверх нативного
%hook SBAwayView
- (void)didMoveToWindow {
	%orig;
	MPLockScreenAttach(self.window);
}

// iOS при пробуждении показывает нативный локскрин позже нашей синхронизации —
// и он оказывался выше подложки, просвечивая под нашей вьюхой при свайпе.
// Пока наш экран накрывает окно, гасим показ обратно (рекурсии нет: повторный
// вход в хук идёт с аргументом YES и до гасилки не доходит)
- (void)setHidden:(BOOL)hidden {
	%orig;
	if (!hidden && MPLockScreenCoversNative()) self.hidden = YES;
}
%end

// Окно локскрина: всё, что iOS добавляет или переставляет в нём при пробуждении,
// немедленно отрабатывается Raise — тот возвращает нашу вьюху наверх и гасит
// нативный контент. Другие SBAlertWindow (алармы, батарея) не задеваем: Raise
// работает только с окном, в котором реально сидит наша вьюха
%hook SBAlertWindow
- (void)didAddSubview:(UIView *)subview {
	%orig;
	MPLockScreenRaise();
}

- (void)layoutSubviews {
	%orig;
	MPLockScreenRaise();
}
%end

// Убираем «полку» дока
%hook SBDockIconListView
+ (UIImage *)backgroundImageForOrientation:(int)orientation {
	UIImage *orig = %orig;
	MPLogOnce(@"dock-bg", @"док: фон %@ (отключён=%d)", orig ? NSStringFromCGSize(orig.size) : @"nil", MPWallOn());
	if (MPWallOn()) return nil;
	return orig;
}
%end

%end // MPSpringBoard

#pragma mark - Metro-лаунчер (интеграция, код из PROMPT-OSNOVA.md раздел 6.2)

#import "MetroLauncher/MPAppDataSource.h"
#import "MetroLauncher/MPHomeController.h"
#import "MetroLauncher/MPMultitaskView.h"

static MPHomeController *MPLauncher = nil;
static void MPEnsureLauncher(void); // ленивое создание лаунчера (реализация ниже)

#pragma mark - Свитчер многозадачности (WP8.1)

// Свой свитчер: двойное нажатие Home вместо родной панели многозадачности.
static MPMultitaskView *MPMultitask = nil;

static BOOL MPTaskSwitcherOn(void) { return MPOn() && MPFlag(MPKeyMultitask, YES); }

// Запущенные приложения iOS 6.1. Селектора runningApplications у
// SBApplicationController на этой прошивке НЕТ (сверено с бинарником
// SpringBoard): есть allApplications (все установленные) и флаг isRunning
// у SBApplication. Порядок «недавние первыми» берём из модели родного
// бара многозадачности SBAppSwitcherModel (identifiers, недавние в начале).
static NSArray *MPRunningAppIDs(void) {
    NSMutableArray *ids = [NSMutableArray array];
    @try {
        Class cls = objc_getClass("SBApplicationController");
        id ctrl = (cls != nil && [cls respondsToSelector:@selector(sharedInstance)]) ? [cls sharedInstance] : nil;
        NSArray *all = (ctrl != nil && [ctrl respondsToSelector:@selector(allApplications)])
            ? [ctrl allApplications] : nil;
        if (all == nil) {
            MPLogOnce(@"mt-no-allapps", @"!! SBApplicationController.allApplications недоступен — список пуст");
            return ids;
        }

        NSMutableSet *running = [NSMutableSet set];
        for (id app in all) {
            BOOL isRunning = ([app respondsToSelector:@selector(isRunning)]) ? [app isRunning] : NO;
            if (!isRunning) continue;
            NSString *bid = [app respondsToSelector:@selector(displayIdentifier)] ? [app displayIdentifier] : nil;
            if ([bid isKindOfClass:[NSString class]] && bid.length > 0) [running addObject:bid];
        }
        if (running.count == 0) {
            MPLog(@"многозадачность: запущенных нет (установленных %lu)", (unsigned long)all.count);
            return ids;
        }

        // недавние — из модели родного свитчера; пропускаем нестроковые значения
        Class swCls = objc_getClass("SBAppSwitcherModel");
        id swModel = (swCls != nil && [swCls respondsToSelector:@selector(sharedInstance)]) ? [swCls sharedInstance] : nil;
        NSArray *recentIds = (swModel != nil && [swModel respondsToSelector:@selector(identifiers)])
            ? [swModel identifiers] : nil;
        if (recentIds != nil) {
            for (NSString *bid in recentIds)
                if ([bid isKindOfClass:[NSString class]] && [running containsObject:bid] && ![ids containsObject:bid])
                    [ids addObject:bid];
        }
        // только что запущенные могли ещё не попасть в недавние — дописываем в конец
        for (NSString *bid in running)
            if (![ids containsObject:bid]) [ids addObject:bid];

        MPLog(@"многозадачность: запущенных %lu — %@", (unsigned long)ids.count, ids);
    } @catch (NSException *e) {
        MPLog(@"!! список запущенных: %@ (%@)", e.name, e.reason);
    }
    return ids;
}

// Закрытие приложения: SIGKILL процессу. SpringBoard сам замечает смерть
// процесса и вычищает своё состояние — так же, как при обычном падении приложения.
// pid у SBApplication на iOS 6.1 — свойства _pid/pid (сверено с бинарником).
static void MPKillAppWithBundleID(NSString *bid) {
    @try {
        Class cls = objc_getClass("SBApplicationController");
        id ctrl = (cls != nil && [cls respondsToSelector:@selector(sharedInstance)]) ? [cls sharedInstance] : nil;
        NSArray *all = (ctrl != nil && [ctrl respondsToSelector:@selector(allApplications)])
            ? [ctrl allApplications] : nil;
        for (id app in all) {
            NSString *other = [app respondsToSelector:@selector(displayIdentifier)] ? [app displayIdentifier] : nil;
            if (![other isEqualToString:bid]) continue;
            BOOL isRunning = ([app respondsToSelector:@selector(isRunning)]) ? [app isRunning] : NO;
            pid_t pid = -1;
            if ([app respondsToSelector:@selector(_pid)]) pid = [app _pid];
            else if ([app respondsToSelector:@selector(pid)]) pid = [app pid];
            if (isRunning && pid > 0) {
                kill(pid, SIGKILL);
                MPLog(@"многозадачность: приложение закрыто %@ (pid %d)", bid, pid);
            } else {
                MPLog(@"многозадачность: %@ не запущено (isRunning=%d, pid=%d) — закрывать нечего",
                      bid, isRunning, pid);
            }
            return;
        }
        MPLog(@"!! многозадачность: %@ не найдено среди установленных", bid);
    } @catch (NSException *e) {
        MPLog(@"!! закрытие %@: %@ (%@)", bid, e.name, e.reason);
    }
}

// Живой снимок приложения: SpringBoard сам умеет снимать содержимое запущенного
// приложения (этим механизмом iOS 6.1 показывает «предыдущее приложение» при
// свайпе от края). Нужен для карточек без кэшированного снимка — прежде всего
// для приложения на переднем плане. Селекторы сверены с бинарником 6.1.3.
static UIImage *MPLiveAppSnapshot(NSString *bid) {
    UIImage *result = nil;
    @try {
        Class ctrlCls = objc_getClass("SBApplicationController");
        id appCtrl = (ctrlCls != nil && [ctrlCls respondsToSelector:@selector(sharedInstance)]) ? [ctrlCls sharedInstance] : nil;
        id app = (appCtrl != nil && [appCtrl respondsToSelector:@selector(applicationWithDisplayIdentifier:)])
            ? [appCtrl applicationWithDisplayIdentifier:bid] : nil;
        if (app == nil) return nil;

        Class uiCls = objc_getClass("SBUIController");
        id ui = (uiCls != nil && [uiCls respondsToSelector:@selector(sharedInstance)]) ? [uiCls sharedInstance] : nil;
        if (ui == nil || ![ui respondsToSelector:@selector(systemGestureSnapshotForApp:includeStatusBar:decodeImage:)])
            return nil;

        id img = [ui systemGestureSnapshotForApp:app includeStatusBar:YES decodeImage:YES];
        if ([img isKindOfClass:[UIImage class]]) result = img;
        MPLog(@"многозадачность: живой снимок %@ → %@", bid, result != nil ? @"ок" : @"пусто");
    } @catch (NSException *e) {
        MPLog(@"!! живой снимок %@: %@ (%@)", bid, e.name, e.reason);
    }
    return result;
}

// Показ свитчера: ленивое создание. Главное окно к этому моменту уже захвачено
// хуком SBWallpaperView (см. MPSetHostWindow) — телефон давно разблокировался.
static void MPShowMultitask(void) {
    @try {
        if (MPMultitask == nil) {
            MPMultitask = [[MPMultitaskView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            MPMultitask.onActivateBlock = ^(NSString *bid) {
                [[MPAppDataSource sharedDataSource] launchAppWithBundleID:bid];
            };
            MPMultitask.onCloseBlock = ^(NSString *bid) {
                MPKillAppWithBundleID(bid);
            };
            MPMultitask.livePreviewBlock = ^(NSString *bid) {
                return MPLiveAppSnapshot(bid);
            };
            MPLog(@"свитчер многозадачности создан");
        }
        if (MPMultitask.superview == nil) {
            UIView *host = MPSharedHostWindow();
            if (host == nil) {
                MPLog(@"!! свитчер: главное окно не захвачено — открыть нельзя");
                return;
            }
            [host addSubview:MPMultitask];
            MPLog(@"свитчер установлен в %@", NSStringFromClass([host class]));
        }
        [MPMultitask.superview bringSubviewToFront:MPMultitask];
        [MPMultitask openAnimated:YES withAppIDs:MPRunningAppIDs()];
    } @catch (NSException *e) {
        MPLog(@"!! показ свитчера: %@ (%@)", e.name, e.reason);
    }
}

@interface SBAwayController : NSObject
+ (id)sharedAwayController;
- (BOOL)isLocked;
@end

static void MPLockStateChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // наблюдатель регистрируется во всех UIKit-процессах, живём только в SpringBoard
    if (objc_getClass("SBIconView") == nil) return;
    MPLockScreenSync(); // сам уйдёт на главный поток
    dispatch_async(dispatch_get_main_queue(), ^{
        // свитчер на заблокированном экране не нужен
        if (MPMultitask != nil && [MPMultitask isOpen]) [MPMultitask closeAnimated:NO];
        MPEnsureLauncher();
        BOOL locked = [[objc_getClass("SBAwayController") sharedAwayController] isLocked];
        if (locked) [MPLauncher hideMetroAnimated:NO];
        else [MPLauncher showMetroAnimated:NO];
    });
}

// Смена акцента на странице «Цвета» (Настройки): перечитать настройки и
// мгновенно перекрасить плитки, список и кнопку «M»
static void MPAccentChangedSB(CFNotificationCenterRef center, void *observer,
                              CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (objc_getClass("SBIconView") == nil) return;    // только SpringBoard
    dispatch_async(dispatch_get_main_queue(), ^{
        [MPMetroStyle reloadPreferences];
        if (MPLauncher != nil) [MPLauncher applyStyleToPages];
    });
}

// Включение/выключение экрана (кнопка Power, автосон): покрывает пробуждение
// при блокировке и возврат к локскрину после отмены ввода кода — в обоих
// случаях lockstate не меняется, а локскрин должен вернуться
static void MPDisplayStatusChanged(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (objc_getClass("SBIconView") == nil) return;
    MPLockScreenSync();
}

// Ленивое создание лаунчера (только главный поток). Класс SpringBoard на iOS 6.1
// не реализует applicationDidFinishLaunching:, поэтому хукить запуск бессмысленно —
// создаём через 60 с после старта (вотчдог-окно позади) и при смене блокировки.
static void MPEnsureLauncher(void) {
	if (MPLauncher != nil) return;
	MPLauncher = [[MPHomeController alloc] init];
	[MPLauncher installLauncherView];

	id away = [objc_getClass("SBAwayController") sharedAwayController];
	BOOL locked = (away != nil && [away respondsToSelector:@selector(isLocked)]) ? [away isLocked] : YES;
	if (!locked) [MPLauncher showMetroAnimated:NO];
}

// Кнопка Home: выход из режима редактирования плиток (как «назад» в WP8)
// и свой свитчер многозадачности по двойному нажатию. «Проглоченные» свитчером
// нажатия не отдаём SpringBoard (парой down/up), иначе под нашей вьюхой
// откроется родная панель многозадачности и повиснет после закрытия свитчера.
struct __GSEvent;

static NSTimeInterval MPLastMenuDownAt = 0;
static BOOL MPConsumeNextMenuUp = NO;

%group MPLauncherHooks

%hook SpringBoard
- (void)menuButtonDown:(struct __GSEvent *)event {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();

    // 1) Свитчер открыт: Home закрывает его
    if (MPMultitask != nil && [MPMultitask isOpen]) {
        MPLastMenuDownAt = 0;          // следующее нажатие — новое, не «второе»
        MPConsumeNextMenuUp = YES;
        MPLog(@"Home: закрытие свитчера");
        [MPMultitask closeAnimated:YES];
        return;
    }

    // 2) Двойное нажатие — свой свитчер WP8.1 вместо родной панели
    if (MPTaskSwitcherOn() && MPLastMenuDownAt > 0 && now - MPLastMenuDownAt < 0.45) {
        id away = [objc_getClass("SBAwayController") sharedAwayController];
        BOOL locked = (away != nil && [away respondsToSelector:@selector(isLocked)]) ? [away isLocked] : NO;
        if (!locked) {
            MPLastMenuDownAt = 0;
            MPConsumeNextMenuUp = YES; // второй up поглощается вместе с down
            MPLog(@"Home: двойное нажатие → свитчер WP");
            MPShowMultitask();
            return;
        }
    }

    MPLastMenuDownAt = now;

    // 3) Обычное нажатие: выход из режима правки плиток
    %orig;
    if (MPLauncher != nil && [MPLauncher isMetroVisible]) {
        [MPLauncher homeButtonPressed];
        MPLog(@"Home: выход из режима правки");
    }
}

- (void)menuButtonUp:(struct __GSEvent *)event {
    if (MPConsumeNextMenuUp) {
        MPConsumeNextMenuUp = NO;
        MPLog(@"Home: up поглощён (нажатие досталось свитчеру)");
        return;
    }
    %orig;
}
%end

// Бейджи: уведомляем лаунчер

%hook SBIcon
- (void)noteBadgeDidChange {
	%orig;
	[[NSNotificationCenter defaultCenter] postNotificationName:MPAppsChangedNotification object:nil];
}
%end

%end // MPLauncherHooks

// Нативный ввод код-пароля живёт в SBAwayView поверх нашей вьюхи: на время его
// показа локскрин прячем, после закрытия (отмена кода, «домой» без ввода) —
// возвращаем через sync, если устройство всё ещё заблокировано
%group MPLockScreenHooks

%hook SBPasscodeViewController
- (void)viewWillAppear:(BOOL)animated {
	%orig;
	MPLockScreenPasscodeUI(YES);
}

- (void)viewWillDisappear:(BOOL)animated {
	%orig;
	MPLockScreenPasscodeUI(NO);
}
%end

%end // MPLockScreenHooks

#pragma mark - Отладочный снимок экрана

// Инструмент разработки: в обычной работе молчит (один открытый fd + vnode-источник).
// Из SSH:
//   echo x >> /var/mobile/Library/Caches/metrophone/shot.request
// SpringBoard рендерит верхнее окно (локскрин или рабочий стол) в shot.png рядом.
// renderInContext рисует слой-дерево и не требует включённого экрана — поэтому
// снимать можно и залоченный телефон.
#define MP_SHOT_DIR     @"/var/mobile/Library/Caches/metrophone"
#define MP_SHOT_REQUEST "/var/mobile/Library/Caches/metrophone/shot.request"

static void MPDebugDump(void);   // объявление: команда ниже ссылается на дамп
static void MPDebugDumpSpecs(void);

// Первая UITableView в дереве окна (для просмотра «Настроек»)
static UITableView *MPDebugFindTable(UIView *root) {
	NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count > 0) {
		UIView *v = [stack lastObject];
		[stack removeLastObject];
		if ([v isKindOfClass:[UITableView class]]) return (UITableView *)v;
		[stack addObjectsFromArray:v.subviews];
	}
	return nil;
}

static UINavigationController *MPDebugFindNavViaBar(UIView *root);

// Сброс всех навигационных стеков в дереве окна (для команды root).
static NSUInteger MPDebugPopAllNavs(UIView *root) {
	NSUInteger n = 0;
	NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count > 0) {
		id v = [stack lastObject];
		[stack removeLastObject];
		if ([v isKindOfClass:[UINavigationController class]]) {
			[(UINavigationController *)v popToRootViewControllerAnimated:NO];
			n++;
		}
		if ([v isKindOfClass:[UIViewController class]]) {
			UIViewController *vc = (UIViewController *)v;
			if (vc.presentedViewController != nil) {
				[vc dismissViewControllerAnimated:NO completion:nil];
				[stack addObject:vc.presentedViewController];
			}
			[stack addObjectsFromArray:vc.childViewControllers];
			if ([vc isViewLoaded]) [stack addObject:vc.view];
		}
		if ([v isKindOfClass:[UIView class]]) {
			[stack addObjectsFromArray:[(UIView *)v subviews]];
		}
	}
	return n;
}

// Таблица ТЕКУЩЕЙ страницы. Искать по всему окну нельзя: во время push/pop
// в иерархии живут таблицы соседних контроллеров, и тап уходил в чужой список
// (снимок «Статистики» оказывался страницей Bluetooth-устройства).
static UITableView *MPDebugActiveTable(void) {
	UIWindow *w = [UIApplication sharedApplication].keyWindow;
	UINavigationController *nav = MPDebugFindNavViaBar(w);
	UIViewController *top = nav.topViewController ?: nav;
	UITableView *t = (top != nil) ? MPDebugFindTable(top.view) : nil;
	if (t != nil) return t;
	return MPDebugFindTable(w);
}

// Навигационный контроллер в дереве «Настроек»: корнем может быть не UINavigationController
static UINavigationController *MPDebugFindNav(UIViewController *root) {
	if (root == nil) return nil;
	if ([root isKindOfClass:[UINavigationController class]]) return (UINavigationController *)root;
	if (root.presentedViewController != nil) {
		UINavigationController *n = MPDebugFindNav(root.presentedViewController);
		if (n != nil) return n;
	}
	for (UIViewController *c in root.childViewControllers) {
		UINavigationController *n = MPDebugFindNav(c);
		if (n != nil) return n;
	}
	return nil;
}

// У «Настроек» iOS 6 у окна нет rootViewController — достаём навигацию из делегата бара
static UINavigationController *MPDebugFindNavViaBar(UIView *root) {
	if (root == nil) return nil;
	NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count > 0) {
		UIView *v = [stack lastObject];
		[stack removeLastObject];
		if ([v isKindOfClass:[UINavigationBar class]]) {
			id d = [(UINavigationBar *)v delegate];
			if ([d isKindOfClass:[UINavigationController class]]) return (UINavigationController *)d;
		}
		[stack addObjectsFromArray:v.subviews];
	}
	return nil;
}

// Первый UIControl заданного класса в дереве (свитч/слайдер в ячейке)
static UIControl *MPDebugFindControlIn(UIView *root, Class cls) {
	if (root == nil) return nil;
	if ([root isKindOfClass:cls]) return (UIControl *)root;
	for (UIView *s in root.subviews) {
		UIControl *r = MPDebugFindControlIn(s, cls);
		if (r != nil) return r;
	}
	return nil;
}

// object_isClass — API iOS 8; в libobjc iOS 6.1.3 его нет, и первый же вызов
// роняет процесс через dyld («Symbol not found: _object_isClass»), @try не спасает.
// Эквивалент, доступный с iOS 2: у объекта-класса object_getClass даёт метакласс.
static BOOL MPIsClassObject(id v) {
	return (v != nil) && class_isMetaClass(object_getClass(v));
}

static dispatch_source_t MPDebugShotSource = nil;   // vnode-источник канала снимков (держим статикой)

// Инициализатор PS-контроллеров (объявлен в PSViewController.h, класс берём как id)
@interface UIViewController (MPPSDebugInit)
- (id)initForContentSize:(CGSize)size;
@end

// Открыть строку по плоскому индексу specifier'а (iOS 6): detail-класс или
// principal class бандла → initForContentSize: + specifier → pushController:.
// PS не использует tableView:didSelectRowAtIndexPath: (проверено), поэтому
// переход честно повторяет внутренний механизм PS. YES — переход состоялся.
static BOOL MPPushSpecifierByIndex(id ds, NSInteger flat) {
	if (ds == nil || flat < 0 || ![ds respondsToSelector:@selector(specifierAtIndex:)]) return NO;
	id (*sendSpec)(id, SEL, long) = (id (*)(id, SEL, long))objc_msgSend;
	id (*sendProp)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
	SEL propSel = NSSelectorFromString(@"propertyForKey:");
	id spec = sendSpec(ds, @selector(specifierAtIndex:), flat);
	if (spec == nil) return NO;

	// 1) Штатная фабрика PS знает про bundle/detail больше, чем ручная сборка;
	//    без неё страницы-плагины (USAGE, NOTES, WALLPAPER…) открываются пустыми.
	id made = nil;
	NSString *usedSel = nil;
	for (NSString *selName in @[@"controllerForSpecifier:", @"detailControllerForSpecifier:",
	                              @"makeControllerForSpecifier:"]) {
		SEL s = NSSelectorFromString(selName);
		if (![ds respondsToSelector:s]) continue;
		id (*sendCtl)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
		@try { made = sendCtl(ds, s, spec); } @catch (NSException *e) { made = nil; }
		if (made != nil) { usedSel = selName; break; }
	}
	if (made != nil && [made isKindOfClass:[UIViewController class]]) {
		MPLog(@"отладка: push %@ через %@", NSStringFromClass([made class]), usedSel);
		void (*sendPush)(id, SEL, id, BOOL) = (void (*)(id, SEL, id, BOOL))objc_msgSend;
		sendPush(ds, @selector(pushController:animate:), made, YES);
		return YES;
	}

	Class cls = nil;
	NSString *detailName = nil, *bundleName = nil;
	if ([spec respondsToSelector:@selector(detailControllerClass)]) {
		id (*sendCls)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
		id c = sendCls(spec, @selector(detailControllerClass));
		if (MPIsClassObject(c)) cls = (Class)c;
	}
	if (cls == nil && [spec respondsToSelector:propSel]) {
		id d = sendProp(spec, propSel, @"detail");
		if ([d isKindOfClass:[NSString class]]) detailName = d;
		else if (MPIsClassObject(d)) cls = (Class)d;
		id b = sendProp(spec, propSel, @"bundle");
		if ([b isKindOfClass:[NSString class]]) bundleName = b;
	}
	NSBundle *loaded = nil;
	if (bundleName.length > 0) {
		NSArray *candidates = @[
			[NSString stringWithFormat:@"/System/Library/PreferenceBundles/%@.bundle", bundleName],
			[NSString stringWithFormat:@"/Library/PreferenceBundles/%@.bundle", bundleName],
			[NSString stringWithFormat:@"/Applications/Preferences.app/%@.bundle", bundleName],
		];
		for (NSString *p in candidates) {
			NSBundle *bndl = [NSBundle bundleWithPath:p];
			if (bndl != nil && [bndl load]) { loaded = bndl; break; }
		}
	}
	if (cls == nil && detailName.length > 0) {
		cls = NSClassFromString(detailName);
		if (cls == Nil && loaded != nil) cls = NSClassFromString(detailName);
	}
	if (cls == nil && loaded != nil) {
		cls = [loaded principalClass];      // строка без detail: страница — principal
	}
	if (cls == Nil) return NO;

	UIViewController *vc = [[cls alloc] initForContentSize:CGSizeMake(320.0f, 480.0f)];
	if ([vc respondsToSelector:@selector(setSpecifier:)]) {
		id (*s2)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
		s2(vc, @selector(setSpecifier:), spec);
	}
	if (loaded != nil && [vc respondsToSelector:@selector(setBundle:)]) {
		id (*s3)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
		s3(vc, @selector(setBundle:), loaded);
	}
	// Часть контроллеров (Заметки, Напоминания, Twitter…) строит содержимое
	// только когда знает родителя: без parent/root они открываются пустой
	// полосатой страницей.
	if ([vc respondsToSelector:@selector(setParentController:)]) {
		id (*s4)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
		s4(vc, @selector(setParentController:), ds);
	}
	if ([vc respondsToSelector:@selector(setRootController:)]) {
		id root = nil;
		if ([ds respondsToSelector:@selector(rootController)]) {
			id (*getRoot)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
			root = getRoot(ds, @selector(rootController));
		}
		if (root == nil && [ds respondsToSelector:@selector(navigationController)]) {
			id (*getNav)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
			root = getNav(ds, @selector(navigationController));
		}
		if (root != nil) {
			id (*s5)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
			s5(vc, @selector(setRootController:), root);
		}
	}
	void (*sendPush)(id, SEL, id, BOOL) = (void (*)(id, SEL, id, BOOL))objc_msgSend;
	MPLog(@"отладка: push %@ (ручная сборка)", NSStringFromClass([vc class]));
	sendPush(ds, @selector(pushController:animate:), vc, YES);
	return YES;
}

// Команда из файла запроса: "shot" (только снимок), "metro", "ios", "page0"/"page1".
// После действия снимок делается сам — одна команда = один кадр.
static void MPDebugRunCommand(NSString *cmd) {
	// url <строка> — открыть ссылку (например, prefs:root=MetroPhone, чтобы
	// попасть в наш раздел настроек без ручных тапов)
	if (cmd.length > 4 &&
	    [cmd compare:@"url " options:NSCaseInsensitiveSearch range:NSMakeRange(0, 4)] == NSOrderedSame) {
		NSString *url = [[cmd substringFromIndex:4] stringByTrimmingCharactersInSet:
		                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		MPLog(@"отладка: открываю %@", url);
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
		return;
	}
	if ([cmd caseInsensitiveCompare:@"dump"] == NSOrderedSame) {
		MPDebugDump();
		return;
	}
	if ([cmd caseInsensitiveCompare:@"specs"] == NSOrderedSame) {
		MPDebugDumpSpecs();
		return;
	}
	// scroll <0..1> — промотать список «Настроек» к доле высоты (для снимков)
	if (cmd.length > 7 && [cmd compare:@"scroll " options:NSCaseInsensitiveSearch
	                              range:NSMakeRange(0, 7)] == NSOrderedSame) {
		CGFloat f = [[cmd substringFromIndex:7] floatValue];
		UITableView *t = MPDebugActiveTable();
		if (t != nil) {
			CGFloat maxY = MAX(0.0f, t.contentSize.height - t.bounds.size.height);
			[t setContentOffset:CGPointMake(0.0f, maxY * f) animated:NO];
			MPLog(@"отладка: прокрутка %.2f (из %.0f)", f, maxY);
		}
		return;
	}
	// tabpreview — отрисовать сегментные вкладки в PNG (инструмент разработки)
	if ([cmd caseInsensitiveCompare:@"tabpreview"] == NSOrderedSame) {
		extern void MPPreviewSegmentTabs(void);
		MPPreviewSegmentTabs();
		return;
	}
	// select <секция>:<строка> — всегда через didSelect делегата, даже на
	// PS-таблицах: строки без detail (конфигурации VPN) иначе не открыть
	if (cmd.length > 7 && [cmd compare:@"select " options:NSCaseInsensitiveSearch
	                           range:NSMakeRange(0, 7)] == NSOrderedSame) {
		NSArray *parts = [[cmd substringFromIndex:7] componentsSeparatedByString:@":"];
		UITableView *t = MPDebugActiveTable();
		if (t != nil && parts.count == 2) {
			NSInteger sec = [(NSString *)parts[0] intValue];
			NSInteger row = [(NSString *)parts[1] intValue];
			id del = t.delegate;
			SEL sel = @selector(tableView:didSelectRowAtIndexPath:);
			if ([del respondsToSelector:sel] && row >= 0 && row < [t numberOfRowsInSection:sec]) {
				NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:sec];
				[t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
				void (*send)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
				send(del, sel, t, ip);
				MPLog(@"отладка: select %ld:%ld → didSelect", (long)sec, (long)row);
			}
		}
		return;
	}
	// tap row <секция>:<строка> — открыть строку текущей таблицы «Настроек»
	// (indexPath → плоский индекс specifier'а → pushController:)
	if (cmd.length > 8 &&
	    [cmd compare:@"tap row " options:NSCaseInsensitiveSearch range:NSMakeRange(0, 8)] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;      // в SpringBoard тапов нет
		NSArray *parts = [[cmd substringFromIndex:8] componentsSeparatedByString:@":"];
		UITableView *t = MPDebugActiveTable();
		id ds = t.dataSource;
		Class psVCClass = objc_getClass("PSViewController");
		BOOL isPS = (t != nil && ds != nil && psVCClass != Nil && [ds isKindOfClass:psVCClass]);
		if (t != nil && parts.count == 2 && !isPS) {
			// Обычная таблица («Профили», «Spotlight»): честный didSelect у делегата.
			NSInteger sec = [(NSString *)parts[0] intValue];
			NSInteger row = [(NSString *)parts[1] intValue];
			id del = t.delegate;
			SEL sel = @selector(tableView:didSelectRowAtIndexPath:);
			if ([del respondsToSelector:sel] && row >= 0 && row < [t numberOfRowsInSection:sec]) {
				NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:sec];
				[t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
				void (*send)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
				send(del, sel, t, ip);
				MPLog(@"отладка: tap %ld:%ld → didSelect", (long)sec, (long)row);
			}
			return;
		}
		if (isPS) {
			NSInteger sec = [(NSString *)parts[0] intValue];
			NSInteger row = [(NSString *)parts[1] intValue];
			if (row >= 0 && row < [t numberOfRowsInSection:sec]) {
				NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:sec];
				[t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
				NSInteger flat = -1;
				if ([ds respondsToSelector:@selector(indexForIndexPath:)]) {
					NSInteger (*sendIdx)(id, SEL, id) = (NSInteger (*)(id, SEL, id))objc_msgSend;
					flat = sendIdx(ds, @selector(indexForIndexPath:), ip);
				}
				BOOL ok = MPPushSpecifierByIndex(ds, flat);
				if (ok) {
					MPLog(@"отладка: tap %ld:%ld → push", (long)sec, (long)row);
				} else {
					MPLog(@"отладка: tap %ld:%ld — нет detail (кнопка/тумблер/действие)", (long)sec, (long)row);
				}
			} else {
				MPLog(@"отладка: tap %ld:%ld — строки нет (секций %lu)", (long)sec, (long)row,
				      (unsigned long)t.numberOfSections);
			}
		} else {
			MPLog(@"отладка: tap пропущен (таблица=%@ ds=%@ parts=%lu)",
			      t != nil ? @"есть" : @"нет", ds != nil ? NSStringFromClass([ds class]) : @"нет",
			      (unsigned long)parts.count);
		}
		return;
	}
	// search [on|off] — включить/выключить режим поиска у текущего контроллера
	if (cmd.length >= 6 &&
	    [cmd compare:@"search" options:NSCaseInsensitiveSearch range:NSMakeRange(0, 6)] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		BOOL on = (cmd.length < 8 || [cmd rangeOfString:@"off"].location == NSNotFound);
		UIWindow *w = [UIApplication sharedApplication].keyWindow;
		UINavigationController *nav = MPDebugFindNavViaBar(w);
		UIViewController *vc = nav.topViewController;
		SEL sel = NSSelectorFromString(@"setSearching:");
		if (vc != nil && [vc respondsToSelector:sel]) {
			void (*send)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
			send(vc, sel, on);
			MPLog(@"отладка: search %d → %@", (int)on, NSStringFromClass([vc class]));
		} else {
			MPLog(@"отладка: search — метода нет (vc=%@)", vc ? NSStringFromClass([vc class]) : @"nil");
		}
		return;
	}
	// sshot — снимок ЭКРАНА целиком (все окна, как Power+Home)
	if ([cmd caseInsensitiveCompare:@"sshot"] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		extern CGImageRef UICreateScreenImage(void);
		CGImageRef cg = NULL;
		// символ приватный и не в стабах SDK — берём через dlsym
		typedef CGImageRef (*MPScreenFn)(void);
		MPScreenFn fn = (MPScreenFn)dlsym(RTLD_DEFAULT, "UICreateScreenImage");
		if (fn != NULL) cg = fn();
		if (cg == NULL) { MPLog(@"отладка: sshot — пусто"); return; }
		UIImage *img = [UIImage imageWithCGImage:cg];
		CGImageRelease(cg);
		NSString *path = [MP_SHOT_DIR stringByAppendingPathComponent:@"screen.png"];
		BOOL ok = [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
		MPLog(@"отладка: sshot %@ → %@", NSStringFromCGSize(img.size), ok ? @"ок" : @"НЕ записан");
		return;
	}
	// wins — список окон с уровнями (диагностика перекрытий)
	if ([cmd caseInsensitiveCompare:@"wins"] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		for (UIWindow *w in [UIApplication sharedApplication].windows) {
			MPLog(@"[wins] %@ level=%.0f hidden=%d frame=%@", NSStringFromClass([w class]),
			      w.windowLevel, (int)w.hidden, NSStringFromCGRect(w.frame));
		}
		return;
	}
	// hit <x> <y> — что получит тап в этой точке (проверка перекрытий)
	if (cmd.length > 4 &&
	    [cmd compare:@"hit " options:NSCaseInsensitiveSearch range:NSMakeRange(0, 4)] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		NSArray *parts = [[cmd substringFromIndex:4] componentsSeparatedByString:@" "];
		CGFloat x = parts.count > 0 ? [[parts objectAtIndex:0] floatValue] : 0.0f;
		CGFloat y = parts.count > 1 ? [[parts objectAtIndex:1] floatValue] : 0.0f;
		UIWindow *w = [UIApplication sharedApplication].keyWindow;
		UIView *hit = [w hitTest:CGPointMake(x, y) withEvent:nil];
		NSMutableString *chain = [NSMutableString string];
		NSArray *allWindows = [UIApplication sharedApplication].windows;
		for (UIWindow *win in [allWindows reverseObjectEnumerator]) {
			UIView *h = [win hitTest:CGPointMake(x, y) withEvent:nil];
			if (h != nil && h != (UIView *)win) {
				hit = h;
				[chain appendFormat:@"[level %.0f] ", win.windowLevel];
				break;
			}
		}
		for (UIView *v = hit; v != nil && chain.length < 180; v = v.superview) {
			[chain appendFormat:@"%@ < ", NSStringFromClass([v class])];
		}
		MPLog(@"отладка: hit %.0f,%.0f → %@", x, y, chain);
		return;
	}
	// focus — поставить курсор в первое поле поиска (проверка страниц с клавиатурой)
	if ([cmd caseInsensitiveCompare:@"focus"] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		UIWindow *w = [UIApplication sharedApplication].keyWindow;
		NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
		UITextField *field = nil;
		while (stack.count > 0) {
			UIView *v = [stack lastObject];
			[stack removeLastObject];
			if ([v isKindOfClass:[UITextField class]]) { field = (UITextField *)v; break; }
			[stack addObjectsFromArray:v.subviews];
		}
		if (field != nil) {
			[field becomeFirstResponder];
			MPLog(@"отладка: focus → %@", NSStringFromClass([field class]));
		} else {
			MPLog(@"отладка: focus — поля нет");
		}
		return;
	}
	// back — тап по шапке страницы: выход назад на страницах вне PS
	// (Spotlight, «Профили», сертификат), где нет навбара с кнопкой
	if ([cmd caseInsensitiveCompare:@"back"] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		UITableView *t = MPDebugActiveTable();
		UIView *h = (t != nil) ? t.tableHeaderView : nil;
		if (h == nil) {
			// панели поиска держат шапку в отдельном окне
			for (UIWindow *win in [UIApplication sharedApplication].windows) {
				NSMutableArray *stack = [NSMutableArray arrayWithObject:win];
				while (stack.count > 0 && h == nil) {
					UIView *v = [stack lastObject];
					[stack removeLastObject];
					if ([v isKindOfClass:NSClassFromString(@"MPSettingsHeaderView")]) { h = v; break; }
					[stack addObjectsFromArray:v.subviews];
				}
			}
		}
		SEL tapSel = NSSelectorFromString(@"headerTapped");
		if (h != nil && [h respondsToSelector:tapSel]) {
			void (*send)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
			send(h, tapSel);
			MPLog(@"отладка: back — тап по шапке");
		} else {
			MPLog(@"отладка: back — шапки нет");
		}
		return;
	}
	// root — гарантированный возврат в корень «Настроек» (проверка для краулера)
	if ([cmd caseInsensitiveCompare:@"root"] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		UIWindow *w = [UIApplication sharedApplication].keyWindow;
		// Навигация «Настроек» живёт ВНЕ дерева вьюх, поэтому pop делаем через
		// контроллер бара, а обход дерева — как добивку для вложенных стеков.
		UINavigationController *nav = MPDebugFindNavViaBar(w);
		if (nav != nil) [nav popToRootViewControllerAnimated:NO];
		NSUInteger stacks = MPDebugPopAllNavs(w.rootViewController != nil ? (id)w.rootViewController : (id)w);
		MPLog(@"отладка: root — nav=%@, стеков в дереве: %lu",
		      nav != nil ? NSStringFromClass([nav class]) : @"nil", (unsigned long)stacks);
		return;
	}
	// back — назад по стеку «Настроек» (или закрыть модальную страницу)
	if ([cmd caseInsensitiveCompare:@"back"] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;      // в SpringBoard навигации нет
		UIWindow *w = [UIApplication sharedApplication].keyWindow;
		UINavigationController *nav = MPDebugFindNavViaBar(w);
		MPLog(@"отладка: back — nav=%@ стек=%lu", nav != nil ? NSStringFromClass([nav class]) : @"nil",
		      nav != nil ? (unsigned long)nav.viewControllers.count : 0);
		if (nav != nil && nav.viewControllers.count > 1) {
			unsigned long before = (unsigned long)nav.viewControllers.count;
			[nav popViewControllerAnimated:NO];
			MPLog(@"отладка: back (pop, стек %lu → %lu)", before, (unsigned long)nav.viewControllers.count);
		} else if (w != nil && w.rootViewController.presentedViewController != nil) {
			[w.rootViewController dismissViewControllerAnimated:NO completion:nil];
			MPLog(@"отладка: back (dismiss)");
		} else {
			MPLog(@"отладка: back — некуда");
		}
		return;
	}
	// set switch <секция>:<строка> on|off — переключить тумблер строки (с PS-логикой)
	if (cmd.length > 11 &&
	    [cmd compare:@"set switch " options:NSCaseInsensitiveSearch range:NSMakeRange(0, 11)] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;      // в SpringBoard тумблеров нет
		NSArray *tokens = [[cmd substringFromIndex:11] componentsSeparatedByString:@" "];
		NSArray *sr = (tokens.count > 0) ? [tokens[0] componentsSeparatedByString:@":"] : [NSArray array];
		BOOL on = (tokens.count > 1 && [tokens[1] hasSuffix:@"on"]);
		UITableView *t = MPDebugActiveTable();
		id ds = t.dataSource;
		if (t != nil && ds != nil && sr.count == 2) {
			NSInteger sec = [(NSString *)sr[0] intValue];
			NSInteger row = [(NSString *)sr[1] intValue];
			if (row >= 0 && row < [t numberOfRowsInSection:sec]) {
				NSIndexPath *ip = [NSIndexPath indexPathForRow:row inSection:sec];
				[t scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
				__weak UITableView *weakT = t;
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
				               dispatch_get_main_queue(), ^{
					UITableView *tt = weakT;
					if (tt == nil) return;
					UISwitch *sw = (UISwitch *)MPDebugFindControlIn([tt cellForRowAtIndexPath:ip], [UISwitch class]);
					if (sw == nil) { MPLog(@"отладка: switch %ld:%ld не найден", (long)sec, (long)row); return; }
					if (sw.on != on) {
						[sw setOn:on animated:NO];
						// PS-логика слушает ValueChanged; WP-оверлей зеркалится нашим хуком
						[sw sendActionsForControlEvents:UIControlEventValueChanged];
					}
					MPLog(@"отладка: switch %ld:%ld → %@", (long)sec, (long)row, on ? @"on" : @"off");
				});
			} else {
				MPLog(@"отладка: switch %ld:%ld — строки нет", (long)sec, (long)row);
			}
		}
		return;
	}
	// set slider <0..1> — значение первого видимого слайдера таблицы
	if (cmd.length > 11 &&
	    [cmd compare:@"set slider " options:NSCaseInsensitiveSearch range:NSMakeRange(0, 11)] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;      // в SpringBoard слайдеров нет
		CGFloat f = [[cmd substringFromIndex:11] floatValue];
		f = MIN(MAX(f, 0.0f), 1.0f);
		UITableView *t = MPDebugActiveTable();
		if (t != nil) {
			UISlider *slider = nil;
			for (UITableViewCell *c in t.visibleCells) {
				slider = (UISlider *)MPDebugFindControlIn(c, [UISlider class]);
				if (slider != nil) break;
			}
			if (slider != nil) {
				slider.value = slider.minimumValue + f * (slider.maximumValue - slider.minimumValue);
				[slider sendActionsForControlEvents:UIControlEventValueChanged];
				MPLog(@"отладка: slider → %.2f (диапазон %.0f…%.0f)", slider.value,
				      slider.minimumValue, slider.maximumValue);
			} else {
				MPLog(@"отладка: слайдер на странице не найден");
			}
		}
		return;
	}
	// dismiss — закрыть алерт (краулер случайно может открыть «Другая…» и т.п.)
	if ([cmd caseInsensitiveCompare:@"dismiss"] == NSOrderedSame) {
		if (objc_getClass("SBIconView") != nil) return;
		for (UIWindow *w in [UIApplication sharedApplication].windows) {
			UIAlertView *av = (UIAlertView *)MPDebugFindControlIn(w, [UIAlertView class]);
			if (av != nil && [av isKindOfClass:[UIAlertView class]]) {
				[av dismissWithClickedButtonIndex:0 animated:NO];
				MPLog(@"отладка: алерт закрыт");
			}
		}
		return;
	}
	// rotate — попытка повернуть интерфейс (Настройки iOS 6 портретные: ожидаемо игнор)
	if ([cmd caseInsensitiveCompare:@"rotate"] == NSOrderedSame) {
		[[UIDevice currentDevice] setValue:@(UIInterfaceOrientationLandscapeRight) forKey:@"orientation"];
		MPLog(@"отладка: запрос на поворот отправлен");
		return;
	}
	// tap idx <плоский индекс> — открыть строку по specifierAtIndex: (iOS 6)
	// specs2 — дамп всех specifier'ов текущей страницы для краулера
	if (cmd.length >= 6 &&
	    ([cmd compare:@"tap idx " options:NSCaseInsensitiveSearch range:NSMakeRange(0, 8)] == NSOrderedSame ||
	     [cmd caseInsensitiveCompare:@"specs2"] == NSOrderedSame)) {
		if (objc_getClass("SBIconView") != nil) return;
		UITableView *t = MPDebugActiveTable();
		id ds = t.dataSource;
		if (t == nil || ds == nil || ![ds respondsToSelector:@selector(specifierAtIndex:)]) return;
		id (*sendSpec)(id, SEL, long) = (id (*)(id, SEL, long))objc_msgSend;
		id (*sendProp)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
		SEL propSel = NSSelectorFromString(@"propertyForKey:");

		if ([cmd caseInsensitiveCompare:@"specs2"] == NSOrderedSame) {
			// плоский список: idx | cell | label | detail | bundle
			NSMutableString *out = [NSMutableString string];
			NSInteger n = 0;
			while (YES) {
				if (![ds respondsToSelector:@selector(specifierAtIndex:)]) break;
				id spec = sendSpec(ds, @selector(specifierAtIndex:), n);
				if (spec == nil) break;
				NSString *cell = @"", *label = @"", *detail = @"", *bundle = @"";
				if ([spec respondsToSelector:propSel]) {
					id v = sendProp(spec, propSel, @"cell");
					if ([v isKindOfClass:[NSString class]]) cell = v;
					v = sendProp(spec, propSel, @"label");
					if ([v isKindOfClass:[NSString class]]) label = v;
					v = sendProp(spec, propSel, @"detail");
					if ([v isKindOfClass:[NSString class]]) detail = v;
					else if (MPIsClassObject(v)) detail = NSStringFromClass((Class)v);
					v = sendProp(spec, propSel, @"bundle");
					if ([v isKindOfClass:[NSString class]]) bundle = v;
				}
				[out appendFormat:@"%ld|%@|%@|%@|%@\n", (long)n, cell, label, detail, bundle];
				n++;
				if (n > 300) break;
			}
			NSString *path = [MP_SHOT_DIR stringByAppendingPathComponent:@"dump-specs2.txt"];
			[out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
			MPLog(@"отладка: specs2 — %ld specifier'ов", (long)n);
			return;
		}

		NSInteger flat = [[cmd substringFromIndex:8] intValue];
		BOOL ok = MPPushSpecifierByIndex(ds, flat);
		if (!ok) {
			MPLog(@"отладка: tap idx %ld — нет detail (кнопка/тумблер/действие)", (long)flat);
		} else {
			MPLog(@"отладка: tap idx %ld → push", (long)flat);
		}
		return;
	}
	// prefscheck / prefspage — работа с бандлом настроек изнутри «Настроек»:
	// открытие через prefs:root= даёт пустую таблицу (URL не передаёт бандл),
	// поэтому для просмотра поднимаем контроллер сами.
	if ([cmd caseInsensitiveCompare:@"prefscheck"] == NSOrderedSame ||
	    [cmd caseInsensitiveCompare:@"prefspage"] == NSOrderedSame) {
		NSBundle *bundle = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/MetroPhonePrefs.bundle"];
		[bundle load];
		Class cls = [bundle principalClass];
		id controller = (cls != Nil) ? [[cls alloc] init] : nil;
		// PSListController ищет Root.plist в своём bundle: без него — в бандле «Настроек».
		// PreferenceLoader выставляет его сам, при ручном создании — выставляем руками.
		if (controller != nil && [controller respondsToSelector:NSSelectorFromString(@"setBundle:")]) {
			[controller setValue:bundle forKey:@"bundle"];   // KVC: без предупреждения ARC о performSelector
		}
		NSArray *specs = [controller respondsToSelector:@selector(specifiers)]
		    ? (NSArray *)[controller valueForKey:@"specifiers"] : nil;
		MPLog(@"отладка: бандл=%@ класс=%@ specifiers=%lu",
		      bundle != nil ? @"есть" : @"нет", NSStringFromClass(cls), (unsigned long)specs.count);
		if ([cmd caseInsensitiveCompare:@"prefspage"] == NSOrderedSame && controller != nil) {
			UIViewController *rootVC = [[UIApplication sharedApplication] keyWindow].rootViewController;
			UINavigationController *nav = MPDebugFindNav(rootVC);
			MPLog(@"отладка: корень %@, навигация %@", NSStringFromClass([rootVC class]),
			      nav != nil ? @"есть" : @"нет");
			if (nav != nil) {
				[nav pushViewController:controller animated:NO];
				MPLog(@"отладка: страница настроек открыта (стек %lu)",
				      (unsigned long)nav.viewControllers.count);
			} else {
				// У «Настроек» iOS 6 у окна нет rootViewController — показываем панель
				// в своём отладочном окне поверх (только для снимка, продукт не трогаем)
				static UIWindow *debugWindow = nil;
				if (debugWindow == nil) {
					debugWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
					debugWindow.windowLevel = UIWindowLevelAlert;
					UINavigationController *own = [[UINavigationController alloc] initWithRootViewController:controller];
					debugWindow.rootViewController = own;
				}
				[debugWindow makeKeyAndVisible];
				MPLog(@"отладка: панель показана в своём окне");
			}
		}
		return;
	}
	if (MPLauncher == nil) return;
	if ([cmd caseInsensitiveCompare:@"metro"] == NSOrderedSame) {
		[MPLauncher showMetroAnimated:NO];
		return;
	}
	if ([cmd caseInsensitiveCompare:@"ios"] == NSOrderedSame) {
		[MPLauncher hideMetroAnimated:NO];
		return;
	}
	if ([cmd rangeOfString:@"page" options:NSCaseInsensitiveSearch].location == 0) {		// Лента-пейджер — приватный ivar контроллера; для отладки берём через KVC,
		// чтобы не добавлять в продукт публичных «отладочных» методов.
		UIScrollView *pager = [MPLauncher valueForKey:@"pager"];
		NSInteger page = [[cmd substringFromIndex:4] integerValue];
		if (pager != nil) {
			[pager setContentOffset:CGPointMake(pager.bounds.size.width * page, 0) animated:NO];
			MPLog(@"отладка: страница %ld", (long)page);
		}
	}
}

// Дамп дерева вьюх: класс, кадр, скрытость и текст меток/кнопок. Нужен и для
// диагностики (что именно открылось), и для проверки вёрстки (пересечения,
// вылеты за экран, обрезанный текст) без глаз.
static void MPDebugDumpView(UIView *v, NSInteger depth, NSMutableString *out) {
	if (v == nil || depth > 14) return;
	NSString *extra = @"";
	if ([v isKindOfClass:[UILabel class]]) {
		extra = [NSString stringWithFormat:@" «%@»", ((UILabel *)v).text ?: @""];
	} else if ([v isKindOfClass:[UIButton class]]) {
		extra = [NSString stringWithFormat:@" «%@»", [((UIButton *)v) titleForState:UIControlStateNormal] ?: @""];
	} else if ([v isKindOfClass:[UISwitch class]]) {
		extra = ((UISwitch *)v).isOn ? @" [вкл]" : @" [выкл]";
	}
	[out appendFormat:@"%*s%@ (%.0f,%.0f %.0fx%.0f)%@%@\n",
	 (int)(depth * 2), "", NSStringFromClass([v class]),
	 v.frame.origin.x, v.frame.origin.y, v.frame.size.width, v.frame.size.height,
	 v.hidden ? @" скрыто" : @"", extra];
	for (UIView *s in v.subviews) MPDebugDumpView(s, depth + 1, out);
}

static void MPDebugDump(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		@try {
			BOOL isSpringBoard = (objc_getClass("SBIconView") != nil);
			UIWindow *w = nil;
			if (isSpringBoard) {
				w = MPLockScreenWindow();
				if (w == nil) w = MPSharedHostWindow();
			} else {
				w = [UIApplication sharedApplication].keyWindow;
			}
			if (w == nil) { MPLog(@"отладка: дамп — окна нет"); return; }

			NSMutableString *out = [NSMutableString string];
			[out appendFormat:@"окно %@ %.0fx%.0f\n", NSStringFromClass([w class]),
			 w.bounds.size.width, w.bounds.size.height];
			UIViewController *root = [w rootViewController];
			if (root != nil) [out appendFormat:@"root: %@\n", NSStringFromClass([root class])];
			if ([root isKindOfClass:[UINavigationController class]]) {
				// что именно открыто: класс и заголовок каждого контроллера в стеке
				for (UIViewController *c in ((UINavigationController *)root).viewControllers) {
					[out appendFormat:@"  стек: %@ «%@»\n", NSStringFromClass([c class]), c.title ?: @""];
				}
			}
			MPDebugDumpView(w, 0, out);

			NSString *name = isSpringBoard ? @"dump.txt" : @"dump-prefs.txt";
			NSString *path = [MP_SHOT_DIR stringByAppendingPathComponent:name];
			BOOL ok = [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
			MPLog(@"отладка: дамп %@ → %@", name, ok ? @"ок" : @"НЕ записан");
		} @catch (NSException *e) {
			MPLog(@"!! отладка: дамп — %@ (%@)", e.name, e.reason);
		}
	});
}

static void MPDebugDumpSpecs(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		@try {
			if (objc_getClass("SBIconView") != nil) return;      // только процесс «Настроек»
			UIWindow *w = [UIApplication sharedApplication].keyWindow;
			UITableView *table = nil;
			NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
			while (stack.count > 0 && table == nil) {
				UIView *v = [stack lastObject];
				[stack removeLastObject];
				if ([v isKindOfClass:[UITableView class]]) { table = (UITableView *)v; break; }
				[stack addObjectsFromArray:v.subviews];
			}
			id ds = table.dataSource;
			NSArray *specs = nil;
			if ([ds respondsToSelector:NSSelectorFromString(@"specifiers")]) {
				specs = [ds valueForKey:@"specifiers"];
			}
			NSMutableString *out = [NSMutableString string];
			id (*sendObj)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
			for (id s in specs) {
				NSString *name = [s respondsToSelector:NSSelectorFromString(@"name")] ? [s valueForKey:@"name"] : @"";
				NSString *ident = [s respondsToSelector:NSSelectorFromString(@"identifier")] ? [s valueForKey:@"identifier"] : @"";
				NSString *icon = nil;
				if ([s respondsToSelector:NSSelectorFromString(@"propertyForKey:")]) {
					icon = sendObj(s, NSSelectorFromString(@"propertyForKey:"), @"icon");
				}
				[out appendFormat:@"%@ | %@ | icon=%@\n", ident ?: @"", name ?: @"", icon ?: @"—"];
			}
			NSString *path = [MP_SHOT_DIR stringByAppendingPathComponent:@"dump-specs.txt"];
			[out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
			MPLog(@"отладка: спецификаторов %lu → dump-specs.txt", (unsigned long)specs.count);
		} @catch (NSException *e) {
			MPLog(@"!! отладка: specs — %@ (%@)", e.name, e.reason);
		}
	});
}

static void MPDebugShotTake(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		@try {
			// Снимок делаем в том процессе, где живёт нужная вьюха: у SpringBoard
			// (локскрин — своё окно, лаунчер — главное) и у «Настроек» (свой keyWindow).
			BOOL isSpringBoard = (objc_getClass("SBIconView") != nil);
			UIWindow *w = nil;
			if (isSpringBoard) {
				w = MPLockScreenWindow();
				if (w == nil) w = MPSharedHostWindow();
			} else {
				w = [UIApplication sharedApplication].keyWindow;
			}
			if (w == nil) { MPLog(@"отладка: снимок — окна нет"); return; }

			UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0);
			[w.layer renderInContext:UIGraphicsGetCurrentContext()];
			if (!isSpringBoard) {
				// верхние окна (шапка панели поиска живёт в своём окне) — дорисовать
				for (UIWindow *extra in [UIApplication sharedApplication].windows) {
					if (extra == w || extra.hidden || extra.windowLevel <= w.windowLevel) continue;
					CGContextRef ctx = UIGraphicsGetCurrentContext();
					CGContextSaveGState(ctx);
					CGContextTranslateCTM(ctx, extra.frame.origin.x, extra.frame.origin.y);
					[extra.layer renderInContext:ctx];
					CGContextRestoreGState(ctx);
				}
			}
			UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
			UIGraphicsEndImageContext();
			if (img == nil) { MPLog(@"отладка: снимок — рендер пуст"); return; }

			NSString *name = isSpringBoard ? @"shot.png" : @"shot-prefs.png";
			NSString *path = [MP_SHOT_DIR stringByAppendingPathComponent:name];
			BOOL ok = [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
			MPLog(@"отладка: снимок %@ %@ → %@", NSStringFromClass([w class]),
			      NSStringFromCGSize(w.bounds.size), ok ? @"ок" : @"НЕ записан");
		} @catch (NSException *e) {
			MPLog(@"!! отладка: снимок — %@ (%@)", e.name, e.reason);
		}
	});
}

static void MPDebugShotWatch(void) {
	@try {
		NSFileManager *fm = [NSFileManager defaultManager];
		[fm createDirectoryAtPath:MP_SHOT_DIR withIntermediateDirectories:YES attributes:nil error:NULL];
		if (![fm fileExistsAtPath:@MP_SHOT_REQUEST]) {
			[fm createFileAtPath:@MP_SHOT_REQUEST contents:[NSData data] attributes:nil];
		}
		int fd = open(MP_SHOT_REQUEST, O_EVTONLY);
		if (fd < 0) { MPLog(@"!! отладка: файл запроса не открылся"); return; }

		dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd,
			DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND, dispatch_get_main_queue());
		dispatch_source_set_event_handler(src, ^{
			struct stat st;
			if (stat(MP_SHOT_REQUEST, &st) != 0 || st.st_size == 0) return;

			NSString *cmd = [[NSString stringWithContentsOfFile:@MP_SHOT_REQUEST
			                                              encoding:NSUTF8StringEncoding
			                                                 error:NULL]
			                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			ftruncate(fd, 0);          // гасим запрос, чтобы не сработал повторно

			if (cmd.length > 0 && [cmd caseInsensitiveCompare:@"shot"] != NSOrderedSame) {
				MPDebugRunCommand(cmd);
				// даём анимации/лейауту улечься и снимаем
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
				               dispatch_get_main_queue(), ^{ MPDebugShotTake(); });
			} else {
				MPDebugShotTake();
			}
		});
		dispatch_source_set_cancel_handler(src, ^{ close(fd); });
		// Ссылку держим в статике: ARC освободил бы локальный источник сразу
		// после выхода из функции, и vnode-события бы не приходили.
		MPDebugShotSource = src;
		dispatch_resume(src);
		MPLog(@"отладка: канал снимков готов");
	} @catch (NSException *e) {
		MPLog(@"!! отладка: канал — %@ (%@)", e.name, e.reason);
	}
}

#pragma mark - Инициализация

// Перекраска «Настроек» в WP 8.1 — инициализация только в com.apple.Preferences
extern void MPSettingsInitIfNeeded(void);

// Metro-стиль живёт ТОЛЬКО в SpringBoard (лаунчер и тема стола) и в «Настройках».
// Все остальные приложения не получают ни одного хука — оригинальный дизайн iOS.
static BOOL MPProcessIsPreferences(void) {
	CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle());
	return (bid != nil && CFStringCompare(bid, CFSTR("com.apple.Preferences"), 0) == kCFCompareEqualTo);
}

static void MPCleanupOldLog(void) {
	struct stat st;
	if (stat(MP_LOG_PATH, &st) == 0 && st.st_size > 512 * 1024) {
		remove(MP_LOG_PATH); // не даём журналу расти бесконечно
	}
}

// 133A: перехват необработанного исключения. Само по себе не лечит крэш, но даёт
// текст причины в журнале — без него «Настройки» падали с SIGABRT без следа.
static void MPUncaughtExceptionHandler(NSException *exception) {
	@try {
		MPLog(@"!! необработанное исключение: %@ — %@", [exception name], [exception reason]);
		NSArray *stack = [exception callStackSymbols];
		NSUInteger n = MIN(stack.count, (NSUInteger)10);
		for (NSUInteger i = 0; i < n; i++) MPLog(@"   %@", [stack objectAtIndex:i]);
	} @catch (NSException *e) {
		// журнал недоступен — молчим, чтобы не уронить обработчик
	}
}

%ctor {
	MPCleanupOldLog();
	MPLog(@"=== MetroPhone %@ запуск (pid %d) ===", MP_VERSION, getpid());
	MPLog(@"настройки: вкл=%d панели=%d плитки=%d стильПлиток=%ld обои=%d подписи=%d заглавные=%d акцент=%@ многозадачность=%d локскрин=%d",
	      MPOn(), MPFlag(MPKeyFlatPanels, YES), MPFlag(MPKeyTiles, YES),
	      (long)1, MPFlag(MPKeyBlackWallpaper, YES),
	      MPFlag(MPKeyMetroLabels, YES), MPFlag(MPKeyUppercase, YES),
	      MPString(MPKeyAccent, @"blue"), MPFlag(MPKeyMultitask, YES),
	      MPFlag(MPKeyLockscreen, YES));

	// В %ctor делаем только расстановку хуков (чистый MSHookMessageEx, безопасно до main).
	// Любые вызовы UIKit/графики откладываем на главный поток: до старта runloop
	// инициализация CoreText/CoreGraphics/UIAppearance может подвесить SpringBoard.

	BOOL mpIsPrefs = MPProcessIsPreferences();
	BOOL mpIsSB = (objc_getClass("SBIconView") != nil);

	if (mpIsPrefs || mpIsSB) {
		@try {
			%init(MPUikit);   // база Metro: панели/статус-бар — только тут, не в сторонних приложениях
			MPLog(@"ctor: UIKit-хуки установлены (процесс: %@)", mpIsPrefs ? @"Настройки" : @"SpringBoard");
		} @catch (NSException *e) {
			MPLog(@"!! ctor UIKit: %@ (%@)", e.name, e.reason);
		}
	} else {
		MPLog(@"ctor: стороннее приложение — хуки не устанавливаются, оригинальный дизайн");
	}

	// SpringBoard-классы существуют только в SpringBoard
	if (mpIsSB) {
		MPSBLaunchTime = CFAbsoluteTimeGetCurrent();
		@try {
			%init(MPSpringBoard);
			MPLog(@"ctor: SpringBoard-хуки установлены");

			// Сердцебиение: если SpringBoard умрёт молча, по пропуску строк в журнале
			// будет видно точное время смерти (журнал переживает respring).
			// Держим источник в статике — трогать [UIApplication sharedApplication]
			// из конструктора нельзя: до main это подвешивает SpringBoard.
			dispatch_source_t heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
				dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
			dispatch_source_set_timer(heartbeat, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
				5 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
			dispatch_source_set_event_handler(heartbeat, ^{
				MPLog(@"сердцебиение: жив (pid %d)", getpid());
			});
			dispatch_resume(heartbeat);
			MPHeartbeatSource = heartbeat; // держим ссылку, чтобы источник не освободился

			MPScheduleTileKick();

			@try {
				%init(MPLauncherHooks);
				MPLog(@"ctor: хуки лаунчера установлены");
			} @catch (NSException *e) {
				MPLog(@"!! ctor лаунчер: %@ (%@)", e.name, e.reason);
			}

			// Хуки код-пароля для локскрина: класс может отсутствовать — ставим только если есть
			@try {
				if (objc_getClass("SBPasscodeViewController") != nil) {
					%init(MPLockScreenHooks);
					MPLog(@"ctor: хуки локскрина установлены (SBPasscodeViewController есть)");
				} else {
					MPLog(@"ctor: SBPasscodeViewController не найден — passcode-хуки пропущены");
				}
			} @catch (NSException *e) {
				MPLog(@"!! ctor локскрин: %@ (%@)", e.name, e.reason);
			}

			// отладочный канал снимков экрана (см. MPDebugShotWatch)
			MPDebugShotWatch();

			// блокировка/разблокировка — только для SpringBoard (в приложениях
			// лаунчеру делать нечего, а коллеги по фильтру com.apple.UIKit его бы создали)
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
				&MPLockStateChanged, CFSTR("com.apple.springboard.lockstate"), NULL,
				CFNotificationSuspensionBehaviorDeliverImmediately);

			// включение/выключение экрана: локскрин возвращается после пробуждения
			// и после отмены ввода кода (lockstate в этих случаях не приходит)
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
				&MPDisplayStatusChanged, CFSTR("com.apple.iokit.hid.displayStatus"), NULL,
				CFNotificationSuspensionBehaviorDeliverImmediately);

			// смена акцента в Настройках: при выходе из приложения лаунчер НЕ проходит
			// через showMetroAnimated (просто виден в окне SpringBoard), поэтому плитки
			// и кнопка «M» перекрашиваются по уведомлению, а не при показе
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
				&MPAccentChangedSB, CFSTR("ru.ash.metrophone.accent-changed"), NULL,
				CFNotificationSuspensionBehaviorDeliverImmediately);

			// лаунчер — через 60 с после старта, когда окно вотчдога пройдено
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)),
				dispatch_get_main_queue(), ^{
					MPEnsureLauncher();
				});
		} @catch (NSException *e) {
			MPLog(@"!! ctor SpringBoard: %@ (%@)", e.name, e.reason);
		}
	} else {
		MPLog(@"ctor: SBIconView нет — это не SpringBoard, SpringBoard-хуки пропущены");
	}
	MPLog(@"ctor: хуки готовы");

	// UIAppearance и шрифты настраиваются лениво — при первой отрисовке панелей
	// (см. MPConfigureAppearanceIfNeeded): ранние вызовы UIKit/UIFont из конструктора
	// дедлочили SpringBoard и все приложения на iOS 6.
	if (mpIsPrefs) MPSettingsInitIfNeeded();
	if (mpIsPrefs) MPDebugShotWatch();   // снимок экрана «Настроек» для отладки
	if (mpIsPrefs) NSSetUncaughtExceptionHandler(&MPUncaughtExceptionHandler);   // 133A

	MPLog(@"ctor: завершён");
}
