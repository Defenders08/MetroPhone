#import "MPTilesPageView.h"
#import "MPTileView.h"
#import "MPLayoutModel.h"
#import "MPTileEditor.h"
#import "MPMetroStyle.h"
#import "MPAppDataSource.h"

static const CGFloat MPTilesHeaderH = 30.0f;          // шапка под статус-баром (отступ сетки под статус-бар)
static const NSTimeInterval MPLongPressDelay = 0.6;   // долгое нажатие
static const CGFloat MPTapSlop = 10.0f;               // допуск смещения для тапа/долгого нажатия
static const NSInteger MPBuildBatch = 8;              // плиток за один проход главного потока

#pragma mark - Скролл, пробрасывающий касания странице

@protocol MPTilesScrollTouchDelegate <NSObject>
- (void)tilesScrollTouchesBegan:(NSSet *)touches;
- (void)tilesScrollTouchesMoved:(NSSet *)touches;
- (void)tilesScrollTouchesEnded:(NSSet *)touches;
- (void)tilesScrollTouchesCancelled:(NSSet *)touches;
@end

@interface MPTilesScrollView : UIScrollView
@property (nonatomic, weak) id<MPTilesScrollTouchDelegate> touchDelegate;
@end

@implementation MPTilesScrollView
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self.touchDelegate tilesScrollTouchesBegan:touches];
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    [self.touchDelegate tilesScrollTouchesMoved:touches];
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self.touchDelegate tilesScrollTouchesEnded:touches];
}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self.touchDelegate tilesScrollTouchesCancelled:touches];
}
@end

#pragma mark - MPTilesPageView

@interface MPTilesPageView () <MPTilesScrollTouchDelegate, MPTileEditorHost>
@end

@implementation MPTilesPageView {
    MPTilesScrollView *_scrollView;
    MPLayoutModel     *_model;
    MPTileEditor      *_editor;
    NSMutableArray    *_tiles;          // MPTileView, параллельно _model.items
    NSDictionary      *_entriesByID;    // bundleID → MPAppEntry

    BOOL      _loaded;
    BOOL      _building;
    NSArray  *_pendingApps;             // список, пришедший во время сборки/правки
    NSInteger _columns;                 // плотность сетки, при которой уложены текущие плитки

    NSInteger _pressIndex;              // плитка под пальцем (нормальный режим), -1 = нет
    CGPoint   _pressStart;
    CGPoint   _lastPoint;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        _topInset = 20.0f;
        _pressIndex = -1;
        _tiles = [NSMutableArray array];
        _model = [MPLayoutModel sharedModel];   // общий экземпляр: правки видит и список
        _editor = [[MPTileEditor alloc] init];
        _editor.host = self;

        _scrollView = [[MPTilesScrollView alloc] initWithFrame:CGRectZero];
        _scrollView.touchDelegate = self;
        _scrollView.backgroundColor = [UIColor blackColor];
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.alwaysBounceVertical = YES;
        _scrollView.alwaysBounceHorizontal = NO;
        _scrollView.directionalLockEnabled = YES;
        _scrollView.multipleTouchEnabled = NO;
        [self addSubview:_scrollView];

    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)setTopInset:(CGFloat)topInset {
    _topInset = topInset;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat y = _topInset + MPTilesHeaderH;
    _scrollView.frame = CGRectMake(0.0f, y, w, h - y);
}

- (BOOL)isLoaded { return _loaded; }
- (BOOL)isEditing { return _editor.editing; }

#pragma mark - Геометрия

- (CGRect)frameForItem:(MPTileItem *)it {
    // Сетка WP8: cell = (W − 3·gap)/4; позиции кратно ячейкам, размеры по пролётам.
    // Внешних полей нет — gap только МЕЖДУ плитками (по ТЗ).
    CGFloat W = self.bounds.size.width;
    CGFloat cell = [MPMetroStyle cellForContainerWidth:W];
    CGFloat g = MPMetroGap;
    CGSize sz = [MPMetroStyle tilePixelSize:it.tileSize containerWidth:W];
    CGFloat x = (CGFloat)it.col * (cell + g);
    CGFloat y = (CGFloat)it.row * (cell + g);
    return CGRectMake(x, y, sz.width, sz.height);
}

