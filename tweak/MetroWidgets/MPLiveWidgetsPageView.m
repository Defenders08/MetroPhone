#import "MPLiveWidgetsPageView.h"
#import "MPLiveTile.h"
#import "MPLiveTileView.h"
#import "MPLiveTileCenter.h"
#import "MPLiveTileRegistry.h"
#import "MetroLauncher/MPLayoutModel.h"
#import "MetroLauncher/MPMetroStyle.h"

@implementation MPLiveWidgetsPageView {
    UIScrollView    *_scrollView;
    NSMutableArray  *_tiles;        // MPLiveTileView
    CGFloat          _builtWidth;   // ширина, под которую страница собрана
    BOOL             _forceRebuild; // состав/размеры изменились — пересобрать обязательно

    UITapGestureRecognizer          *_tap;
    UILongPressGestureRecognizer   *_longPress;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        _topInset = 20.0f;
        _tiles = [NSMutableArray array];

        _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scrollView.backgroundColor = [UIColor blackColor];
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.alwaysBounceVertical = YES;
        _scrollView.directionalLockEnabled = YES;
        _scrollView.multipleTouchEnabled = NO;
        _scrollView.delaysContentTouches = NO;   // тап по виджету — без задержки
        [self addSubview:_scrollView];

        _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGesture:)];
        [_scrollView addGestureRecognizer:_tap];
        _longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longGesture:)];
        _longPress.minimumPressDuration = 0.6;
        [_scrollView addGestureRecognizer:_longPress];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(widgetsChanged:)
                                                     name:MPLiveWidgetsChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setTopInset:(CGFloat)topInset {
    _topInset = topInset;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _scrollView.frame = CGRectMake(0.0f, _topInset, w, h - _topInset);
    [self rebuild];   // сам решит: ширина та же и не было изменений — пропустит
}

#pragma mark - Сборка

- (void)ensureLoaded {
    _forceRebuild = YES;
    [self rebuild];
}

// Укладка «первое подходящее место» — та же сетка, что у плиток приложений,
// но локальная: страница виджетов не участвует в раскладке стартового экрана.
- (void)rebuild {
    CGFloat W = _scrollView.bounds.size.width;
    if (W < 8.0f) return;                     // кадр ещё не посчитан — пересборка в layoutSubviews
    if (_builtWidth == W && !_forceRebuild) return;
    _builtWidth = W;
    _forceRebuild = NO;

    for (UIView *v in _tiles) [v removeFromSuperview];
    [_tiles removeAllObjects];

    NSInteger cols = [MPMetroStyle columns];
    CGFloat cell = [MPMetroStyle cellForContainerWidth:W];
    CGFloat g = MPMetroGap;

    MPLiveTileCenter *center = [MPLiveTileCenter sharedCenter];

    NSMutableArray *rows = [NSMutableArray array];   // ряды занятости, байт на ячейку
    CGFloat maxY = 0.0f;

    for (NSString *tileID in [center enabledWidgetIDs]) {
        id<MPLiveTileProvider> p = [MPLiveTileRegistry providerForID:tileID];
        if (p == nil) continue;
        MPTileSize gridSize = MPLiveGridSize([center sizeForTileID:tileID]);
        NSInteger sx = (NSInteger)MPTileSpanX(gridSize, cols), sy = (NSInteger)MPTileSpanY(gridSize);
        if (sx > cols) sx = cols;

        NSInteger placedRow = 0, placedCol = 0;
        BOOL placed = NO;
        for (NSInteger r = 0; !placed; r++) {
            while ((NSInteger)rows.count < r + sy)
                [rows addObject:[NSMutableData dataWithLength:(NSUInteger)cols]];
            for (NSInteger c = 0; c + sx <= cols; c++) {
                BOOL free = YES;
                for (NSInteger rr = r; rr < r + sy && free; rr++) {
                    const uint8_t *bytes = [[rows objectAtIndex:rr] bytes];
                    for (NSInteger cc = c; cc < c + sx; cc++) {
                        if (bytes[cc]) { free = NO; break; }
                    }
                }
                if (free) { placedRow = r; placedCol = c; placed = YES; break; }
            }
        }
        for (NSInteger rr = placedRow; rr < placedRow + sy; rr++) {
            uint8_t *bytes = [[rows objectAtIndex:rr] mutableBytes];
            for (NSInteger cc = placedCol; cc < placedCol + sx; cc++) bytes[cc] = 1;
        }

        MPLiveTileView *tv = [[MPLiveTileView alloc] initWithTileID:tileID
                                                               size:MPLiveSizeFromGrid(gridSize)];
        tv.launchTarget = [p launchTarget];
        tv.frame = CGRectMake((CGFloat)placedCol * (cell + g), (CGFloat)placedRow * (cell + g),
                              (CGFloat)sx * cell + (CGFloat)(sx - 1) * g,
                              (CGFloat)sy * cell + (CGFloat)(sy - 1) * g);
        [_scrollView addSubview:tv];
        [_tiles addObject:tv];
        maxY = CGRectGetMaxY(tv.frame);
    }

    _scrollView.contentSize = CGSizeMake(_scrollView.bounds.size.width,
                                         MAX(maxY + 20.0f, _scrollView.bounds.size.height));
    [self updatePinIndicators];
}

