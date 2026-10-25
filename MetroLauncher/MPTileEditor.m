#import "MPTileEditor.h"
#import "MPMetroStyle.h"
#import "MPTileView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat MPDragStartDistance = 8.0f;     // порог начала перетаскивания
static const CFTimeInterval MPSwapCooldown = 0.25;   // пауза между перестановками (под анимацию перепаковки)
static const CGFloat MPAutoscrollEdge = 50.0f;       // зона автоскролла у краёв
static const CGFloat MPAutoscrollMaxSpeed = 12.0f;   // пикселей за тик
static const CGFloat MPSelectedScale = 0.80f;        // заметный зазор вокруг плитки — главный носитель парения на чёрном фоне
static const CGFloat MPMarkerDiameter = 30.0f;       // круглый маркер управления
static const CGFloat MPLiftDy = -3.5f;               // отрыв вверх (иллюзия парения)

// «Парение» WP8: небольшой масштаб + микросдвиг вверх, без вращения
static CGAffineTransform MPSelectedTransform(void) {
    return CGAffineTransformTranslate(CGAffineTransformMakeScale(MPSelectedScale, MPSelectedScale), 0.0f, MPLiftDy);
}
static CGAffineTransform MPDragTransform(void) {
    // в руке — крупнее выбранной: плитка «висит» над мозаикой
    return CGAffineTransformTranslate(CGAffineTransformMakeScale(0.92f, 0.92f), 0.0f, MPLiftDy);
}

// Едва заметная мягкая тень прямо под плиткой — иллюзия небольшого расстояния от фона.
// shadowPath по bounds: дёшево, без тяжёлых размытий и растеризации.
static void MPSetLiftShadow(UIView *v, CGFloat opacity, CGFloat radius) {
    if (v == nil) return;
    v.layer.shadowColor = [[UIColor blackColor] CGColor];
    v.layer.shadowOpacity = opacity;
    v.layer.shadowRadius = radius;
    v.layer.shadowOffset = CGSizeMake(0.0f, 2.0f);
    v.layer.shadowPath = [UIBezierPath bezierPathWithRect:v.bounds].CGPath;
}

@implementation MPTileEditor {
    BOOL         _editing;
    NSInteger    _selectedIndex;     // выбранная плитка (с маркерами) или -1
    BOOL         _wasSelectedOnBegan;// выбранная уже была выбрана в начале тапа → тап завершает правку
    MPTileView  *_dragView;
    NSInteger    _dragIndex;
    CGPoint      _dragOffset;
    NSInteger    _candidateIndex;
    CGPoint      _startPoint;
    CGPoint      _lastContentPoint;
    CGFloat      _fingerViewY;
    CFAbsoluteTime _lastSwapTime;
    NSTimer     *_autoscrollTimer;

    UIButton    *_resizeMarker;      // нижний левый угол: смена размера
    UIButton    *_unpinMarker;       // нижний правый угол: открепление плитки
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _dragIndex = -1;
        _candidateIndex = -1;
        _selectedIndex = -1;
    }
    return self;
}

- (void)dealloc {
    [_autoscrollTimer invalidate];
}

- (BOOL)editing { return _editing; }
- (MPTileView *)draggingView { return _dragView; }

#pragma mark - Маркеры управления (WP8: круги у нижних углов выбранной плитки)

- (UIButton *)mp_markerWithGlyph:(NSString *)glyph action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.bounds = CGRectMake(0.0f, 0.0f, MPMarkerDiameter, MPMarkerDiameter);
    b.layer.cornerRadius = MPMarkerDiameter / 2.0f;
    b.layer.masksToBounds = YES;
    b.backgroundColor = [UIColor whiteColor];
    b.layer.borderColor = [[UIColor colorWithWhite:0.25f alpha:1.0f] CGColor];
    b.layer.borderWidth = 1.0f;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:17.0f];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    [b setTitle:glyph forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.1f alpha:1.0f] forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    b.hidden = YES;
    return b;
}

- (void)mp_ensureMarkers {
    if (_resizeMarker != nil) return;
    UIView *container = [_host editorTilesContainer];
    _resizeMarker = [self mp_markerWithGlyph:@"\u2195" action:@selector(resizeTapped)];      // ↕
    _unpinMarker  = [self mp_markerWithGlyph:@"\u00D7" action:@selector(unpinTapped)];      // ×
    [container addSubview:_resizeMarker];
    [container addSubview:_unpinMarker];
}

