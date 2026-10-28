#import "MPIconTheme.h"
#import "MetroPhoneCommon.h"
#include <CoreFoundation/CoreFoundation.h>

// Ресурсы темы ставятся пакетом рядом со шрифтом (layout/... в репозитории)
static NSString *MPIconsDir(void)   { return @"/Library/Application Support/MetroPhone/icons"; }
static NSString *MPGlyphsDir(void)  { return @"/Library/Application Support/MetroPhone/glyphs"; }
static NSString *MPMapPath(void)    { return [MPIconsDir() stringByAppendingPathComponent:@"map.plist"]; }

// Пользовательский слой
static NSString *MPChoicesPath(void) { return @"/var/mobile/Library/Preferences/metrophone-icons.plist"; }

@implementation MPIconTheme

+ (NSString *)userIconsDirectory {
    return @"/var/mobile/Library/MetroPhone/UserIcons";
}

#pragma mark - Настройки (читаются на лету, как MPFlag в Tweak.xm)

static BOOL MPThemeFlag(NSString *key, BOOL def) {
    CFTypeRef v = CFPreferencesCopyAppValue((CFStringRef)key, CFSTR(MP_PREFS_DOMAIN));
    if (v == NULL) return def;
    BOOL result = def;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) result = CFBooleanGetValue((CFBooleanRef)v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) result = [(__bridge NSNumber *)v boolValue];
    CFRelease(v);
    return result;
}

#pragma mark - Кэши

static NSCache *MPThemeImgCache(void) {
    static NSCache *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 60;   // iPhone 4: декодированные 256px-квадраты по ~256 КБ
    });
    return cache;
}

// Встроенный маппинг bundleID → выбор ("wp:..."/"glyph:..."); не меняется в рантайме
static NSDictionary *MPBuiltinMap(void) {
    static NSDictionary *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = [NSDictionary dictionaryWithContentsOfFile:MPMapPath()] ?: @{};
    });
    return map;
}

// Пользовательский выбор: пере читаем только по Darwin-событию (файл крошечный,
// но читать его на каждое обновление ячейки не нужно)
static volatile BOOL MPChoicesDirty = YES;

static NSDictionary *MPUserChoices(void) {
    static NSDictionary *choices = nil;
    if (MPChoicesDirty) {
        MPChoicesDirty = NO;
        choices = [NSDictionary dictionaryWithContentsOfFile:MPChoicesPath()] ?: @{};
    }
    return choices;
}

#pragma mark - Папка пользовательских иконок

static void MPEnsureUserDir(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = [MPIconTheme userIconsDirectory];
        if ([[NSFileManager defaultManager] createDirectoryAtPath:dir
                                      withIntermediateDirectories:YES attributes:nil error:NULL]) {
            NSString *readme = [dir stringByAppendingPathComponent:@"README.txt"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:readme]) {
                NSString *text =
                    @"MetroPhone — пользовательские иконки.\n\n"
                    @"Положите сюда PNG-файлы (квадратные, желательно 256x256),\n"
                    @"затем в лаунчере: долгое нажатие на приложении → «сменить иконку».\n"
                    @"Имена файлов произвольные.\n";
                [text writeToFile:readme atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        }
    });
}

#pragma mark - Резолвинг

