// MetroPhone — вьюха Metro-локскрина (WP 8.1). iOS 6.1, экран 320×480.
//
// Структура снизу вверх: UIImageView с обоями → подписи (часы/день/дата) →
// статусные строки (батарея + уведомления). Пан-жест: вверх уносит вьюху
// (разблокировка, механика iOS 7), влево — запускает камеру, как в оригинале:
// вьюха следует за пальцем, иконка камеры наливается и растёт, за порогом
// экран уезжает за левый край и зовётся колбэк камеры; недотянутый жест —
// пружина назад. Замеры текста — только iOS 6 API (sizeWithFont:), метки — UILabel.

#import "MPLockScreenView.h"
#import "../MetroLauncher/MPMetroStyle.h"
#import <QuartzCore/QuartzCore.h> // CATransactionFlush (коммит анимаций до тяжёлых вызовов)

#import <objc/runtime.h>
#import <dlfcn.h>
#import <math.h>

// Метрики нижнего блока (пропорции референса WP 8.1)
static const CGFloat MPLSLeftInset   = 20.0;  // левый отступ блока
static const CGFloat MPLSBottomInset = 20.0;  // отступ даты от нижнего края
static const CGFloat MPLSClockSize   = 64.0;  // кегль часов
static const CGFloat MPLSDateSize    = 24.0;  // кегль дня недели и даты
static const CGFloat MPLSRowSize     = 15.0;  // кегль строк батареи и уведомлений
static const CGFloat MPLSUnlockDistance = 140.0; // порог свайпа (pt вверх)
static const CGFloat MPLSUnlockVelocity = 700.0; // либо резкий флик вверх (pt/с)
static const CGFloat MPLSAxisLockDelta  = 12.0;  // смещение, после которого фиксируется ось жеста
static const CGFloat MPLSCameraDistance = 90.0;  // порог свайпа влево для камеры (pt)
static const CGFloat MPLSCameraVelocity = 600.0; // либо резкий флик влево (pt/с)
static const CGFloat MPLSIconIdleAlpha  = 0.60;  // прозрачность иконки камеры в покое (при свайпе — до 1)

// Ось пан-жеста: фиксируется по первому заметному движению и не меняется до
// конца жеста — диагональный свайп не должен дёргать обе анимации сразу
typedef enum {
    MPLSPanAxisNone = 0,
    MPLSPanAxisVertical,   // вверх — разблокировка
    MPLSPanAxisHorizontal, // влево — камера
} MPLSPanAxis;

#pragma mark - Батарея (IOPS через dlsym — без линковки IOKit, чтобы не трогать tbd)

static NSInteger MPLSBatteryPercent(void) {
	typedef CFTypeRef (*IOPSCopyInfoFn)(void);
	typedef CFArrayRef (*IOPSListFn)(CFTypeRef blob);
	typedef CFDictionaryRef (*IOPSDescFn)(CFTypeRef blob, CFTypeRef ps);
	static IOPSCopyInfoFn copyInfo = nil;
	static IOPSListFn listFn = nil;
	static IOPSDescFn descFn = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
		if (handle == NULL) {
			MPLog(@"!! локскрин: IOKit не открылся — батареи не будет");
			return;
		}
		copyInfo = (IOPSCopyInfoFn)dlsym(handle, "IOPSCopyPowerSourcesInfo");
		listFn   = (IOPSListFn)dlsym(handle, "IOPSGetPowerSourceList");
		descFn   = (IOPSDescFn)dlsym(handle, "IOPSGetPowerSourceDescription");
	});
	if (copyInfo == NULL || listFn == NULL || descFn == NULL) return -1;
	@try {
		CFTypeRef blob = copyInfo();
		if (blob == NULL) return -1;
		NSInteger percent = -1;
		CFArrayRef list = listFn(blob);
		if (list != NULL) {
			for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
				// Get-словарь принадлежит blob и отдельно не освобождается
				CFDictionaryRef desc = descFn(blob, CFArrayGetValueAtIndex(list, i));
				if (desc == NULL) continue;
				CFNumberRef cur = (CFNumberRef)CFDictionaryGetValue(desc, CFSTR("Current Capacity"));
				CFNumberRef max = (CFNumberRef)CFDictionaryGetValue(desc, CFSTR("Max Capacity"));
				if (cur != NULL && max != NULL) {
					NSInteger c = 0, m = 0;
					CFNumberGetValue(cur, kCFNumberNSIntegerType, &c);
					CFNumberGetValue(max, kCFNumberNSIntegerType, &m);
					if (m > 0) percent = (NSInteger)(100.0 * c / m + 0.5);
				}
			}
			CFRelease(list);
		}
		CFRelease(blob);
		return percent;
	} @catch (NSException *e) {
		MPLog(@"!! локскрин: батарея — %@ (%@)", e.name, e.reason);
		return -1;
	}
}

