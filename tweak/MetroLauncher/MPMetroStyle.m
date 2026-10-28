#import "MPMetroStyle.h"
#import <stdio.h>
#import <sys/stat.h>
#import <sys/time.h>

#define MP_LOG_PATH "/var/mobile/Library/Preferences/metrophone.log"

// Свои горячие пути больше не пишут в syslog: на iOS 6 каждый NSLog уходит
// через ASL-демон и в хуках иконок стоит миллисекунды. Файл-журнал остаётся
// всегда, а дублирование в syslog включается ключом verboseLog в настройках.
static BOOL MPSyslogWanted(void) {
    static BOOL wanted = NO;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last > 1.0) {              // читаем настройку не чаще раза в секунду
        last = now;
        CFTypeRef v = CFPreferencesCopyAppValue(CFSTR("verboseLog"), CFSTR("ru.ash.metrophone"));
        if (v != NULL) {
            if (CFGetTypeID(v) == CFBooleanGetTypeID()) wanted = CFBooleanGetValue((CFBooleanRef)v);
            else if (CFGetTypeID(v) == CFNumberGetTypeID()) wanted = [(__bridge NSNumber *)v boolValue];
            CFRelease(v);
        } else {
            wanted = NO;
        }
    }
    return wanted;
}

void MPLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm parts;
    localtime_r(&tv.tv_sec, &parts);
    char stamp[32];
    strftime(stamp, sizeof(stamp), "%H:%M:%S", &parts);

    FILE *f = fopen(MP_LOG_PATH, "a");
    if (f != NULL) {
        fprintf(f, "[%s.%03d] %s\n", stamp, (int)(tv.tv_usec / 1000), line.UTF8String);
        fclose(f);
    }
    if (MPSyslogWanted()) NSLog(@"[MetroPhone] %@", line);
}

static UIWindow *MPHostWindow = nil;

void MPSetHostWindow(UIWindow *window) {
    if (MPHostWindow == nil && window != nil) {
        MPHostWindow = window;
        MPLog(@"окно SpringBoard захвачено: %@", NSStringFromClass([window class]));
    }
}

UIWindow *MPSharedHostWindow(void) {
    return MPHostWindow;
}

// Состояние настроек. Читается/пишется только с главного потока (UI-слой).
static BOOL       MPStyleLoaded    = NO;
static BOOL       MPStyleEnabled   = YES;
static BOOL       MPStyleUppercase = YES;
static NSInteger  MPStyleTileStyle = 1;
static NSInteger  MPStyleColumns   = 4;
static UIColor   *MPStyleAccent    = nil;

static UIColor *MPHexColor(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0f
                           green:((hex >> 8) & 0xFF) / 255.0f
                            blue:(hex & 0xFF) / 255.0f
                           alpha:1.0f];
}

// «1BA1E2» / «#1ba1e2» → цвет; nil, если строка не HEX
static UIColor *MPColorFromHexString(NSString *hex) {
    if (hex.length == 0) return nil;
    NSString *s = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (s.length != 6) return nil;
    NSScanner *sc = [NSScanner scannerWithString:s];
    unsigned v = 0;
    if (![sc scanHexInt:&v]) return nil;
    return MPHexColor((uint32_t)v);
}

// Палитра акцентов (раздел 5.2)
static UIColor *MPAccentForName(NSString *name) {
    static NSDictionary *palette = nil;
    if (palette == nil) {
        palette = @{ @"blue":    @(0x1BA1E2),
                     @"purple":  @(0xA200FF),
                     @"magenta": @(0xD80073),
                     @"green":   @(0x008A00),
                     @"lime":    @(0xA4C400),
                     @"orange":  @(0xF09609),
                     @"red":     @(0xE51400),
                     @"teal":    @(0x00ABA9) };
    }
    NSNumber *n = (name.length > 0) ? [palette objectForKey:name] : nil;
    return MPHexColor(n ? (uint32_t)[n unsignedIntValue] : 0x1BA1E2);
}

@implementation MPMetroStyle

#pragma mark - Настройки

