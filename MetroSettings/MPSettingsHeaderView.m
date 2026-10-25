#import "MPSettingsHeaderView.h"

static const CGFloat MPSetHInset = 16.0f;

@implementation MPSettingsHeaderView {
    UILabel *_small;
    UILabel *_big;
    UILabel *_chevron;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];

        _small = [[UILabel alloc] initWithFrame:CGRectZero];
        _small.font = [MPMetroStyle mediumFont:13.0f];
        _small.textColor = [UIColor whiteColor];
        _small.backgroundColor = [UIColor clearColor];
        _small.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self addSubview:_small];

        _big = [[UILabel alloc] initWithFrame:CGRectZero];
        _big.font = [MPMetroStyle lightFont:52.0f];
        _big.textColor = [UIColor whiteColor];
        _big.backgroundColor = [UIColor clearColor];
        _big.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        // длинные названия ужимаются до 30 pt, дальше обрезаются правым краем (как в WP)
        _big.adjustsFontSizeToFitWidth = YES;
        _big.minimumFontSize = 30.0f;
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

- (void)setSmallTitle:(NSString *)smallTitle {
    _smallTitle = [smallTitle uppercaseStringWithLocale:[NSLocale currentLocale]];
    _small.text = _smallTitle;
}

- (void)setPageTitle:(NSString *)pageTitle {
    _pageTitle = [pageTitle lowercaseStringWithLocale:[NSLocale currentLocale]];
    _big.text = _pageTitle;
    [self setNeedsLayout];
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    return 100.0f;   // малый 13 + огромный 52 + отступы — по референсу WP 8.1
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;

    _small.frame = CGRectMake(MPSetHInset, 8.0f, w - MPSetHInset - 8.0f, 18.0f);

    CGFloat bigTop = CGRectGetMaxY(_small.frame) + 4.0f;
    CGFloat bigH = [MPSettingsHeaderView heightForWidth:w] - bigTop - 6.0f;

    if (self.showsBackChevron) {
        _chevron.hidden = NO;
        _chevron.frame = CGRectMake(6.0f, bigTop + 2.0f, 26.0f, bigH);
        _big.frame = CGRectMake(34.0f, bigTop, w - 36.0f, bigH);
    } else {
        _chevron.hidden = YES;
        _big.frame = CGRectMake(MPSetHInset - 2.0f, bigTop, w - MPSetHInset - 4.0f, bigH);
    }
}

@end
