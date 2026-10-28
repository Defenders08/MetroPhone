#import "MPLiveTileSizeView.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString * const MPSizeDomain  = @"ru.ash.metrophone";
static NSString * const MPSizeChanged = @"ru.ash.metrophone.livetiles-changed";

// Встроенные виджеты — тот же список, что регистрирует MPLiveTileCenter
// (включая тестовые; перед релизом тестовые строки убрать).
// Ключи: liveTile.<id>.size (0 = 1×1, 1 = 2×1, 2 = 2×2).
#define MPSizeWidgetCount 5
static NSString * const MPSizeWidgetID[MPSizeWidgetCount] = {
    @"mp.widget.clock", @"mp.widget.battery", @"mp.widget.nowplaying",
    @"mp.widget.test.counter", @"mp.widget.test.states"
};
static NSString * const MPSizeWidgetTitle[MPSizeWidgetCount] = {
    @"Часы", @"Батарея", @"Сейчас играет", @"Тест: счётчик", @"Тест: состояния"
};
static NSString * const MPSizeNames[3] = { @"1×1", @"2×1", @"2×2" };

static NSString *MPSizeKey(NSString *tileID) {
    return [NSString stringWithFormat:@"liveTile.%@.size", tileID];
}

static NSInteger MPSizeCurrent(NSString *tileID) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)MPSizeKey(tileID), (__bridge CFStringRef)MPSizeDomain));
    if ([v isKindOfClass:[NSNumber class]]) {
        NSInteger n = [(NSNumber *)v integerValue];
        if (n >= 0 && n <= 2) return n;
    }
    // по умолчанию: часы и тест-счётчик — 2×2, остальные — 2×1 (как +defaultSize)
    return ([tileID isEqualToString:@"mp.widget.clock"] ||
            [tileID isEqualToString:@"mp.widget.test.counter"]) ? 2 : 1;
}

static void MPSizeStore(NSString *tileID, NSInteger size) {
    CFPreferencesSetAppValue((__bridge CFStringRef)MPSizeKey(tileID),
                             (__bridge CFPropertyListRef)[NSNumber numberWithInteger:size],
                             (__bridge CFStringRef)MPSizeDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MPSizeDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)MPSizeChanged, NULL, NULL, TRUE);
}

@implementation MPLiveTileSizeView {
    NSMutableArray *_values;       // UILabel со значением размера каждой строки
    NSMutableArray *_separators;   // линии между строками
}

+ (CGFloat)rowHeight { return 44.0f; }

+ (CGFloat)heightForWidth:(CGFloat)width {
    return (CGFloat)MPSizeWidgetCount * [self rowHeight];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.autoresizesSubviews = NO;
        _values = [[NSMutableArray alloc] init];
        _separators = [[NSMutableArray alloc] init];

        CGFloat rowH = [MPLiveTileSizeView rowHeight];
        for (NSInteger i = 0; i < MPSizeWidgetCount; i++) {
            CGFloat y = (CGFloat)i * rowH;

            UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, y, 150.0f, rowH)];
            title.text = MPSizeWidgetTitle[i];
            title.font = [UIFont systemFontOfSize:17.0f];
            title.textColor = [UIColor whiteColor];
            title.backgroundColor = [UIColor clearColor];
            title.userInteractionEnabled = NO;
            [self addSubview:title];

            // значения по центру правого края, до шеврона
            UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, y, 70.0f, rowH)];
            value.textAlignment = NSTextAlignmentRight;
            value.font = [UIFont systemFontOfSize:17.0f];
            value.textColor = [UIColor whiteColor];
            value.backgroundColor = [UIColor clearColor];
            value.userInteractionEnabled = NO;
            value.tag = 100 + (NSInteger)i;
            [self addSubview:value];
            [_values addObject:value];

            UILabel *chevron = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, y, 30.0f, rowH)];
            chevron.text = @"›";
            chevron.font = [UIFont systemFontOfSize:20.0f];
            chevron.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
            chevron.backgroundColor = [UIColor clearColor];
            chevron.userInteractionEnabled = NO;
            chevron.tag = 200 + (NSInteger)i;
            [self addSubview:chevron];

            // разделитель строк (кроме последней)
            if (i < MPSizeWidgetCount - 1) {
                UIView *sep = [[UIView alloc] initWithFrame:CGRectZero];
                sep.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.15f];
                sep.userInteractionEnabled = NO;
                [self addSubview:sep];
                [_separators addObject:sep];
            }
        }
        [self layoutSubviews];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat rowH = [MPLiveTileSizeView rowHeight];
    for (NSInteger i = 0; i < MPSizeWidgetCount; i++) {
        UILabel *value = [_values objectAtIndex:i];
        UILabel *chevron = [self viewWithTag:200 + (NSInteger)i];
        value.frame = CGRectMake(w - 30.0f - 70.0f - 6.0f, (CGFloat)i * rowH, 70.0f, rowH);
        chevron.frame = CGRectMake(w - 30.0f, (CGFloat)i * rowH, 30.0f, rowH);
        if (i < (NSInteger)_separators.count) {
            UIView *sep = [_separators objectAtIndex:i];
            sep.frame = CGRectMake(16.0f, (CGFloat)(i + 1) * rowH - 0.5f, w - 16.0f, 0.5f);
        }
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint p = [touch locationInView:self];
    CGFloat rowH = [MPLiveTileSizeView rowHeight];
    NSInteger row = (NSInteger)floorf(p.y / rowH);
    if (row < 0 || row >= MPSizeWidgetCount) return;

    NSString *tileID = MPSizeWidgetID[row];
    NSInteger size = MPSizeCurrent(tileID);
    size = (size + 1) % 3;
    MPSizeStore(tileID, size);

    UILabel *value = [_values objectAtIndex:row];
    value.text = MPSizeNames[size];
}

// Свежие значения при каждом показе страницы
- (void)refreshValues {
    for (NSInteger i = 0; i < MPSizeWidgetCount; i++) {
        UILabel *value = [_values objectAtIndex:i];
        value.text = MPSizeNames[MPSizeCurrent(MPSizeWidgetID[i])];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window != nil) [self refreshValues];
}

@end