- (void)updateContentSize {
    // Высота контента: ряды занятости × ячейка + gap + нижнее поле.
    // Смешанные ряды учитываются через rowCount модели (в ячейках 1×1).
    CGFloat cell = [MPMetroStyle cellForContainerWidth:self.bounds.size.width];
    CGFloat g = MPMetroGap;
    CGFloat h = _model.rowCount * (cell + g) + 20.0f;
    _scrollView.contentSize = CGSizeMake(_scrollView.bounds.size.width, MAX(h, 1.0f));
}

- (void)relayoutAnimated:(BOOL)animated {
    [_model packWithColumns:[MPMetroStyle columns]];
    [self updateContentSize];
    NSArray *items = _model.items;
    MPTileView *dragging = _editor.draggingView;
    NSUInteger n = MIN(_tiles.count, items.count);
    if (!animated) {
        for (NSUInteger i = 0; i < n; i++) {
            MPTileView *tv = [_tiles objectAtIndex:i];
            if (tv == dragging) continue;               // плитка под пальцем двигается пальцем
            tv.frame = [self frameForItem:[items objectAtIndex:i]];
        }
        return;
    }
    // Свап в правке: анимируем только плитки в видимой части скролла (и уезжающие
    // из неё). Остальным ставим конечный кадр сразу — их всё равно не видно, а на
    // A4 пачка из 45 анимаций на каждый свап давала рывки.
    CGRect visible = _scrollView.bounds;   // координаты контента
    NSMutableArray *animatedIdx = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) {
        MPTileView *tv = [_tiles objectAtIndex:i];
        if (tv == dragging) continue;
        CGRect f = [self frameForItem:[items objectAtIndex:i]];
        if (CGRectIntersectsRect(visible, tv.frame) || CGRectIntersectsRect(visible, f)) {
            [animatedIdx addObject:[NSNumber numberWithUnsignedInteger:i]];
        } else {
            tv.frame = f;
        }
    }
    [UIView animateWithDuration:0.2 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         for (NSNumber *idx in animatedIdx) {
                             NSUInteger i = [idx unsignedIntegerValue];
                             MPTileView *tv = [self->_tiles objectAtIndex:i];
                             if (tv == dragging) continue;
                             tv.frame = [self frameForItem:[self->_model.items objectAtIndex:i]];
                         }
                     }
                     completion:nil];
}

#pragma mark - Загрузка и сборка плиток

- (void)ensureLoadedWithApps:(NSArray *)apps {
    if (_loaded || _building) return;
    _building = YES;
    MPLog(@"плитки: загрузка раскладки");

    [self applyStyle];
    [_model load];                       // чтение plist — лениво, здесь, а не в ctor
    [_model syncWithApps:apps];
    [_model packWithColumns:[MPMetroStyle columns]];
    [self updateEntries:apps];
    [self updateContentSize];
    [self buildTilesFromIndex:0];
}

- (void)updateEntries:(NSArray *)apps {
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithCapacity:apps.count];
    for (MPAppEntry *e in apps) [map setObject:e forKey:e.bundleID];
    _entriesByID = map;
}

- (MPTileView *)makeTileForItem:(MPTileItem *)it {
    MPTileView *tv = [[MPTileView alloc] initWithFrame:[self frameForItem:it]];
    MPAppEntry *e = [_entriesByID objectForKey:it.bundleID];
    if (e != nil) [tv configureWithEntry:e];
    else tv.bundleID = it.bundleID;
    return tv;
}

// Сборка пачками по MPBuildBatch плиток: между пачками управление возвращается в runloop.
- (void)buildTilesFromIndex:(NSInteger)start {
    NSArray *items = _model.items;
    NSInteger end = MIN(start + MPBuildBatch, (NSInteger)items.count);
    for (NSInteger i = start; i < end; i++) {
        MPTileView *tv = [self makeTileForItem:[items objectAtIndex:i]];
        [_tiles addObject:tv];
        [_scrollView addSubview:tv];
    }
    if (end < (NSInteger)items.count) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self buildTilesFromIndex:end]; });
        return;
    }
    _building = NO;
    _loaded = YES;
    MPLog(@"плитки: собрано %lu", (unsigned long)_tiles.count);
    if (_pendingApps != nil) {
        NSArray *p = _pendingApps;
        _pendingApps = nil;
        [self syncWithApps:p];
    }
}