#pragma mark - Уведомления (бейджи приложений)

// Классы SpringBoard для бейджей (селекторы — с запасными путями, всё через respondsToSelector)
@interface SBApplication : NSObject
- (NSString *)displayIdentifier;
- (NSString *)displayName;
- (NSString *)badgeValue;
@end

@interface SBApplicationController : NSObject
+ (id)sharedInstance;
- (NSArray *)allApplications;
@end

@interface SBIconModel : NSObject
+ (id)sharedInstance;
- (id)applicationBadgeForDisplayIdentifier:(NSString *)identifier;
@end

// Приложения с ненулевыми бейджами, топ-3 по убыванию:
// @{ @"name": NSString, @"count": NSNumber }. Бейдж в iOS 6 живёт в SBIconModel
// (applicationBadgeForDisplayIdentifier:); запасной путь — свойства SBApplication.
// Скан идёт по ВСЕМ установленным приложениям, а вызов происходит на каждом показе
// и каждый минутный тик — результат кэшируется на 30 с (бейджи меняются редко).
static NSArray *MPLSBadgeRows(void) {
	static NSArray *cache = nil;
	static CFAbsoluteTime cacheStamp = 0;
	CFAbsoluteTime nowTime = CFAbsoluteTimeGetCurrent();
	if (cache != nil && nowTime - cacheStamp < 30.0) return cache;

	NSMutableArray *rows = [NSMutableArray array];
	@try {
		Class ctrlCls = objc_getClass("SBApplicationController");
		id ctrl = (ctrlCls != nil && [ctrlCls respondsToSelector:@selector(sharedInstance)]) ? [ctrlCls sharedInstance] : nil;
		NSArray *all = (ctrl != nil && [ctrl respondsToSelector:@selector(allApplications)]) ? [ctrl allApplications] : nil;
		if (all.count == 0) return rows;

		Class modelCls = objc_getClass("SBIconModel");
		id model = (modelCls != nil && [modelCls respondsToSelector:@selector(sharedInstance)]) ? [modelCls sharedInstance] : nil;
		BOOL modelWorks = (model != nil && [model respondsToSelector:@selector(applicationBadgeForDisplayIdentifier:)]);
		static BOOL logged = NO;
		if (!logged) {
			logged = YES;
			MPLog(@"локскрин: бейджи — SBIconModel %@", modelWorks ? @"ок" : @"недоступен, пробуем SBApplication");
		}

		for (id app in all) {
			NSString *bid = [app respondsToSelector:@selector(displayIdentifier)] ? [app displayIdentifier] : nil;
			if (![bid isKindOfClass:[NSString class]] || bid.length == 0) continue;

			NSInteger count = -1;
			if (modelWorks) {
				id v = [model applicationBadgeForDisplayIdentifier:bid];
				if ([v respondsToSelector:@selector(integerValue)]) count = [v integerValue];
			}
			if (count < 0 && [app respondsToSelector:@selector(badgeValue)]) {
				id v = [app badgeValue];
				if (v != nil && [v respondsToSelector:@selector(integerValue)]) count = [v integerValue];
			}
			if (count <= 0) continue;

			NSString *name = [app respondsToSelector:@selector(displayName)] ? [app displayName] : bid;
			if (![name isKindOfClass:[NSString class]] || name.length == 0) name = bid;
			[rows addObject:@{ @"name": name, @"count": @(count) }];
		}
		[rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			return [b[@"count"] compare:a[@"count"]];
		}];
		if (rows.count > 3) [rows removeObjectsInRange:NSMakeRange(3, rows.count - 3)];
	} @catch (NSException *e) {
		MPLog(@"!! локскрин: бейджи — %@ (%@)", e.name, e.reason);
	}
	cache = rows;
	cacheStamp = CFAbsoluteTimeGetCurrent();
	return rows;
}

#pragma mark - Вьюха

// Глиф камеры в духе Metro UI / Windows Phone: тонкий УГЛОВАТЫЙ контур —
// корпус и выступ-видоискатель с острыми 90-градусными углами одной
// непрерывной линией, внутри круг объектива (круг оставляем — без него глиф
// перестаёт читаться как камера). Намеренно мелкий (22×17) и полупрозрачный —
// подсказка, а не кнопка-плитка. Рисуем векторно в drawRect (на @2x чисто,
// PNG не нужен), тап ловится распознавателем снаружи.
@interface MPLSCameraIconView : UIView
@end