// Белый уголок у закреплённых на стартовом (их же открепляет долгое нажатие)
- (void)updatePinIndicators {
    MPLayoutModel *model = [MPLayoutModel sharedModel];
    for (MPLiveTileView *tv in _tiles) {
        BOOL pinned = ![model isBundleIDExcluded:tv.tileID];
        if (pinned && [tv viewWithTag:777] == nil) {
            UIView *pin = [[UIView alloc] initWithFrame:
                           CGRectMake(tv.bounds.size.width - 10.0f, 4.0f, 6.0f, 6.0f)];
            pin.tag = 777;
            pin.backgroundColor = [UIColor whiteColor];
            pin.userInteractionEnabled = NO;
            pin.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
            [tv addSubview:pin];
        } else if (!pinned) {
            [[tv viewWithTag:777] removeFromSuperview];
        }
    }
}

#pragma mark - События

- (MPLiveTileView *)tileAtPoint:(CGPoint)p {
    for (MPLiveTileView *tv in _tiles) {
        if (CGRectContainsPoint(tv.frame, p)) return tv;
    }
    return nil;
}

- (void)tapGesture:(UITapGestureRecognizer *)gr {
    CGPoint p = [gr locationInView:_scrollView];
    MPLiveTileView *tv = [self tileAtPoint:p];
    if (tv == nil) return;
    MPLog(@"виджеты: тап %@ → %@", tv.tileID, tv.launchTarget ?: @"без действия");
    [[MPLiveTileCenter sharedCenter] launchTileView:tv];
}

// Долгое нажатие: закреплённая плитка открепляется со стартового, откреплённая
// возвращается (как long-press-pin в списке приложений)
- (void)longGesture:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [gr locationInView:_scrollView];
    MPLiveTileView *tv = [self tileAtPoint:p];
    if (tv == nil) return;
    MPLayoutModel *model = [MPLayoutModel sharedModel];
    BOOL wasPinned = ![model isBundleIDExcluded:tv.tileID];
    MPLog(@"виджеты: %@ стартового экрана", wasPinned ? @"открепление от" : @"закрепление на");
    [[MPLiveTileCenter sharedCenter] setPinnedToHome:(!wasPinned) forTileID:tv.tileID];
    // центр разошлёт MPLiveWidgetsChangedNotification — страница пересоберётся
}

- (void)applyStyle {
    self.backgroundColor = [UIColor blackColor];
    for (MPLiveTileView *tv in _tiles) [tv applyStyle];
}

// Состав/размеры виджетов изменились (настройки, редактор, закрепление)
- (void)widgetsChanged:(NSNotification *)n {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self widgetsChanged:n]; });
        return;
    }
    _forceRebuild = YES;
    [self rebuild];
}

@end
