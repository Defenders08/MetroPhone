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
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <time.h>
#import <sys/stat.h>
#import <sys/time.h>
#import "MetroPhoneCommon.h"
#import "MetroLauncher/MPMetroStyle.h"

#define MP_VERSION @"0.5.2"
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

static NSInteger MPInt(NSString *key, NSInteger def) {
	CFTypeRef v = CFPreferencesCopyAppValue((CFStringRef)key, CFSTR(MP_PREFS_DOMAIN));
	if (v == NULL) return def;
	NSInteger result = def;
	if (CFGetTypeID(v) == CFNumberGetTypeID()) result = [(__bridge NSNumber *)v integerValue];
	CFRelease(v);
	return result;
}

#pragma mark - Состояние

static BOOL MPOn(void)        { return MPFlag(MPKeyEnabled, YES); }
static BOOL MPFlatPanels(void){ return MPOn() && MPFlag(MPKeyFlatPanels, YES); }
static BOOL MPTilesOn(void)   { return MPOn() && MPFlag(MPKeyTiles, YES); }
static BOOL MPWallOn(void)    { return MPOn() && MPFlag(MPKeyBlackWallpaper, YES); }
static BOOL MPLabelsOn(void)  { return MPOn() && MPFlag(MPKeyMetroLabels, YES); }
static BOOL MPUpperOn(void)   { return MPOn() && MPFlag(MPKeyUppercase, YES); }
static BOOL MPTileAccent(void){ return MPInt(MPKeyTileStyle, 0) == 1; }

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
	NSString *style = [NSString stringWithFormat:@"%@-%ld", MPString(MPKeyAccent, @"blue"), (long)MPInt(MPKeyTileStyle, 0)];
	NSString *suffix = scale > 2.5 ? @"@3x" : (scale > 1.5 ? @"@2x" : @"");
	return [dir stringByAppendingPathComponent:
		[NSString stringWithFormat:@"tile-%@-f%d-%@v6%@.png", bid, format, style, suffix]];
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
@interface SBApplication : NSObject
- (NSString *)path;
@end

@interface SBApplicationIcon : NSObject
- (id)application;
- (NSString *)applicationBundleID;
- (void)reloadIconImage;
@end

@interface SBWallpaperView : UIImageView
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

	// 1) готовая плитка с диска
	UIImage *disk = [UIImage imageWithContentsOfFile:tilePath];
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
	MPLog(@"SBIconView: тень %@ (скрыта=%d)", view ? @"создана" : @"нет", (MPTilesOn() || MPWallOn()));
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
	MPLogOnce(@"sbiconview-frame", @"SBIconView.setFrame: %@", NSStringFromCGRect(frame));
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

// Убираем «полку» дока
%hook SBDockIconListView
+ (UIImage *)backgroundImageForOrientation:(int)orientation {
	UIImage *orig = %orig;
	MPLog(@"док: фон %@ (отключён=%d)", orig ? NSStringFromCGSize(orig.size) : @"nil", MPWallOn());
	if (MPWallOn()) return nil;
	return orig;
}
%end

%end // MPSpringBoard

#pragma mark - Metro-лаунчер (интеграция, код из PROMPT-OSNOVA.md раздел 6.2)

#import "MetroLauncher/MPAppDataSource.h"
#import "MetroLauncher/MPHomeController.h"

static MPHomeController *MPLauncher = nil;
static void MPEnsureLauncher(void); // ленивое создание лаунчера (реализация ниже)

@interface SBAwayController : NSObject
+ (id)sharedAwayController;
- (BOOL)isLocked;
@end

static void MPLockStateChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	// наблюдатель регистрируется во всех UIKit-процессах, живём только в SpringBoard
	if (objc_getClass("SBIconView") == nil) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		MPEnsureLauncher();
		BOOL locked = [[objc_getClass("SBAwayController") sharedAwayController] isLocked];
		if (locked) [MPLauncher hideMetroAnimated:NO];
		else [MPLauncher showMetroAnimated:NO];
	});
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
struct __GSEvent;

%group MPLauncherHooks

%hook SpringBoard
- (void)menuButtonDown:(struct __GSEvent *)event {
	%orig;
	if (MPLauncher != nil && [MPLauncher isMetroVisible]) {
		[MPLauncher homeButtonPressed];
		MPLog(@"Home: выход из режима правки");
	}
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

%ctor {
	MPCleanupOldLog();
	MPLog(@"=== MetroPhone %@ запуск (pid %d) ===", MP_VERSION, getpid());
	MPLog(@"настройки: вкл=%d панели=%d плитки=%d стильПлиток=%ld обои=%d подписи=%d заглавные=%d акцент=%@",
	      MPOn(), MPFlag(MPKeyFlatPanels, YES), MPFlag(MPKeyTiles, YES),
	      (long)MPInt(MPKeyTileStyle, 0), MPFlag(MPKeyBlackWallpaper, YES),
	      MPFlag(MPKeyMetroLabels, YES), MPFlag(MPKeyUppercase, YES),
	      MPString(MPKeyAccent, @"blue"));

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

			// блокировка/разблокировка — только для SpringBoard (в приложениях
			// лаунчеру делать нечего, а коллеги по фильтру com.apple.UIKit его бы создали)
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
				&MPLockStateChanged, CFSTR("com.apple.springboard.lockstate"), NULL,
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

	MPLog(@"ctor: завершён");
}