+ (UIImage *)imageForChoice:(NSString *)choice {
    if (choice.length == 0) return nil;

    NSString *name = nil, *dir = nil;
    if ([choice hasPrefix:@"wp:"])         { name = [choice substringFromIndex:3]; dir = MPIconsDir(); }
    else if ([choice hasPrefix:@"glyph:"]) { name = [choice substringFromIndex:6]; dir = MPGlyphsDir(); }
    else if ([choice hasPrefix:@"user:"])  { name = [choice substringFromIndex:5]; dir = [self userIconsDirectory]; }
    if (name.length == 0 || dir == nil) return nil;
    if ([name pathExtension].length == 0) name = [name stringByAppendingPathExtension:@"png"];
    // защита от «../» в значении, пришедшем из файла
    if ([name rangeOfString:@"/"].location != NSNotFound) return nil;

    NSString *path = [dir stringByAppendingPathComponent:name];
    UIImage *cached = [MPThemeImgCache() objectForKey:path];
    if (cached != nil) return cached;

    UIImage *img = [UIImage imageWithContentsOfFile:path];
    [MPThemeImgCache() setObject:(img ?: (id)[NSNull null]) forKey:path];
    return img;
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID fill:(BOOL *)isFill {
    if (bundleID.length == 0) return nil;
    MPEnsureUserDir();

    // 1) пользовательский выбор (файл мог исчезнуть — тогда просто идём ниже)
    NSString *choice = [MPUserChoices() objectForKey:bundleID];
    if (choice != nil) {
        UIImage *img = [self imageForChoice:choice];
        if (img != nil) {
            if (isFill) *isFill = [choice hasPrefix:@"user:"];
            return img;
        }
    }

    // 2) встроенная WP-тема: wp-иконки (квадратные 256px) — на всю плитку, заливка
    // без искажений; глифы (белые силуэты 48px с прозрачностью) — «60 % по центру»
    if (MPThemeFlag(MPKeyWPIcons, YES)) {
        NSString *mapped = [MPBuiltinMap() objectForKey:bundleID];
        UIImage *img = mapped != nil ? [self imageForChoice:mapped] : nil;
        if (img != nil) {
            if (isFill) *isFill = [mapped hasPrefix:@"wp:"];
            return img;
        }
    }

    // 3) темы нет: оригинальная иконка, для fill-режима — на всю плитку
    if (isFill) *isFill = MPThemeFlag(MPKeyFillSideIcons, YES);
    return nil;
}

#pragma mark - Пользовательский выбор

+ (NSString *)customChoiceForBundleID:(NSString *)bundleID {
    return [MPUserChoices() objectForKey:bundleID];
}

+ (BOOL)hasCustomChoiceForBundleID:(NSString *)bundleID {
    return [MPUserChoices() objectForKey:bundleID] != nil;
}

+ (void)setCustomChoice:(NSString *)choice forBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return;
    MPEnsureUserDir();
    NSMutableDictionary *choices = [NSMutableDictionary dictionaryWithDictionary:MPUserChoices()];
    if (choice.length == 0) [choices removeObjectForKey:bundleID];
    else [choices setObject:choice forKey:bundleID];
    [choices writeToFile:MPChoicesPath() atomically:YES];
    MPChoicesDirty = YES;
    [MPThemeImgCache() removeAllObjects];
}

+ (void)removeCustomChoiceForBundleID:(NSString *)bundleID {
    [self setCustomChoice:nil forBundleID:bundleID];
}

#pragma mark - Списки для пикера

+ (NSArray *)builtinChoices {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:MPIconsDir() error:NULL]) {
        if ([f hasSuffix:@".png"]) [out addObject:[@"wp:" stringByAppendingString:[f stringByDeletingPathExtension]]];
    }
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:MPGlyphsDir() error:NULL]) {
        if ([f hasSuffix:@".png"]) [out addObject:[@"glyph:" stringByAppendingString:[f stringByDeletingPathExtension]]];
    }
    return out;
}

+ (NSArray *)userChoices {
    NSMutableArray *out = [NSMutableArray array];
    MPEnsureUserDir();
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self userIconsDirectory] error:NULL]) {
        if ([f hasSuffix:@".png"]) [out addObject:[@"user:" stringByAppendingString:f]];
    }
    return out;
}

#pragma mark - Событие «иконки изменились»

+ (void)notifyIconsChanged {
    MPChoicesDirty = YES;
    [MPThemeImgCache() removeAllObjects];
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(MP_ICONS_CHANGED_NOTIFICATION), NULL, NULL, YES);
}

@end