@implementation MPLSCameraIconView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self == nil) return self;
	self.backgroundColor = [UIColor clearColor];
	self.userInteractionEnabled = YES;
	self.contentMode = UIViewContentModeRedraw;
	return self;
}

- (void)drawRect:(CGRect)rect {
	CGFloat w = rect.size.width;
	CGFloat h = rect.size.height;
	CGFloat line = 1.25;

	CGFloat bumpW = 8.0;    // ширина выступа-видоискателя
	CGFloat bumpH = 3.5;    // высота выступа
	CGFloat xL = line / 2.0, xR = w - line / 2.0;
	CGFloat yT = bumpH, yB = h - line / 2.0;
	CGFloat bx1 = (w - bumpW) / 2.0, bx2 = (w + bumpW) / 2.0;

	// Один замкнутый силуэт без скруглений: выступ вливается в верхнюю грань
	// корпуса, все углы прямые
	UIBezierPath *path = [UIBezierPath bezierPath];
	[path moveToPoint:CGPointMake(bx1, yT)];
	[path addLineToPoint:CGPointMake(bx1, line / 2.0)];
	[path addLineToPoint:CGPointMake(bx2, line / 2.0)];
	[path addLineToPoint:CGPointMake(bx2, yT)];
	[path addLineToPoint:CGPointMake(xR, yT)];
	[path addLineToPoint:CGPointMake(xR, yB)];
	[path addLineToPoint:CGPointMake(xL, yB)];
	[path addLineToPoint:CGPointMake(xL, yT)];
	[path closePath];

	// Объектив — вторым подпутём
	CGFloat lensD = MIN(xR - xL, yB - yT) * 0.5;
	[path appendPath:[UIBezierPath bezierPathWithOvalInRect:
	    CGRectMake((w - lensD) / 2.0, yT + ((yB - yT) - lensD) / 2.0, lensD, lensD)]];

	path.lineWidth = line;
	path.lineJoinStyle = kCGLineJoinMiter;

	// Почти непрозрачный белый: итоговую прозрачность задаёт alpha самой вьюхи
	// (0.6 в покое, при свайпе влево наливается до 1.0). Тень едва заметная,
	// только чтобы контур не терялся на светлых обоях
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 0.5,
	                            [UIColor colorWithWhite:0.0 alpha:0.25].CGColor);
	[[UIColor colorWithWhite:1.0 alpha:0.9] setStroke];
	[path stroke];
}

@end

@interface MPLockScreenView ()
@property (nonatomic, strong) UIImageView *wallpaperView;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *weekdayLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *statusStack;   // батарея + строки уведомлений
@property (nonatomic, strong) UIView *cameraIcon;    // камера WP внизу справа
@property (nonatomic, strong) dispatch_source_t clockSource;
@property (nonatomic, strong) CADisplayLink *slideFpsLink;  // замер кадров слайда
@property (nonatomic, assign) NSTimeInterval fpsT, fpsSum, fpsMax;
@property (nonatomic, assign) NSInteger fpsN, fpsOver, fpsOver33;
@property (nonatomic, assign) CGFloat homeY;         // «домашний» center.y до жеста
@property (nonatomic, assign) CGFloat homeX;         // «домашний» center.x до жеста
@property (nonatomic, assign) MPLSPanAxis panAxis;   // выбранная ось текущего жеста
@property (nonatomic, assign) BOOL cameraBusy;       // камера уже запускается (тап/свайп)
@end