- (void)mp_placeMarkersAnimated:(BOOL)animated forFrame:(CGRect)frame {
    if (_resizeMarker == nil) return;
    CGFloat r = MPMarkerDiameter / 2.0f;
    CGRect left  = CGRectMake(frame.origin.x - r, CGRectGetMaxY(frame) - MPMarkerDiameter + r,
                              MPMarkerDiameter, MPMarkerDiameter);
    CGRect right = CGRectMake(CGRectGetMaxX(frame) - r, CGRectGetMaxY(frame) - MPMarkerDiameter + r,
                              MPMarkerDiameter, MPMarkerDiameter);
    void (^apply)(void) = ^{
        _resizeMarker.frame = left;
        _unpinMarker.frame = right;
    };
    if (animated) {
        [UIView animateWithDuration:0.22 animations:apply];
    } else {
        apply();
    }
    [_resizeMarker.superview bringSubviewToFront:_resizeMarker];
    [_unpinMarker.superview bringSubviewToFront:_unpinMarker];
}

- (void)mp_showMarkers:(BOOL)show {
    _resizeMarker.hidden = !show;
    _unpinMarker.hidden = !show;
}

- (void)resizeTapped {
    if (_selectedIndex < 0 || _selectedIndex >= [_host editorTileCount]) return;
    NSInteger idx = _selectedIndex;
    BOOL ok = [_host editorCycleSizeAtIndex:idx];   // модель + перепаковка + анимация соседей
    MPLog(@"правка: смена размера плитки %ld → %@", (long)idx, ok ? @"OK" : @"не влезает");
    // маркеры — на новое место плитки (с той же анимацией)
    CGRect frame = [_host editorFrameForTileAtIndex:idx];
    [self mp_placeMarkersAnimated:YES forFrame:frame];
}

- (void)unpinTapped {
    if (_selectedIndex < 0 || _selectedIndex >= [_host editorTileCount]) return;
    NSInteger idx = _selectedIndex;
    MPTileView *tile = [_host editorTileViewAtIndex:idx];
    MPLog(@"правка: открепление плитки %ld", (long)idx);
    [self mp_showMarkers:NO];
    _selectedIndex = -1;

    if (tile != nil) {
        [UIView animateWithDuration:0.20 animations:^{
            tile.transform = CGAffineTransformMakeScale(0.01f, 0.01f);
            tile.alpha = 0.0f;
        } completion:^(BOOL finished) {
            tile.transform = CGAffineTransformIdentity;
            tile.alpha = 1.0f;
            MPSetLiftShadow(tile, 0.0f, 0.0f);
        }];
    }
    // хост убирает плитку из модели/вьюх, пишет excluded и пересобирает сетку
    [_host editorRemoveTileAtIndex:idx];
    [_host editorSave];
}

#pragma mark - Выбор плитки

- (void)mp_selectTileAtIndex:(NSInteger)index animated:(BOOL)animated {
    if (index == _selectedIndex) return;
    [self mp_deselectCurrentTile:animated];

    if (index >= 0 && index < [_host editorTileCount]) {
        _selectedIndex = index;
        MPTileView *tile = [_host editorTileViewAtIndex:index];
        void (^apply)(void) = ^{
            tile.transform = MPSelectedTransform();          // масштаб + отрыв — одновременно
            MPSetLiftShadow(tile, 0.35f, 3.0f);              // мягкая тень (видна на соседних плитках и зазорах)
        };
        if (animated) [UIView animateWithDuration:0.18 animations:apply];
        else apply();

        [self mp_ensureMarkers];
        [self mp_showMarkers:YES];
        [self mp_placeMarkersAnimated:NO forFrame:[_host editorFrameForTileAtIndex:index]];
        [[_host editorTilesContainer] bringSubviewToFront:tile];
        [_resizeMarker.superview bringSubviewToFront:_resizeMarker];
        [_unpinMarker.superview bringSubviewToFront:_unpinMarker];
    }
}

