#import "MPIconPickerView.h"
#import "MPIconTheme.h"
#import "MPTileView.h"
#import "MPMetroStyle.h"

// Серийная очередь декодирования миниатюр: как и для плиток, параллельные
// декодирования PNG прибивают SpringBoard по памяти
static dispatch_queue_t MPThumbQueue(void) {
    static dispatch_queue_t q = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("ru.ash.metrophone.iconpicker", DISPATCH_QUEUE_SERIAL); });
    return q;
}

// Миниатюра «квадрат с вписанной картинкой» — кнопки пикера держат именно её:
// декодированные 256px-оригиналы на весь список уложили бы iPhone 4 по памяти.
static UIImage *MPThumbImage(UIImage *src, CGFloat px) {
    if (src == nil) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(px, px), NO, 0.0);
    CGFloat s = MIN(px / src.size.width, px / src.size.height);
    CGSize d = CGSizeMake(src.size.width * s, src.size.height * s);
    [src drawInRect:CGRectMake(floorf((px - d.width) / 2.0f), floorf((px - d.height) / 2.0f), d.width, d.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

@implementation MPIconPickerView {
    NSString   *_bundleID;
    NSArray    *_allChoices;   // выбор (формат MPIconTheme) по индексу = кнопка.tag
    NSMutableArray *_buttons;
    UIScrollView *_scroll;
}

+ (void)showFromView:(UIView *)parent forBundleID:(NSString *)bundleID appName:(NSString *)appName {
    if (bundleID.length == 0 || parent == nil) return;
    for (UIView *sub in parent.subviews) {
        if ([sub isKindOfClass:[MPIconPickerView class]]) [sub removeFromSuperview];   // один пикер за раз
    }
    MPIconPickerView *v = [[MPIconPickerView alloc] initWithFrame:parent.bounds bundleID:bundleID appName:appName ?: @""];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.alpha = 0.0f;
    [parent addSubview:v];
    [UIView animateWithDuration:0.22 animations:^{ v.alpha = 1.0f; }];
}

- (id)initWithFrame:(CGRect)frame bundleID:(NSString *)bundleID appName:(NSString *)appName {
    self = [super initWithFrame:frame];
    if (self) {
        _bundleID = [bundleID copy];
        _buttons  = [NSMutableArray array];
        self.backgroundColor = [UIColor blackColor];

        CGFloat w = frame.size.width;

        // Шапка: «назад» + заголовок в стиле WP (мелкий надзаголовок, крупное имя)
        UIButton *back = [UIButton buttonWithType:UIButtonTypeCustom];
        back.frame = CGRectMake(0.0f, 0.0f, 48.0f, 56.0f);
        [back setTitle:@"‹" forState:UIControlStateNormal];
        [back setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        back.titleLabel.font = [MPMetroStyle lightFont:30.0f];
        [back addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:back];

        UILabel *cap = [[UILabel alloc] initWithFrame:CGRectMake(52.0f, 6.0f, w - 64.0f, 16.0f)];
        cap.backgroundColor = [UIColor clearColor];
        cap.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
        cap.font = [MPMetroStyle regularFont:13.0f];
        cap.text = @"смена иконки";
        [self addSubview:cap];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(52.0f, 20.0f, w - 64.0f, 32.0f)];
        title.backgroundColor = [UIColor clearColor];
        title.textColor = [MPMetroStyle accentColor];
        title.font = [MPMetroStyle thinFont:22.0f];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        title.text = appName;
        [self addSubview:title];

        _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0.0f, 56.0f, w, frame.size.height - 56.0f)];
        _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scroll.backgroundColor = [UIColor blackColor];
        _scroll.alwaysBounceVertical = YES;
        [self addSubview:_scroll];

        NSArray *builtin = [MPIconTheme builtinChoices];
        NSArray *user    = [MPIconTheme userChoices];

        CGFloat y = 10.0f;
        y = [self addSection:@"встроенные" choices:builtin startY:y];
        if (user.count > 0) y = [self addSection:@"мои" choices:user startY:y];
        _scroll.contentSize = CGSizeMake(w, y + 16.0f);

        [self refreshSelection];
    }
    return self;
}

// Метка секции + сетка 4 в ряд; возвращает новую нижнюю координату
- (CGFloat)addSection:(NSString *)caption choices:(NSArray *)choices startY:(CGFloat)y {
    CGFloat w = _scroll.bounds.size.width;
    if (choices.count == 0) return y;

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12.0f, y, w - 24.0f, 26.0f)];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [MPMetroStyle accentColor];
    l.font = [MPMetroStyle thinFont:20.0f];
    l.text = caption;
    [_scroll addSubview:l];
    y += 32.0f;

    CGFloat gap = 6.0f;
    NSInteger cols = 4;
    CGFloat cell = floorf((w - gap * (cols + 1)) / cols);
    CGFloat thumbPx = cell * 2.0f;   // @2x экрана — миниатюра не мылится на плитке

    NSInteger base = _allChoices.count;
    NSMutableArray *sectionChoices = [NSMutableArray arrayWithCapacity:choices.count];
    [sectionChoices addObjectsFromArray:choices];
    _allChoices = _allChoices == nil ? sectionChoices : [_allChoices arrayByAddingObjectsFromArray:sectionChoices];

    for (NSInteger i = 0; i < (NSInteger)choices.count; i++) {
        NSInteger r = i / cols, c = i % cols;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(gap + c * (cell + gap), y + r * (cell + gap), cell, cell);
        b.backgroundColor = [MPMetroStyle tileColor];
        b.tag = base + i;
        b.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [b addTarget:self action:@selector(iconTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_scroll addSubview:b];
        [_buttons addObject:b];

        NSString *choice = [choices objectAtIndex:i];
        dispatch_async(MPThumbQueue(), ^{
            UIImage *img = MPThumbImage([MPIconTheme imageForChoice:choice], thumbPx);
            if (img == nil) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [b setImage:img forState:UIControlStateNormal];
            });
        });
    }
    NSInteger rows = ((NSInteger)choices.count + cols - 1) / cols;
    return y + rows * (cell + gap) + 10.0f;
}

- (void)iconTapped:(UIButton *)sender {
    NSString *choice = [_allChoices objectAtIndex:sender.tag];
    [MPIconTheme setCustomChoice:choice forBundleID:_bundleID];
    [MPIconTheme notifyIconsChanged];
    [MPIconLoader clearCache];
    // Плитки и список перечитают иконки по общему событию «список изменился»
    [[NSNotificationCenter defaultCenter] postNotificationName:MPAppsChangedNotification object:nil];
    [self refreshSelection];
}

- (void)refreshSelection {
    NSString *current = [MPIconTheme customChoiceForBundleID:_bundleID];
    UIColor *accent = [MPMetroStyle accentColor];
    for (UIButton *b in _buttons) {
        NSString *choice = [_allChoices objectAtIndex:b.tag];
        BOOL sel = (choice != nil && [choice isEqualToString:current]);
        b.layer.borderWidth = sel ? 2.0f : 0.0f;
        b.layer.borderColor = sel ? accent.CGColor : NULL;
    }
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 0.0f; }
                     completion:^(BOOL finished) { [self removeFromSuperview]; }];
}

@end