@implementation MPLockScreenView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self == nil) return self;

	self.backgroundColor = [UIColor blackColor];
	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

	_wallpaperView = [[UIImageView alloc] initWithFrame:self.bounds];
	_wallpaperView.contentMode = UIViewContentModeScaleAspectFill;
	_wallpaperView.clipsToBounds = YES;
	_wallpaperView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_wallpaperView.hidden = YES;
	[self addSubview:_wallpaperView];

	// Лёгкая тень под белым текстом — читаемость на светлых обоях (на тёмных не видна)
	UIColor *shadow = [UIColor colorWithWhite:0.0 alpha:0.45];

	_clockLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_clockLabel.backgroundColor = [UIColor clearColor];
	_clockLabel.textColor = [UIColor whiteColor];
	_clockLabel.font = [MPMetroStyle thinFont:MPLSClockSize];
	_clockLabel.shadowColor = shadow;
	_clockLabel.shadowOffset = CGSizeMake(0, 1);
	[self addSubview:_clockLabel];

	_weekdayLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_weekdayLabel.backgroundColor = [UIColor clearColor];
	_weekdayLabel.textColor = [UIColor whiteColor];
	_weekdayLabel.font = [MPMetroStyle regularFont:MPLSDateSize];
	_weekdayLabel.shadowColor = shadow;
	_weekdayLabel.shadowOffset = CGSizeMake(0, 1);
	[self addSubview:_weekdayLabel];

	_dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_dateLabel.backgroundColor = [UIColor clearColor];
	_dateLabel.textColor = [UIColor whiteColor];
	_dateLabel.font = [MPMetroStyle regularFont:MPLSDateSize];
	_dateLabel.shadowColor = shadow;
	_dateLabel.shadowOffset = CGSizeMake(0, 1);
	[self addSubview:_dateLabel];

	_statusStack = [[UIView alloc] initWithFrame:CGRectZero];
	_statusStack.backgroundColor = [UIColor clearColor];
	_statusStack.userInteractionEnabled = NO;
	[self addSubview:_statusStack];

	_cameraIcon = [[MPLSCameraIconView alloc] initWithFrame:CGRectMake(0, 0, 22, 17)];
	_cameraIcon.alpha = MPLSIconIdleAlpha;
	[self addSubview:_cameraIcon];
	UITapGestureRecognizer *cameraTap =
	    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCameraTap:)];
	[_cameraIcon addGestureRecognizer:cameraTap];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
	[self addGestureRecognizer:pan];

	return self;
}

- (void)handleCameraTap:(UITapGestureRecognizer *)gr {
	// Повторный тап и тап во время перетаскивания не дублируем
	if (self.cameraBusy || self.panAxis != MPLSPanAxisNone) return;
	self.cameraBusy = YES;
	// Отклик кнопки: глиф вспыхивает и растёт, затем весь экран тает — и только
	// после этого запускаем камеру (разблокировка и запуск — в контроллере)
	[UIView animateWithDuration:0.12
	                      delay:0.0
	                    options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
	                 animations:^{
		self.cameraIcon.alpha = 1.0;
		self.cameraIcon.transform = CGAffineTransformMakeScale(1.4, 1.4);
	}
	                 completion:^(BOOL finished) {
		[UIView animateWithDuration:0.22
		                      delay:0.0
		                    options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
		                 animations:^{
			self.alpha = 0.0;
		}
		                 completion:^(BOOL finished2) {
			if (self.onCameraBlock != nil) self.onCameraBlock();
		}];
	}];
}

#pragma mark Обои и положение

- (void)setWallpaperImage:(UIImage *)image {
	_wallpaperView.image = image;
	_wallpaperView.hidden = (image == nil);
	MPLog(@"локскрин: обои %@", image != nil ? NSStringFromCGSize(image.size) : @"нет (чёрный фон)");
}

- (void)resetSlide {
	UIView *parent = self.superview;
	CGFloat x = (parent != nil) ? parent.bounds.size.width / 2.0 : self.bounds.size.width / 2.0;
	CGFloat y = (parent != nil) ? parent.bounds.size.height / 2.0 : self.bounds.size.height / 2.0;
	self.transform = CGAffineTransformIdentity;
	self.alpha = 1.0;
	self.center = CGPointMake(x, y);
	self.homeX = x;
	self.homeY = y;
	self.panAxis = MPLSPanAxisNone;
	self.cameraBusy = NO;
	[self resetCameraHint];
}

#pragma mark Формат времени (12/24ч из локали устройства)

- (NSString *)clockFormat {
	static NSString *format = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// Шаблон «j» раскрывается по 12/24-часовой настройке устройства:
		// в 12-часовых локалях в паттерн входит маркер «a» (AM/PM)
		NSString *tmpl = [NSDateFormatter dateFormatFromTemplate:@"j:mm" options:0 locale:[NSLocale currentLocale]];
		format = ([tmpl rangeOfString:@"a"].location == NSNotFound) ? @"HH:mm" : @"h:mm";
	});
	return format;
}

#pragma mark Контент