#pragma mark - Обновление списка / бейджей

- (void)syncWithApps:(NSArray *)apps {
    if (!_loaded) {
        if (_building) _pendingApps = apps;
        return;
    }
    [self updateEntries:apps];
    if (_editor.editing) {            // структуру не трогаем во время правки — только бейджи
        _pendingApps = apps;
        [self refreshTiles];
        return;
    }
    _pendingApps = nil;
    BOOL changed = [_model syncWithApps:apps];
    // Модель могла измениться не сама по себе, а извне: закрепление плитки из
    // списка (pinBundleID) добавляет тайл, о котором сетка ещё не знает.
    // Расхождение числа плиток ловим и пересобираем — это дешевле, чем
    // пересобирать сетку на каждое обновление бейджей.
    if (_model.items.count != _tiles.count) changed = YES;
    if (changed) [self rebuildTilesToMatchModel];
    [self refreshTiles];
}

- (void)refreshTiles {
    for (MPTileView *tv in _tiles) {
        MPAppEntry *e = [_entriesByID objectForKey:tv.bundleID];
        if (e != nil) [tv updateWithEntry:e];
    }
}

- (void)rebuildTilesToMatchModel {
    NSMutableDictionary *byID = [NSMutableDictionary dictionaryWithCapacity:_tiles.count];
    for (MPTileView *tv in _tiles) [byID setObject:tv forKey:tv.bundleID];

    NSMutableArray *newTiles = [NSMutableArray arrayWithCapacity:_model.items.count];
    for (MPTileItem *it in _model.items) {
        MPTileView *tv = [byID objectForKey:it.bundleID];
        if (tv != nil) {
            [byID removeObjectForKey:it.bundleID];
        } else {
            tv = [self makeTileForItem:it];
            [_scrollView addSubview:tv];
        }
        [newTiles addObject:tv];
    }
    for (MPTileView *gone in byID.allValues) [gone removeFromSuperview];   // приложение удалено
    _tiles = newTiles;
    [self relayoutAnimated:NO];
}

- (void)applyStyle {
    // Плотность сетки могла измениться в настройках (ключ smallTiles) — переукладываем
    NSInteger cols = [MPMetroStyle columns];
    if (cols != _columns) {
        _columns = cols;
        if (_loaded) {
            [_model packWithColumns:cols];
            [self relayoutAnimated:NO];
        }
    }
    for (MPTileView *tv in _tiles) [tv applyStyle];
}
#pragma mark - Режим правки

- (void)exitEditingIfNeeded {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(longPressFired) object:nil];
    _pressIndex = -1;
    if (_editor.editing) [_editor endEditingAndSave];
}

#pragma mark - Касания (уровень страницы)

- (NSInteger)indexOfTileAtPoint:(CGPoint)p excluding:(NSInteger)excluded {
    for (NSInteger i = (NSInteger)_tiles.count - 1; i >= 0; i--) {
        if (i == excluded) continue;
        if (CGRectContainsPoint([[_tiles objectAtIndex:i] frame], p)) return i;
    }
    return -1;
}

- (void)cancelPress {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(longPressFired) object:nil];
    _pressIndex = -1;
}

- (void)tilesScrollTouchesBegan:(NSSet *)touches {
    if (!_loaded) return;
    CGPoint p = [[touches anyObject] locationInView:_scrollView];
    _lastPoint = p;
    if (_editor.editing) { [_editor touchBeganAtPoint:p]; return; }

    [self cancelPress];
    _pressIndex = [self indexOfTileAtPoint:p excluding:-1];
    _pressStart = p;
    if (_pressIndex >= 0) {
        [self performSelector:@selector(longPressFired) withObject:nil afterDelay:MPLongPressDelay];
    }
}