+ (void)reloadPreferences {
    CFStringRef domain = CFSTR("ru.ash.metrophone");
    CFPreferencesAppSynchronize(domain);

    BOOL enabled = YES;
    id v = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("enabled"), domain);
    if ([v respondsToSelector:@selector(boolValue)]) enabled = [v boolValue];

    // По умолчанию плитки акцентные (как в WP 8.1); «Тёмные» — осознанный выбор
    // Режим «тёмные плитки» убран: плитки всегда акцентные (WP 8.1)
    NSInteger tileStyle = 1;

    NSString *accent = nil;
    v = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("accent"), domain);
    if ([v isKindOfClass:[NSString class]]) accent = v;

    // Регистр подписей — общий ключ темы (подписи иконок и панелей уже его читают)
    BOOL uppercase = YES;
    v = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("uppercaseLabels"), domain);
    if ([v respondsToSelector:@selector(boolValue)]) uppercase = [v boolValue];

    // Мелкая сетка: 6 колонок вместо 4 — плитки «ещё меньше»
    BOOL smallTiles = NO;
    v = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("smallTiles"), domain);
    if ([v respondsToSelector:@selector(boolValue)]) smallTiles = [v boolValue];

    MPStyleEnabled   = enabled;
    MPStyleUppercase = uppercase;
    MPStyleTileStyle = tileStyle;
    MPStyleColumns   = smallTiles ? 6 : 4;
    // Новый ключ — HEX из сетки «Цвета» (страница WP 8.1). Если не задан
    // (старые установки) — имя из старого списка, иначе синий по умолчанию.
    NSString *hexStr = nil;
    v = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("accentHex"), domain);
    if ([v isKindOfClass:[NSString class]]) hexStr = v;
    MPStyleAccent = nil;
    if (hexStr.length > 0) MPStyleAccent = MPColorFromHexString(hexStr);
    if (MPStyleAccent == nil) MPStyleAccent = MPAccentForName(accent);
    MPStyleLoaded    = YES;
}

+ (void)ensureLoaded {
    if (!MPStyleLoaded) [self reloadPreferences];
}

+ (BOOL)isEnabled {
    [self ensureLoaded];
    return MPStyleEnabled;
}

+ (NSInteger)tileStyle {
    [self ensureLoaded];
    return MPStyleTileStyle;
}

+ (BOOL)uppercaseLabels {
    [self ensureLoaded];
    return MPStyleUppercase;
}

+ (NSInteger)columns {
    [self ensureLoaded];
    return MPStyleColumns;
}

#pragma mark - Цвета

+ (UIColor *)accentColor {
    [self ensureLoaded];
    return MPStyleAccent;
}

+ (UIColor *)tileColor {
    [self ensureLoaded];
    if (MPStyleTileStyle == 1) return MPStyleAccent;
    return [UIColor colorWithWhite:0.12f alpha:1.0f];
}

+ (UIColor *)badgeColor {
    return MPHexColor(0xE51400);
}

+ (UIColor *)placeholderColor {
    return [UIColor colorWithWhite:0.30f alpha:1.0f];
}

#pragma mark - Шрифты (кэш; прямой fontWithName: вне этого хелпера не использовать)

+ (UIFont *)fontWithNames:(NSArray *)names size:(CGFloat)size {
    static NSMutableDictionary *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });

    NSString *key = [NSString stringWithFormat:@"%@|%.1f", [names objectAtIndex:0], (double)size];
    UIFont *font = nil;
    @synchronized (cache) { font = [cache objectForKey:key]; }
    if (font == nil) {
        for (NSString *name in names) {
            font = [UIFont fontWithName:name size:size];
            if (font != nil) break;
        }
        if (font == nil) font = [UIFont systemFontOfSize:size];   // fallback
        @synchronized (cache) { [cache setObject:font forKey:key]; }
    }
    return font;
}

// На iOS 6 шрифта HelveticaNeue-Thin может не быть — тогда берём Light, затем системный.
+ (UIFont *)thinFont:(CGFloat)size {
    return [self fontWithNames:@[@"HelveticaNeue-Thin", @"HelveticaNeue-Light"] size:size];
}
+ (UIFont *)lightFont:(CGFloat)size {
    return [self fontWithNames:@[@"HelveticaNeue-Light"] size:size];
}
+ (UIFont *)regularFont:(CGFloat)size {
    return [self fontWithNames:@[@"HelveticaNeue"] size:size];
}
+ (UIFont *)mediumFont:(CGFloat)size {
    return [self fontWithNames:@[@"HelveticaNeue-Medium"] size:size];
}

#pragma mark - Метрики

// Базовая ячейка: cell = (containerWidth − (cols−1)·gap) / cols
+ (CGFloat)cellForContainerWidth:(CGFloat)width {
    NSInteger cols = [self columns];
    return (width - (CGFloat)(cols - 1) * MPMetroGap) / (CGFloat)cols;
}

// Размеры по пролётам сетки: Small = cell×cell; Medium = 2×2 ячейки; Half (виджеты) = 2×1;
// Wide = во всю ширину сетки, высотой с Medium. Пролёты даёт MPLayoutModel.
+ (CGSize)tilePixelSize:(MPTileSize)size containerWidth:(CGFloat)width {
    CGFloat cell = [self cellForContainerWidth:width];
    CGFloat g = MPMetroGap;
    NSUInteger sx = MPTileSpanX(size, [self columns]), sy = MPTileSpanY(size);
    CGFloat w = (CGFloat)sx * cell + (CGFloat)(sx - 1) * g;
    CGFloat h = (CGFloat)sy * cell + (CGFloat)(sy - 1) * g;
    return CGSizeMake(w, h);
}

+ (CGFloat)statusBarInset {
    CGFloat y = [UIScreen mainScreen].applicationFrame.origin.y;
    if (y < 0.0f || y > 44.0f) y = 20.0f;
    return y;
}

@end