- (void)refreshContent {
	NSDate *now = [NSDate date];

	// NSDateFormatter дорого создавать (инициализация ICU и локали), а refreshContent
	// выполняется на каждый показ локскрина и раз в минуту — форматтеры статические.
	static NSDateFormatter *clockFmt = nil, *weekdayFmt = nil, *dateFmt = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSLocale *locale = [NSLocale currentLocale];
		clockFmt = [[NSDateFormatter alloc] init];
		clockFmt.locale = locale;
		clockFmt.dateFormat = [self clockFormat];
		weekdayFmt = [[NSDateFormatter alloc] init];
		weekdayFmt.locale = locale;
		weekdayFmt.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEE" options:0 locale:locale];
		dateFmt = [[NSDateFormatter alloc] init];
		dateFmt.locale = locale;
		dateFmt.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"dMMMM" options:0 locale:locale];
	});

	self.clockLabel.text = [clockFmt stringFromDate:now];
	self.weekdayLabel.text = [weekdayFmt stringFromDate:now];
	self.dateLabel.text = [dateFmt stringFromDate:now];

	[self rebuildStatusStack];
	[self setNeedsLayout];
}

// Пересборка статусных строк над часами: батарея, затем до 3 строк уведомлений
- (void)rebuildStatusStack {
	UIView *stack = self.statusStack;
	[stack.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

	CGFloat width = self.bounds.size.width - MPLSLeftInset * 2;
	UIFont *rowFont = [MPMetroStyle lightFont:MPLSRowSize];
	CGFloat rowHeight = ceil(20.0);
	CGFloat gap = 6.0;
	CGFloat y = 0.0;

	// Батарея: [глиф] 84%
	NSInteger percent = MPLSBatteryPercent();
	if (percent >= 0) {
		UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, rowHeight)];
		row.backgroundColor = [UIColor clearColor];
		row.userInteractionEnabled = NO;
		[row addSubview:[self batteryGlyph:percent]];
		UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(36, 0, 100, rowHeight)];
		label.backgroundColor = [UIColor clearColor];
		label.textColor = [UIColor whiteColor];
		label.font = rowFont;
		label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.45];
		label.shadowOffset = CGSizeMake(0, 1);
		label.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
		[row addSubview:label];
		[stack addSubview:row];
		y += rowHeight + gap;
	}

	// Уведомления: [квадрат с буквой] Имя  число
	for (NSDictionary *rowInfo in MPLSBadgeRows()) {
		NSString *name = rowInfo[@"name"];
		NSString *count = [rowInfo[@"count"] stringValue];

		UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, width, rowHeight)];
		row.backgroundColor = [UIColor clearColor];
		row.userInteractionEnabled = NO;
		[row addSubview:[self badgeGlyphForName:name]];

		CGFloat textX = 24.0;
		CGFloat nameWidth = [name sizeWithFont:rowFont].width;
		UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 0, ceil(nameWidth) + 2, rowHeight)];
		nameLabel.backgroundColor = [UIColor clearColor];
		nameLabel.textColor = [UIColor whiteColor];
		nameLabel.font = rowFont;
		nameLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.45];
		nameLabel.shadowOffset = CGSizeMake(0, 1);
		nameLabel.text = name;
		[row addSubview:nameLabel];

		UILabel *countLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX + ceil(nameWidth) + 8, 0, 60, rowHeight)];
		countLabel.backgroundColor = [UIColor clearColor];
		countLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
		countLabel.font = rowFont;
		countLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.45];
		countLabel.shadowOffset = CGSizeMake(0, 1);
		countLabel.text = count;
		[row addSubview:countLabel];

		[stack addSubview:row];
		y += rowHeight + gap;
	}

	stack.frame = CGRectMake(MPLSLeftInset, 0, width, y > 0 ? y - gap : 0);
	stack.hidden = (y <= 0);
}

// Квадратик-глиф приложения: цвет акцента, первая буква имени
- (UIView *)badgeGlyphForName:(NSString *)name {
	UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(0, 2, 16, 16)];
	tile.backgroundColor = [MPMetroStyle accentColor];
	tile.userInteractionEnabled = NO;

	UILabel *letter = [[UILabel alloc] initWithFrame:tile.bounds];
	letter.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	letter.backgroundColor = [UIColor clearColor];
	letter.textColor = [UIColor whiteColor];
	letter.font = [MPMetroStyle mediumFont:11];
	letter.textAlignment = NSTextAlignmentCenter;
	if (name.length > 0) {
		letter.text = [[name substringToIndex:1] uppercaseStringWithLocale:[NSLocale currentLocale]];
	}
	[tile addSubview:letter];
	return tile;
}