- (void)tilesScrollTouchesMoved:(NSSet *)touches {
    if (!_loaded) return;
    CGPoint p = [[touches anyObject] locationInView:_scrollView];
    _lastPoint = p;
    if (_editor.editing) { [_editor touchMovedToPoint:p]; return; }

    if (_pressIndex >= 0 &&
        (fabsf(p.x - _pressStart.x) > MPTapSlop || fabsf(p.y - _pressStart.y) > MPTapSlop)) {
        [self cancelPress];              // палец поехал — это скролл, а не тап/долгое нажатие
    }
}

- (void)tilesScrollTouchesEnded:(NSSet *)touches {
    if (!_loaded) return;
    CGPoint p = [[touches anyObject] locationInView:_scrollView];
    if (_editor.editing) { [_editor touchEndedAtPoint:p]; return; }

    NSInteger idx = _pressIndex;
    [self cancelPress];
    if (idx >= 0 && idx < (NSInteger)_tiles.count) {      // тап → запуск приложения
        MPTileView *tv = [_tiles objectAtIndex:idx];
        MPLog(@"запуск %@", tv.bundleID);
        [[MPAppDataSource sharedDataSource] launchAppWithBundleID:tv.bundleID];
    }
}

- (void)tilesScrollTouchesCancelled:(NSSet *)touches {
    if (_editor.editing) { [_editor touchCancelled]; return; }
    [self cancelPress];
}

// Долгое нажатие (0.6 с) → вход в режим правки; плитка сразу «поднимается» и едет за пальцем.
- (void)longPressFired {
    if (_pressIndex < 0 || _editor.editing || !_loaded) return;
    NSInteger idx = _pressIndex;
    _pressIndex = -1;                    // тап после долгого нажатия приложение не запускает
    [_editor beginEditingSelectingTileAtIndex:idx point:_lastPoint];
}

#pragma mark - MPTileEditorHost

- (NSInteger)editorTileCount { return (NSInteger)_tiles.count; }

- (MPTileView *)editorTileViewAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tiles.count) return nil;
    return [_tiles objectAtIndex:index];
}

- (NSInteger)editorIndexOfTileAtPoint:(CGPoint)point excluding:(NSInteger)excluded {
    return [self indexOfTileAtPoint:point excluding:excluded];
}

- (CGRect)editorFrameForTileAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_model.items.count) return CGRectZero;
    return [self frameForItem:[_model.items objectAtIndex:index]];
}

- (void)editorMoveTileFromIndex:(NSInteger)from toIndex:(NSInteger)to {
    NSInteger n = (NSInteger)_tiles.count;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    [_model moveItemFromIndex:from toIndex:to];
    MPTileView *tv = [_tiles objectAtIndex:from];
    [_tiles removeObjectAtIndex:from];
    [_tiles insertObject:tv atIndex:to];
    [self relayoutAnimated:YES];
    [_editor hostDidLayoutTiles];
}

- (BOOL)editorCycleSizeAtIndex:(NSInteger)index {
    BOOL ok = [_model cycleSizeAtIndex:index];
    [self relayoutAnimated:YES];
    [_editor hostDidLayoutTiles];
    return ok;
}

// Открепление: убрать из модели (в excluded) и из вьюх, пересобрать сетку
- (void)editorRemoveTileAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_tiles.count) return;
    MPTileView *tv = [_tiles objectAtIndex:index];
    NSString *bid = tv.bundleID;
    [tv removeFromSuperview];
    [_tiles removeObjectAtIndex:index];
    [_model excludeBundleID:bid];
    [self relayoutAnimated:YES];
}

- (UIView *)editorTilesContainer {
    return _scrollView;   // плитки лежат прямо в скролле (координаты касаний совпадают)
}

- (void)editorSetScrollLocked:(BOOL)locked {
    _scrollView.scrollEnabled = !locked;
}

- (UIScrollView *)editorScrollView { return _scrollView; }

- (void)editorSave {
    [_model save];
}

- (void)editorDidChangeEditing:(BOOL)editing {
    if (self.editingChangedBlock) self.editingChangedBlock(editing);
    if (!editing && _pendingApps != nil) {      // список менялся во время правки — применяем сейчас
        NSArray *p = _pendingApps;
        _pendingApps = nil;
        [self syncWithApps:p];
    }
}

@end
