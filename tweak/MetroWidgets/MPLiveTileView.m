#import "MPLiveTileView.h"
#import "MPLiveTileCenter.h"
#import "MetroLauncher/MPAnimationConstants.h"
#import "MetroLauncher/MPHomeController.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <QuartzCore/QuartzCore.h>

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
    BOOL                   _flipInFlight;      // идёт флип-обновление — новый контент без анимации
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
        // Метка «отрисовано» — только при валидных границах контейнера: провайдер
        // при нулевых границах выходит, ничего не нарисовав, и если запомнить
        // метку сейчас, layoutSubviews сочтёт плитку отрисованной — она навсегда
        // останется пустой (реальный случай: контент пришёл до первого layout).
        UIView *container = _content;
        if (container.bounds.size.width > 8.0f && container.bounds.size.height > 8.0f) {
            _renderedCellH = [self cellHeightForBounds];
            _lastRenderedW = self.bounds.size.width;
        } else {
            MPLog(@"живая плитка %@: контейнер нулевой — отрисовка отложена до layout", _tileID);
        }
    } @catch (NSException *e) {
        // сбой отрисовки не должен выносить ни сетку, ни SpringBoard
        _state = MPLiveTileStateError;
        [self showOverlay:@"!"];
    }
}

// Одновременные флипы на весь экран: бюджет A4 — не больше MPAnimFlipMaxConcurrent.
// Храним моменты старта (не голый счётчик): если вьюху пересобрали посреди флипа
// и completion не сработал, просроченные записи вычищаются сами — счётчик не
// «утекает» и не блокирует флипы навсегда.
static NSMutableArray *MPLiveFlipStarts = nil;

static NSInteger MPLiveFlipsInFlight(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ MPLiveFlipStarts = [NSMutableArray array]; });
    NSTimeInterval now = CACurrentMediaTime();
    NSUInteger i = 0;
    while (i < MPLiveFlipStarts.count) {
        if (now - [MPLiveFlipStarts[i] doubleValue] > 1.0) {   // флип живёт 0.4 с, 1.0 с — с запасом
            [MPLiveFlipStarts removeObjectAtIndex:i];
        } else {
            i++;
        }
    }
    return (NSInteger)MPLiveFlipStarts.count;
}

- (void)applyContent:(MPLiveTileContent *)content provider:(id<MPLiveTileProvider>)provider {
    if (content == nil) return;
    _provider = provider;

    // Контент не изменился — кроссфейд и пересборка вьюх не нужны (часы так
    // обновляются 3 раза из 4: текст реально меняется раз в минуту).
    if (content.state == MPLiveTileStateReady && _state == MPLiveTileStateReady &&
        _lastContent != nil &&
        [content.primaryText isEqualToString:_lastContent.primaryText] &&
        [content.secondaryText isEqualToString:_lastContent.secondaryText] &&
        [content.footerText isEqualToString:_lastContent.footerText]) {
        _lastContent = content;
        return;
    }

    // Лимит одновременных флипов: лишние откладываются на случайные 0.3–1.0 с.
    // Проверка ДО запоминания контента — иначе повторный вызов примет его
    // за «без изменений» и отложенный пройдёт вхолостую.
    if (!MPLiveReduceMotion() && !_flipInFlight &&
        ![MPHomeController metroTransitionActive] &&
        MPLiveFlipsInFlight() >= MPAnimFlipMaxConcurrent) {
        double d = MPAnimFlipRetryMin + (arc4random() % 700) / 1000.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [self applyContent:content provider:provider];
                       });
        return;
    }

    _lastContent = content;

    switch (content.state) {
        case MPLiveTileStateReady: {
            _state = MPLiveTileStateReady;
            _overlay.hidden = YES;
            _content.alpha = 1.0f;
            // Плитка нажата (tilt пишет в тот же layer.transform) — флип затёр бы наклон
            BOOL pressed = !_flipInFlight &&
                !CATransform3DEqualToTransform(self.layer.transform, CATransform3DIdentity);
            if (MPLiveReduceMotion() || _flipInFlight || pressed ||
                [MPHomeController metroTransitionActive]) {
                // Без анимации: идёт Turnstile/приложение на переднем плане/нажатие
                [self renderReady];
            } else {
                MPLog(@"диаг флип: начало t=%.3f (одновременно %ld)",
                      CACurrentMediaTime(), (long)(MPLiveFlipsInFlight() + 1));
                // флип WP (HubTile): поворот к ребру 90°, смена контента, возврат из −90°.
                // Дешевле двухгранного preserve-3d, выглядит так же.
                _flipInFlight = YES;
                [MPLiveFlipStarts addObject:@(CACurrentMediaTime())];
                CATransform3D edge = CATransform3DIdentity;
                edge.m34 = MPAnimPerspective;
                edge = CATransform3DRotate(edge, (CGFloat)M_PI / 2.0f, 0.0f, 1.0f, 0.0f);
                CATransform3D back = CATransform3DIdentity;
                back.m34 = MPAnimPerspective;
                back = CATransform3DRotate(back, -(CGFloat)M_PI / 2.0f, 0.0f, 1.0f, 0.0f);
                [UIView animateWithDuration:MPAnimFlipHalfDur delay:0
                                    options:UIViewAnimationOptionCurveEaseIn
                                 animations:^{ self.layer.transform = edge; }
                                 completion:^(BOOL finished) {
                                     [self renderReady];          // смена на невидимом ребре
                                     // модель мгновенно в −90° (без имплицитной анимации
                                     // через 0° — иначе новый контент мелькнёт лицом)
                                     [CATransaction begin];
                                     [CATransaction setDisableActions:YES];
                                     self.layer.transform = back;
                                     [CATransaction commit];
                                     [UIView animateWithDuration:MPAnimFlipHalfDur delay:0
                                                       options:UIViewAnimationOptionCurveEaseOut
                                                    animations:^{ self.layer.transform = CATransform3DIdentity; }
                                                    completion:^(BOOL done) {
                                                        // завершение обеих половин в ЛЮБОЙ ветке:
                                                        // счётчик и флаг не живут дольше анимации
                                                        self->_flipInFlight = NO;
                                                        if (MPLiveFlipStarts.count > 0)
                                                            [MPLiveFlipStarts removeObjectAtIndex:0];
                                                        MPLog(@"диаг флип: конец t=%.3f (одновременно %ld)",
                                                              CACurrentMediaTime(), (long)MPLiveFlipsInFlight());
                                                    }];
                                 }];
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

// ДИАГНОСТИКА (временная): расширение дампа базовой плитки про живое состояние —
// охота на «белые плитки» при въезде (снимается вместе с дампом в MPHomeController)
- (NSString *)mpLayerDiag {
    NSString *base = [super mpLayerDiag];
    return [NSString stringWithFormat:@"%@ виджет=%@ state=%ld контент=%@ subs=%lu flip=%d",
            base, _tileID, (long)_state,
            _content.backgroundColor == nil ? @"clear" : @"цвет",
            (unsigned long)_content.subviews.count, _flipInFlight];
}

@end