// Глиф батареи: рамка-корпус, заливка по уровню, контакт справа
- (UIView *)batteryGlyph:(NSInteger)percent {
	UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 27, 12)];
	holder.backgroundColor = [UIColor clearColor];
	holder.userInteractionEnabled = NO;

	UIView *body = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 12)];
	body.backgroundColor = [UIColor clearColor];
	body.layer.borderColor = [[UIColor colorWithWhite:1.0 alpha:0.9] CGColor];
	body.layer.borderWidth = 1.0;
	body.layer.cornerRadius = 2.0;
	[holder addSubview:body];

	CGFloat fill = (24.0 - 4.0) * MIN(MAX(percent, 0), 100) / 100.0;
	UIView *level = [[UIView alloc] initWithFrame:CGRectMake(2, 2, MAX(fill, 2.0), 8)];
	level.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.95];
	[body addSubview:level];

	UIView *nub = [[UIView alloc] initWithFrame:CGRectMake(25, 3.5, 2, 5)];
	nub.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.9];
	[holder addSubview:nub];
	return holder;
}

#pragma mark Раскладка

- (void)layoutSubviews {
	[super layoutSubviews];

	CGFloat width = self.bounds.size.width;
	CGFloat bottom = self.bounds.size.height - MPLSBottomInset;

	// Дата — нижняя строка (как на референсе), затем день недели и часы
	CGSize dateSize = [self.dateLabel.text sizeWithFont:self.dateLabel.font];
	CGFloat dateHeight = ceil(dateSize.height);
	self.dateLabel.frame = CGRectMake(MPLSLeftInset, bottom - dateHeight, width - MPLSLeftInset, dateHeight);
	bottom -= dateHeight;

	CGSize weekdaySize = [self.weekdayLabel.text sizeWithFont:self.weekdayLabel.font];
	CGFloat weekdayHeight = ceil(weekdaySize.height);
	self.weekdayLabel.frame = CGRectMake(MPLSLeftInset, bottom - weekdayHeight, width - MPLSLeftInset, weekdayHeight);
	bottom -= weekdayHeight;

	// Часы: у тонкого шрифта слегка отрицательный боковой вынос — компенсируем отступом
	CGSize clockSize = [self.clockLabel.text sizeWithFont:self.clockLabel.font];
	CGFloat clockHeight = ceil(clockSize.height);
	self.clockLabel.frame = CGRectMake(MPLSLeftInset - 2, bottom - clockHeight, width, clockHeight);
	bottom -= clockHeight;

	// Статусные строки (батарея + уведомления) над блоком часов
	CGFloat stackHeight = self.statusStack.frame.size.height;
	if (stackHeight > 0) {
		self.statusStack.frame = CGRectMake(MPLSLeftInset, bottom - stackHeight - 14.0,
		                                    width - MPLSLeftInset * 2, stackHeight);
	}

	// Иконка камеры — внизу справа, в одной 20-пиксельной сетке с блоком часов
	self.cameraIcon.frame = CGRectMake(width - 22.0 - MPLSLeftInset,
	                                   self.bounds.size.height - 17.0 - MPLSBottomInset,
	                                   22.0, 17.0);
}

#pragma mark Жесты: вверх — разблокировка (iOS 7), влево — камера (WP 8.1)

- (void)handlePan:(UIPanGestureRecognizer *)gr {
	CGPoint translation = [gr translationInView:self];

	if (gr.state == UIGestureRecognizerStateChanged) {
		// Ось фиксируем по первому заметному движению; накопленный до порога
		// сдвиг обнуляем, чтобы вьюха не дёрнулась скачком
		if (self.panAxis == MPLSPanAxisNone) {
			if (fabs(translation.x) < MPLSAxisLockDelta &&
			    fabs(translation.y) < MPLSAxisLockDelta) return;
			self.panAxis = (fabs(translation.x) > fabs(translation.y))
			    ? MPLSPanAxisHorizontal : MPLSPanAxisVertical;
			// Вертикальный драг начался (до порога): лаунчер греется заранее,
			// чтобы слайд и Turnstile перекрывались — ноль «ямы»
			if (self.panAxis == MPLSPanAxisVertical && self.onDragBeginBlock != nil) {
				self.onDragBeginBlock();
			}
			[gr setTranslation:CGPointZero inView:self];
			return;
		}

		if (self.panAxis == MPLSPanAxisVertical) {
			// Драг 1:1 — локскрин просто идёт за пальцем, без резинки и эффектов
			self.center = CGPointMake(self.superview.bounds.size.width / 2.0, self.homeY + translation.y);
		} else {
			// Влево вьюха следует за пальцем с сопротивлением, вправо — резинка
			CGFloat dx = translation.x;
			dx = (dx < 0) ? dx * 0.75 : dx * 0.08;
			self.center = CGPointMake(self.homeX + dx, self.homeY);
			[self updateCameraHint:translation.x];
		}
		return;
	}

	if (gr.state == UIGestureRecognizerStateEnded ||
	    gr.state == UIGestureRecognizerStateCancelled) {
		MPLSPanAxis axis = self.panAxis;
		self.panAxis = MPLSPanAxisNone;

		if (axis == MPLSPanAxisHorizontal) {
			CGPoint velocity = [gr velocityInView:self];
			CGFloat dx = self.center.x - self.homeX;
			if (-dx > MPLSCameraDistance || velocity.x < -MPLSCameraVelocity) {
				[self slideAwayAndCamera];
			} else {
				[self springBack];
			}
		} else if (axis == MPLSPanAxisVertical) {
			CGPoint velocity = [gr velocityInView:self];
			CGFloat dy = self.center.y - self.homeY;
			if (-dy > MPLSUnlockDistance || velocity.y < -MPLSUnlockVelocity) {
				[self slideAwayAndUnlockWithVelocity:velocity.y];
			} else {
				// Свайп не дотянут: прогретый лаунчер под вьюхой уже не нужен
				if (self.onDragAbortBlock != nil) self.onDragAbortBlock();
				[self springBackWithVelocity:velocity.y];
			}
		}
	}
}