- (void)mp_deselectCurrentTile:(BOOL)animated {
    if (_selectedIndex < 0) return;
    if (_selectedIndex < [_host editorTileCount]) {
        MPTileView *tile = [_host editorTileViewAtIndex:_selectedIndex];
        void (^apply)(void) = ^{
            tile.transform = CGAffineTransformIdentity;      // плитка возвращается в плоскость сетки
            MPSetLiftShadow(tile, 0.0f, 0.0f);
        };
        if (animated) [UIView animateWithDuration:0.18 animations:apply];
        else apply();
    }
    _selectedIndex = -1;
    [self mp_showMarkers:NO];
}

#pragma mark - Вход / выход

- (void)beginEditingSelectingTileAtIndex:(NSInteger)index point:(CGPoint)point {
    if (_editing) return;
    _editing = YES;
    MPLog(@"правка: вход (WP8), выбрана плитка %ld", (long)index);
    [self mp_selectTileAtIndex:index animated:YES];
    [_host editorDidChangeEditing:YES];

    // палец ещё на плитке — разрешаем сразу перетащить, не отпуская
    _candidateIndex = index;
    _wasSelectedOnBegan = NO;
    _startPoint = point;
    if (_candidateIndex >= 0) [_host editorSetScrollLocked:YES];
}

- (void)endEditingAndSave {
    if (!_editing) return;
    if (_dragView != nil) [self finishDrag];
    _editing = NO;
    _candidateIndex = -1;
    [self mp_deselectCurrentTile:YES];
    [_host editorSetScrollLocked:NO];
    [_host editorSave];
    MPLog(@"правка: выход, раскладка сохранена");
    [_host editorDidChangeEditing:NO];
}

- (void)hostDidLayoutTiles {
    // после перепаковки (например, сменой размера) маркеры едут за плиткой,
    // а тень перестраивается под её новые границы
    if (!_editing || _selectedIndex < 0 || _selectedIndex >= [_host editorTileCount]) return;
    [self mp_placeMarkersAnimated:NO forFrame:[_host editorFrameForTileAtIndex:_selectedIndex]];
    MPTileView *tile = [_host editorTileViewAtIndex:_selectedIndex];
    MPSetLiftShadow(tile, 0.35f, 3.0f);
}

#pragma mark - Касания

- (void)touchBeganAtPoint:(CGPoint)p {
    if (!_editing) return;
    _startPoint = p;
    _candidateIndex = [_host editorIndexOfTileAtPoint:p excluding:-1];
    _wasSelectedOnBegan = (_candidateIndex == _selectedIndex);

    if (_dragView != nil) return;
    if (_candidateIndex >= 0) {
        // WP8: взятие другой плитки сразу выбирает её и готово к перетаскиванию
        [self mp_selectTileAtIndex:_candidateIndex animated:YES];
        [_host editorSetScrollLocked:YES];
    } else {
        [_host editorSetScrollLocked:NO];   // палец на фоне — можно скроллить, тап завершит правку
    }
}

- (void)touchMovedToPoint:(CGPoint)p {
    if (!_editing) return;
    if (_dragView != nil) {
        [self updateDragAtPoint:p];
        return;
    }
    if (_candidateIndex >= 0) {
        CGFloat dx = p.x - _startPoint.x, dy = p.y - _startPoint.y;
        if (dx * dx + dy * dy > MPDragStartDistance * MPDragStartDistance) {
            [self startDragAtIndex:_candidateIndex anchor:_startPoint current:p];
            _candidateIndex = -1;
        }
    }
}

- (void)touchEndedAtPoint:(CGPoint)p {
    if (!_editing) return;
    if (_dragView != nil) {
        [self finishDrag];
        _candidateIndex = -1;
        return;
    }

    if (_candidateIndex < 0) {
        // тап по свободному месту экрана — завершаем редактирование (как в WP8)
        [self endEditingAndSave];
    } else if (_wasSelectedOnBegan) {
        // повторный тап по уже выбранной плитке — тоже выход
        [self endEditingAndSave];
    }
    // иначе: тап по плитке выбрал её (сделано в touchBegan) — режим продолжается
    _candidateIndex = -1;
    [_host editorSetScrollLocked:NO];
}

- (void)touchCancelled {
    if (_dragView != nil) [self finishDrag];
    _candidateIndex = -1;
    [_host editorSetScrollLocked:NO];
}

#pragma mark - Перетаскивание

