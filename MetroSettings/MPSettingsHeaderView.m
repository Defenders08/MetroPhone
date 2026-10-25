#import "MPSettingsHeaderView.h"


@implementation MPSettingsHeaderView {
    UILabel *_small;
    UILabel *_big;
    UILabel *_chevron;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];

        _big = [[UILabel alloc] initWithFrame:CGRectZero];
        _big.font = [MPMetroStyle lightFont:52.0f];
        _big.textColor = [UIColor whiteColor];
        _big.backgroundColor = [UIColor clearColor];
        _big.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _big.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_big];

        _chevron = [[UILabel alloc] initWithFrame:CGRectZero];
        _chevron.text = @"\u2039";                       // ‹
        _chevron.font = [MPMetroStyle lightFont:40.0f];
        _chevron.textColor = [MPMetroStyle accentColor];
        _chevron.backgroundColor = [UIColor clearColor];
        _chevron.hidden = YES;
        [self addSubview:_chevron];

        // вся шапка — кнопка «Назад» (обработчик ставит хост)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(headerTapped)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)headerTapped {
    if (self.backTapped != nil) self.backTapped();
}

- (void)setPageTitle:(NSString *)pageTitle {
    _pageTitle = [pageTitle lowercaseStringWithLocale:[NSLocale currentLocale]];
    _big.text = _pageTitle;
    [self setNeedsLayout];
    [self shrinkTitleFont];
}

// ручной подбор размера: adjustsFontSizeToFitWidth на iOS 6 ненадёжен для
// динамически меняющегося текста — ужимаем от 52 до 30 pt по фактической ширине
- (void)shrinkTitleFont {
    CGFloat w = self.bounds.size.width;
    if (w < 10.0f) w = 320.0f;                 // до первого layoutSubviews
    w -= [self bigLeftOffset] + 10.0f;
    CGFloat size = 52.0f;
    while (size > 30.0f) {
        CGSize fit = [_pageTitle sizeWithFont:[MPMetroStyle lightFont:size]
                            constrainedToSize:CGSizeMake(w, 10000.0f)
                                lineBreakMode:NSLineBreakByClipping];
        if (fit.width <= w + 1.0f) break;
        size -= 2.0f;
    }
    UIFont *f = [MPMetroStyle lightFont:size];
    if (![_big.font isEqual:f]) {
        _big.font = f;
        [_big setNeedsDisplay];
    }
}

- (CGFloat)bigLeftOffset {
    return _chevron.hidden ? 14.0f : 38.0f;
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    return 76.0f;    // только огромный заголовок + отступы
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;

    CGFloat bigTop = 4.0f;
    CGFloat bigH = [MPSettingsHeaderView heightForWidth:w] - bigTop - 6.0f;

    if (self.showsBackChevron) {
        _chevron.hidden = NO;
        _chevron.frame = CGRectMake(4.0f, bigTop + 2.0f, 28.0f, bigH);
        _big.frame = CGRectMake([self bigLeftOffset], bigTop, w - [self bigLeftOffset], bigH);
    } else {
        _chevron.hidden = YES;
        _big.frame = CGRectMake([self bigLeftOffset], bigTop, w - [self bigLeftOffset], bigH);
    }
    [self shrinkTitleFont];
}

@end