// Иконка камеры как индикатор свайпа: по мере утягивания влево глиф наливается,
// растёт и слегка уходит за палец — подсказка «отпустишь = камера»
- (void)updateCameraHint:(CGFloat)rawDx {
	CGFloat progress = MIN(MAX(-rawDx / MPLSCameraDistance, 0.0), 1.0);
	CGFloat scale = 1.0 + 0.4 * progress;
	CGAffineTransform t = CGAffineTransformMakeTranslation(-8.0 * progress, 0.0);
	self.cameraIcon.transform = CGAffineTransformScale(t, scale, scale);
	self.cameraIcon.alpha = MPLSIconIdleAlpha + (1.0 - MPLSIconIdleAlpha) * progress;
}

- (void)resetCameraHint {
	self.cameraIcon.transform = CGAffineTransformIdentity;
	self.cameraIcon.alpha = MPLSIconIdleAlpha;
}

- (void)slideAwayAndCamera {
	self.cameraBusy = YES;
	[UIView animateWithDuration:0.25
	                      delay:0.0
	                    options:UIViewAnimationOptionCurveEaseIn
	                 animations:^{
		self.center = CGPointMake(-self.bounds.size.width / 2.0, self.homeY);
	}
	                 completion:^(BOOL finished) {
		if (self.onCameraBlock != nil) self.onCameraBlock();
	}];
}

// ---- Замер кадров слайда ----

- (void)mpSlideFpsTick {
	NSTimeInterval now = CACurrentMediaTime();
	double d = (now - _fpsT) * 1000.0;
	_fpsT = now;
	if (_fpsN == 0) {
		// Первый кадр после отпускания: наша занятость потока + кадр рендера
		MPLog(@"анлок-хроника: первый кадр слайда через %.0f мс от старта", d);
	} else {
		_fpsSum += d;
		if (d > _fpsMax) _fpsMax = d;
		if (d > 20.0) _fpsOver++;
		if (d > 33.0) _fpsOver33++;
	}
	_fpsN++;
}

- (void)mpSlideFpsStart {
	[_slideFpsLink invalidate];
	_fpsN = 0; _fpsOver = 0; _fpsOver33 = 0; _fpsSum = 0; _fpsMax = 0;
	_fpsT = CACurrentMediaTime();
	CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(mpSlideFpsTick)];
	[link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
	_slideFpsLink = link;
}

- (void)mpSlideFpsStop {
	if (_slideFpsLink == nil) {
		MPLog(@"анлок-хроника: fps слайда: замер не вёлся (link nil)");
		return;
	}
	[_slideFpsLink invalidate];
	_slideFpsLink = nil;
	// Без порога: даже 0–1 тик — диагностика, почему link не тикал
	MPLog(@"анлок-хроника: fps слайда: %ld кадров, >20 мс: %ld, >33 мс: %ld, худший %.1f мс, средний %.1f мс",
	      (long)_fpsN, (long)_fpsOver, (long)_fpsOver33, _fpsMax, _fpsN > 1 ? _fpsSum / (_fpsN - 1) : 0.0);
}

// ---- Слайд-разблокировка: обычный уезд вверх, ease-out 0.3 с ----