- (void)startDragAtIndex:(NSInteger)index anchor:(CGPoint)anchor current:(CGPoint)current {
    MPTileView *tile = [_host editorTileViewAtIndex:index];
    if (tile == nil) return;
    [_host editorSetScrollLocked:YES];

    _dragIndex = index;
    _dragView = tile;
    _dragOffset = CGPointMake(tile.center.x - anchor.x, tile.center.y - anchor.y);
    _lastSwapTime = 0;
    [tile.superview bringSubviewToFront:tile];
    [self mp_showMarkers:NO];          // маркеры убираем, пока плитка в руке

    [UIView animateWithDuration:0.18 animations:^{
        tile.transform = MPDragTransform();                  // парит над сеткой, яркая и плоская
        MPSetLiftShadow(tile, 0.45f, 5.0f);                  // глубокая тень — ложится на соседние плитки
    }];
    [self updateDragAtPoint:current];
    [self startAutoscroll];
    MPLog(@"правка: перетаскивание плитки %ld", (long)index);
}

- (void)updateDragAtPoint:(CGPoint)p {
    UIScrollView *sv = [_host editorScrollView];
    _lastContentPoint = p;
    _fingerViewY = p.y - sv.contentOffset.y;
    _dragView.center = CGPointMake(p.x + _dragOffset.x, p.y + _dragOffset.y);

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _lastSwapTime < MPSwapCooldown) return;
    NSInteger target = [_host editorIndexOfTileAtPoint:p excluding:_dragIndex];
    if (target >= 0 && target != _dragIndex) {
        [_host editorMoveTileFromIndex:_dragIndex toIndex:target];
        _dragIndex = target;
        _lastSwapTime = now;
    }
}

- (void)finishDrag {
    [self stopAutoscroll];
    MPTileView *tile = _dragView;
    NSInteger index = _dragIndex;
    _dragView = nil;
    _dragIndex = -1;
    if (tile == nil) return;

    CGRect target = [_host editorFrameForTileAtIndex:index];
    [UIView animateWithDuration:0.20 animations:^{
        tile.frame = target;                                 // привязка к сетке — плавно, без скачка
        tile.transform = MPSelectedTransform();              // остаётся выбранной и приподнятой
        MPSetLiftShadow(tile, 0.35f, 3.0f);                  // лёгкое парение сохраняется
    }];
    _selectedIndex = index;            // после drop плитка остаётся выбранной — как в WP8
    [self mp_ensureMarkers];
    [self mp_showMarkers:YES];
    [self mp_placeMarkersAnimated:NO forFrame:target];
    [_host editorSetScrollLocked:NO];
    [_host editorSave];                // WP8 сохраняет раскладку сразу после перемещения
}

#pragma mark - Автоскролл у краёв

- (void)startAutoscroll {
    if (_autoscrollTimer != nil) return;
    _autoscrollTimer = [NSTimer timerWithTimeInterval:0.03 target:self
                                             selector:@selector(autoscrollTick)
                                             userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_autoscrollTimer forMode:NSRunLoopCommonModes];
}

- (void)stopAutoscroll {
    [_autoscrollTimer invalidate];
    _autoscrollTimer = nil;
}

- (void)autoscrollTick {
    if (_dragView == nil) { [self stopAutoscroll]; return; }
    UIScrollView *sv = [_host editorScrollView];
    CGFloat viewH = sv.bounds.size.height;

    CGFloat speed = 0.0f;
    if (_fingerViewY < MPAutoscrollEdge) {
        CGFloat k = MIN(1.0f, (MPAutoscrollEdge - _fingerViewY) / MPAutoscrollEdge);
        speed = -k * MPAutoscrollMaxSpeed;
    } else if (_fingerViewY > viewH - MPAutoscrollEdge) {
        CGFloat k = MIN(1.0f, (_fingerViewY - (viewH - MPAutoscrollEdge)) / MPAutoscrollEdge);
        speed = k * MPAutoscrollMaxSpeed;
    }
    if (speed == 0.0f) return;

    CGFloat maxY = MAX(0.0f, sv.contentSize.height - viewH);
    CGFloat ny = MAX(0.0f, MIN(maxY, sv.contentOffset.y + speed));
    if (ny == sv.contentOffset.y) return;
    sv.contentOffset = CGPointMake(0.0f, ny);
    [self updateDragAtPoint:CGPointMake(_lastContentPoint.x, _fingerViewY + ny)];
}

@end
