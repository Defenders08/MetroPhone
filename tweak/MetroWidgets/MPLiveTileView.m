#import "MPLiveTileView.h"
#import "MPLiveTileCenter.h"
#import "MetroLauncher/MPMetroStyle.h"

// Reduce Motion на iOS 6 в системе нет (тумблер появился в iOS 8), но ключ
// com.apple.Accessibility/ReduceMotionEnabled читаем честно: на новых
// прошивках кроссфейд отключится сам, на iOS 6 ключа нет → анимации включены.
// Чтение не из горячего пути (только при смене контента), кэшируем значение.
static BOOL MPLiveReduceMotion(void) {
    static BOOL value = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id v = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("ReduceMotionEnabled"),
                                                           CFSTR("com.apple.Accessibility")));
        value = [v isKindOfClass:[NSNumber class]] && [(NSNumber *)v boolValue];
    });
    return value;
}

@implementation MPLiveTileView {
    NSString              *_tileID;
    MPLiveTileSize         _size;
    MPLiveTileState        _state;
    __weak id<MPLiveTileProvider> _provider;   // владелец — реестр, живёт в процессе
    MPLiveTileContent     *_lastContent;       // для перерисовки при смене размера
    UIView                *_content;
    UILabel               *_overlay;           // «!» при ошибке / подпись Empty
    CGFloat                _renderedCellH;     // высота ячейки, под которую отрисован контент
    CGFloat                _lastRenderedW;     // и ширина (широкая плитка ≠ квадратная)
}

- (instancetype)initWithTileID:(NSString *)tileID size:(MPLiveTileSize)size {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _tileID = [tileID copy];
        _size = size;
        _state = MPLiveTileStateLoading;
        // bundleID = tileID: пересборка сетки ищет вьюхи по нему (rebuildTilesToMatchModel)
        self.bundleID = tileID;

        _content = [[UIView alloc] initWithFrame:CGRectZero];
        _content.backgroundColor = [UIColor clearColor];
        _content.userInteractionEnabled = NO;
        [self addSubview:_content];

        _overlay = [[UILabel alloc] initWithFrame:CGRectZero];
        _overlay.backgroundColor = [UIColor clearColor];
        _overlay.textColor = [UIColor colorWithWhite:1.0f alpha:0.85f];
        _overlay.textAlignment = NSTextAlignmentLeft;
        _overlay.font = [MPMetroStyle mediumFont:12.0f];
        _overlay.hidden = YES;
        _overlay.userInteractionEnabled = NO;
        [self addSubview:_overlay];
    }
    return self;
}

#pragma mark - MPLiveTileProviderRenderHost

- (UIView *)contentContainer { return _content; }

- (MPLiveTileSize)liveTileSize { return _size; }

#pragma mark - Контент и состояния

// Отрисовка Ready: снести старые subviews контента и попросить провайдера
// построить новые под текущий размер.
- (void)renderReady {
    UIView *content = _content;
    for (UIView *sub in content.subviews) [sub removeFromSuperview];
    id<MPLiveTileProvider> provider = _provider;
    MPLiveTileContent *c = _lastContent;
    if (provider == nil || c == nil) return;
    @try {
        [provider renderContent:c inTileView:self];
        _renderedCellH = [self cellHeightForBounds];
        _lastRenderedW = self.bounds.size.width;
    } @catch (NSException *e) {
        // сбой отрисовки не должен выносить ни сетку, ни SpringBoard
        _state = MPLiveTileStateError;
        [self showOverlay:@"!"];
    }
}

- (void)applyContent:(MPLiveTileContent *)content provider:(id<MPLiveTileProvider>)provider {
    if (content == nil) return;
    _provider = provider;
    _lastContent = content;

    switch (content.state) {
        case MPLiveTileStateReady: {
            _state = MPLiveTileStateReady;
            _overlay.hidden = YES;
            _content.alpha = 1.0f;
            if (MPLiveReduceMotion()) {
                [self renderReady];
            } else {
                // кроссфейд WP: старый контент растворяется, новый проявляется
                [UIView transitionWithView:self
                                  duration:0.25
                                   options:UIViewAnimationOptionTransitionCrossDissolve
                                animations:^{ [self renderReady]; }
                                completion:NULL];
            }
            break;
        }
        case MPLiveTileStateError:
            _state = MPLiveTileStateError;
            for (UIView *sub in _content.subviews) [sub removeFromSuperview];
            [self showOverlay:@"!"];
            break;
        case MPLiveTileStateEmpty:
            _state = MPLiveTileStateEmpty;
            for (UIView *sub in _content.subviews) [sub removeFromSuperview];
            // пусто по смыслу: подпись, если провайдер её передал
            [self showOverlay:content.footerText];
            break;
        case MPLiveTileStateLoading:
        case MPLiveTileStateStale:
        default:
            _state = content.state;
            for (UIView *sub in _content.subviews) [sub removeFromSuperview];
            _overlay.hidden = YES;
            break;
    }
    [self setNeedsLayout];
}

- (BOOL)markStale {
    if (_state != MPLiveTileStateReady) return NO;
    _state = MPLiveTileStateStale;
    _content.alpha = 0.45f;   // приглушение без перестройки контента
    return YES;
}

- (void)showOverlay:(NSString *)text {
    _overlay.text = text;
    _overlay.hidden = (text.length == 0);
    [self setNeedsLayout];
}

#pragma mark - Размер

- (void)setLiveTileSize:(MPLiveTileSize)size {
    if (size == _size) return;
    _size = size;
    _renderedCellH = 0.0f;    // заставит layoutSubviews перерисовать контент
    [self setNeedsLayout];
}

// Высота ячейки сетки для текущей ширины — мера «реального» размера виджета
// (после смены плотности сетки или размера плитки кадр меняется).
- (CGFloat)cellHeightForBounds {
    CGFloat w = self.bounds.size.width;
    if (w < 8.0f) return 0.0f;
    return [MPMetroStyle cellForContainerWidth:w];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _content.frame = self.bounds;

    CGFloat left = 10.0f, bottom = h - 8.0f;
    _overlay.font = [MPMetroStyle mediumFont:(w < 64.0f ? 10.0f : 12.0f)];
    CGSize os = [_overlay.text sizeWithFont:_overlay.font];
    _overlay.frame = CGRectMake(left, bottom - os.height, w - left * 2.0f, ceilf(os.height));

    // Кадр изменился (размер «↕», плотность сетки, поворот) — перерисовать контент
    // под новый размер, если он уже был отрисован под другой высоту ячейки.
    CGFloat cell = [self cellHeightForBounds];
    if (_state == MPLiveTileStateReady && cell > 0.0f &&
        (fabsf(_renderedCellH - cell) > 0.5f ||
         fabsf(_lastRenderedW - w) > 0.5f)) {
        [self renderReady];
        _overlay.hidden = YES;
    }
}

#pragma mark - Регистрация в центре

// Слабая таблица центра сама чистит умершие вьюхи; повторное добавление в
// NSHashTable — no-op. Центр не запущен (настройки/чужой процесс) — no-op.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [[MPLiveTileCenter sharedCenter] registerView:self];
}

@end