- (void)slideAwayAndUnlockWithVelocity:(CGFloat)velocityY {
	UIView *parent = self.superview;
	CGFloat h = (parent != nil) ? parent.bounds.size.height : self.bounds.size.height;
	NSTimeInterval t0 = CACurrentMediaTime();
	[self mpSlideFpsStart];
	// Слайд от ТЕКУЩЕЙ позиции пальца: центр уже = точке драга; фиксируем от
	// presentation-слоя на случай незаконченных анимаций — скачка назад не будет
	CALayer *pres = self.layer.presentationLayer;
	if (pres != nil) self.center = pres.position;
	// EaseOut: анимация стартует со скоростью пальца и тормозит — без «паузы»
	// EaseInOut на старте. Длительность из остатка пути и скорости отпускания:
	// флик долетает коротко, медленно дотащенный драг — долго (как до 0.38 с)
	CGFloat remaining = self.center.y + h / 2.0 + 20.0;
	CGFloat speed = MAX(-velocityY, 0.0);
	CGFloat dur = 1.6 * remaining / MAX(speed, 500.0);
	dur = MIN(MAX(dur, 0.18), 0.45);
	// До ПОЛНОГО выхода за экран (нижний край на −20 pt)
	[UIView animateWithDuration:dur
	                      delay:0.0
	                    options:UIViewAnimationOptionCurveEaseOut
	                 animations:^{
		self.center = CGPointMake(self.superview.bounds.size.width / 2.0, -h / 2.0 - 20.0);
	}
	                 completion:^(BOOL finished) {
		[self mpSlideFpsStop];
		if (self.onSlideDoneBlock != nil) self.onSlideDoneBlock();
	}];
	if (self.onUnlockBlock != nil) self.onUnlockBlock();
	// Принудительный коммит: анимации уходят в рендер-процесс до тяжёлых вызовов
	[CATransaction flush];
	MPLog(@"анлок-хроника: слайд %.0f мс (скорость %.0f pt/с, остаток %.0f pt), main занят до коммита %.0f мс (цель ≤16)",
	      dur * 1000.0, speed, remaining, (CACurrentMediaTime() - t0) * 1000.0);
}

- (void)springBack {
	// Публичная обёртка (провал анлока из опроса): скорости пальца уже нет
	[self springBackWithVelocity:0.0];
}

- (void)springBackWithVelocity:(CGFloat)velocityY {
	// Недотянутый флик продолжает движение вверх по инерции (до 40 pt), потом
	// откатывает; медленный дотащенный драг возвращается сразу
	CGFloat drift = MIN(MAX(-velocityY * 0.06, 0.0), 40.0);
	if (drift < 4.0) {
		[self mpSpringHome];
		return;
	}
	[UIView animateWithDuration:0.12
	                      delay:0.0
	                    options:UIViewAnimationOptionCurveEaseOut
	                 animations:^{
		self.center = CGPointMake(self.homeX, self.center.y - drift);
	}
	                 completion:^(BOOL finished) {
		[self mpSpringHome];
	}];
}

- (void)mpSpringHome {
	// Длительность от расстояния: длинный недолёт возвращается быстро,
	// короткий щёлкает на место; EaseOut — старт в такт пальцу
	CGFloat dy = self.center.y - self.homeY;
	CGFloat dur = MIN(MAX(0.10 + fabs(dy) / 900.0, 0.14), 0.30);
	[UIView animateWithDuration:dur
	                      delay:0.0
	                    options:UIViewAnimationOptionCurveEaseOut
	                 animations:^{
		self.alpha = 1.0; // мог таять после тапа по камере
		self.center = CGPointMake(self.homeX, self.homeY);
		[self resetCameraHint];
	}
	                 completion:NULL];
}

#pragma mark Минутный таймер часов

- (void)startClockUpdates {
	if (_clockSource != nil) return;
	dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	// первый тик — на границе ближайшей минуты, дальше раз в минуту
	NSTimeInterval intoMinute = fmod([NSDate date].timeIntervalSince1970, 60.0);
	dispatch_source_set_timer(source,
	    dispatch_time(DISPATCH_TIME_NOW, (int64_t)((60.0 - intoMinute) * NSEC_PER_SEC)),
	    60 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);
	dispatch_source_set_event_handler(source, ^{
		[self refreshContent];
	});
	dispatch_resume(source);
	_clockSource = source;
}

- (void)stopClockUpdates {
	if (_clockSource != nil) {
		dispatch_source_cancel(_clockSource);
		_clockSource = nil;
	}
}

- (void)dealloc {
	[self stopClockUpdates];
}

@end
