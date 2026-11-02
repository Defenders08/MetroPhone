#import "MPContactsPivotView.h"
#import "MPContactsTheme.h"
#import "MPContactsPages.h"
#import "MPContactsData.h"
#import "MPContactsDetail.h"
#import "MPContactsNewEditor.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <QuartzCore/QuartzCore.h>

//──────────────────────────────────────────────────────────────────────────────
// Механика скопирована с «Часов»/«Календаря»: системный UIScrollView с
// pagingEnabled, кольцо-скользящее окно (активная страница всегда в слоте 1,
// normalizeAfterStop молча перекладывает кластер и возвращает contentOffset
// в центр без анимации), шапка — слотовая WP-сетка с лерп-доводкой.
//
// ПОИСК — фиксированная полоса на пивоте (между строкой действий и страницами):
// поле внутри двух вложенных UIScrollView не получало клавиатуру — теперь
// поле — прямой потомок пивота, без скроллвью между ним и окном.

// лупа для полосы поиска: круг + ручка (шрифтовые глифы в iOS 6 ненадёжны)
@interface MPSearchGlassView : UIView
@end
@implementation MPSearchGlassView
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, [MPContactsTheme mutedColor].CGColor);
    CGContextSetLineWidth(ctx, 2.0f);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(2.0f, 2.0f, 11.0f, 11.0f));
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, 12.2f, 12.2f);
    CGContextAddLineToPoint(ctx, 17.0f, 17.0f);
    CGContextStrokePath(ctx);
}
@end

static NSInteger const MPPageCount = 2;
static NSInteger const MPConCenterSlot = 1;          // слот активной страницы

// МАРКЕР СБОРКИ — пишем в журнал при запуске (свежесть dylib проверять журналом)
static NSString * const MPContactsBuildTag = @"CON-3-МОКАП";

static MPContactsPivotView *MPContactsSharedPivot = nil;   // для отладки

static NSInteger MPConMod2(NSInteger x) { return ((x % 2) + 2) % 2; }

@interface MPContactsPivotView () <UIScrollViewDelegate, UITextFieldDelegate>
@property (nonatomic, retain) UIView *headerRow;
@property (nonatomic, retain) UIView *actionsRow;
@property (nonatomic, retain) UIView *searchStrip;
@property (nonatomic, retain) UITextField *search;
@property (nonatomic, retain) NSArray *pages;
@end

@implementation MPContactsPivotView {
    UIButton *_headers[2];
    UIButton *_actA[2];      // кнопка действия («добавить» — только у «всех»)
    CGFloat _actAW[2];
    UIScrollView *_hScroll;
    NSInteger _curPage;
    CGFloat _vOffset, _vAnchor;
    NSUInteger _lastGen;     // поколение данных последней пересборки
    BOOL _pendingReload;     // данные изменились во время жеста — пересобрать после остановки
    BOOL _editorCovering;    // открыт нативный редактор — пивот спрятан
    UITextField *_search;
    // отладочный драйв (conslow/conburst): displayLink ведёт contentOffset
    CADisplayLink *_drvLink;
    CGFloat _drvFrom, _drvTo, _drvStart, _drvDur;
    NSInteger _drvShot, _drvMode;
    BOOL _drvShots, _drvWasScrollEnabled;
    NSMutableArray *_drvLog;
}

+ (MPContactsPivotView *)installedPivotInView:(UIView *)host {
    for (UIView *v in host.subviews) {
        if ([v isKindOfClass:[MPContactsPivotView class]]) {
            if (!MPContactsEditorCovering()) [host bringSubviewToFront:v];
            return (MPContactsPivotView *)v;
        }
    }
    MPContactsPivotView *p = [[MPContactsPivotView alloc] initWithFrame:host.bounds];
    MPContactsSharedPivot = p;
    [host addSubview:p];
    MPLog(@"[Contacts] pivot установлен (%.0f×%.0f)",
          host.bounds.size.width, host.bounds.size.height);
    return p;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.clipsToBounds = YES;

        NSString *titles[2] = {@"Все", @"Избранное"};

        // ленты-контейнеры шире экрана: hitTest пускает тапы только внутри
        // bounds супервью (рисование не клипуется, касания — да)
        CGFloat beltW = MPConStride * MPPageCount;
        CGFloat topInset = [MPMetroStyle statusBarInset];

        _headerRow = [[UIView alloc] initWithFrame:CGRectMake(0.0f, topInset, beltW, MPConHeaderH)];
        [self addSubview:_headerRow];

        // Канон pivot-шапки «Часов»/«Календаря»: большие заголовки-вкладки на
        // y=24 внутри полосы 96, без подписи приложения над ними (мокап юзера,
        // ai/contacts-mockup.html). Кегль 44 — обе вкладки влезают на 320,
        // «Избранное» не обрубается краем экрана
        for (NSInteger i = 0; i < MPPageCount; i++) {
            NSString *t = titles[i];
            // страховка ужатия 44→30 с шагом 2 (канон заголовков «Календаря»)
            UIFont *hf = nil;
            CGFloat size = 44.0f;
            for (; size >= 30.0f; size -= 2.0f) {
                hf = [MPMetroStyle lightFont:size];
                if ([t sizeWithFont:hf].width <= MPConStride - MPConLead * 2.0f) break;
            }
            CGSize s = [t sizeWithFont:hf];
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(0.0f, 24.0f, ceilf(s.width) + 4.0f, ceilf(s.height) + 4.0f);
            b.titleLabel.font = hf;
            b.titleLabel.lineBreakMode = NSLineBreakByClipping;
            [b setTitle:t forState:UIControlStateNormal];
            [b setTitleColor:[MPContactsTheme faintColor] forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            b.tag = i;
            [b addTarget:self action:@selector(headerTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_headerRow addSubview:b];
            _headers[i] = b;
        }

        // строка действий: у «всех» — «добавить» (свой WP-редактор нового
        // контакта), у «избранного» действий нет (едет 1:1 со своей страницей).
        // Юзер поднял ряд ближе к вкладкам: topInset+90 вместо +96
        _actionsRow = [[UIView alloc] initWithFrame:CGRectMake(0.0f, topInset + MPConActionsTop,
                                                                beltW, MPConActionsH)];
        [self addSubview:_actionsRow];
        NSString *actATitle[2] = {@"добавить", @""};
        for (NSInteger i = 0; i < MPPageCount; i++) {
            if (actATitle[i].length == 0) { _actA[i] = nil; continue; }
            UIButton *a = [MPContactsTheme actionButtonWithTitle:actATitle[i]];
            a.tag = i;
            [a addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_actionsRow addSubview:a];
            _actA[i] = a;
        }

        // полоса поиска — фиксированная на пивоте, между строкой действий и
        // страницами (поле вне скроллвью — иначе клавиатура не вылезает).
        // По мокапу юзера: ПРОЗРАЧНЫЙ бокс с плоской белой рамкой 1px,
        // мелкий серый плейсхолдер «Поиск» (16), набранный текст light 20
        CGFloat stripY = topInset + 137.0f;
        CGFloat stripH = MPConSearchH;
        UIView *strip = [[UIView alloc] initWithFrame:
                         CGRectMake(MPConLead, stripY, frame.size.width - MPConLead * 2.0f, stripH)];
        strip.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        strip.backgroundColor = [UIColor clearColor];
        strip.layer.borderColor = [UIColor whiteColor].CGColor;
        strip.layer.borderWidth = MPConSearchBorder;
        [self addSubview:strip];
        self.searchStrip = strip;

        UIView *glass = [[MPSearchGlassView alloc] initWithFrame:CGRectMake(10.0f, 7.0f, 18.0f, 18.0f)];
        [strip addSubview:glass];

        _search = [[UITextField alloc] initWithFrame:
                   CGRectMake(38.0f, 0.0f, strip.bounds.size.width - 38.0f - 10.0f, stripH)];
        _search.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _search.font = [MPMetroStyle lightFont:20.0f];
        _search.textColor = [UIColor whiteColor];
        _search.keyboardAppearance = UIKeyboardAppearanceAlert;
        _search.returnKeyType = UIReturnKeyDone;
        _search.autocorrectionType = UITextAutocorrectionTypeNo;
        _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _search.borderStyle = UITextBorderStyleNone;
        _search.backgroundColor = [UIColor clearColor];
        _search.clearButtonMode = UITextFieldViewModeWhileEditing;
        _search.attributedPlaceholder =
            [[NSAttributedString alloc] initWithString:@"Поиск"
                                            attributes:@{
                NSForegroundColorAttributeName: [MPContactsTheme mutedColor],
                NSFontAttributeName: [MPMetroStyle lightFont:16.0f],
            }];
        _search.delegate = self;
        [strip addSubview:_search];
        self.search = _search;

        // страховка фокуса: тап по полосе принудительно ставит курсор
        UITapGestureRecognizer *focusTap = [[UITapGestureRecognizer alloc]
                                           initWithTarget:self action:@selector(focusSearch)];
        focusTap.cancelsTouchesInView = NO;
        [strip addGestureRecognizer:focusTap];

        // системный горизонтальный пейджер
        CGFloat contentTop = stripY + stripH + 6.0f;
        CGFloat contentH = frame.size.height - contentTop;
        _hScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0.0f, contentTop,
                                                                   frame.size.width, contentH)];
        _hScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _hScroll.pagingEnabled = YES;
        _hScroll.contentSize = CGSizeMake(MPConStride * MPPageCount, contentH);
        _hScroll.showsHorizontalScrollIndicator = NO;
        _hScroll.showsVerticalScrollIndicator = NO;
        _hScroll.backgroundColor = [UIColor clearColor];
        _hScroll.delegate = self;
        [self addSubview:_hScroll];

        MPContactsAllPage *all = [[MPContactsAllPage alloc]
                                  initWithFrame:CGRectMake(0.0f, 0.0f, MPConStride, contentH)];
        MPContactsFavPage *fav = [[MPContactsFavPage alloc]
                                  initWithFrame:CGRectMake(0.0f, 0.0f, MPConStride, contentH)];
        _pages = @[all, fav];

        __weak MPContactsPivotView *wSelf = self;
        // тап по строке → WP-экран контакта
        void (^onPerson)(MPContactsPerson *) = ^(MPContactsPerson *p) {
            MPContactsDetail *d = [MPContactsDetail sharedDetail];
            d.onEdit = ^(MPContactsPerson *pp) {
                MPContactsPresentNativeEditor(pp.recordID);
            };
            [d presentInPivot:wSelf person:p];
        };
        all.onSelectPerson = onPerson;
        fav.onSelectPerson = onPerson;

        for (NSInteger i = 0; i < MPPageCount; i++) {
            UIView *pg = [_pages objectAtIndex:i];
            pg.autoresizingMask = UIViewAutoresizingFlexibleHeight;
            [_hScroll addSubview:pg];
        }

        // КОЛЬЦО: старт — страница 0 («все») в центральном слоте
        _curPage = 0;
        _lastGen = (NSUInteger)-1;   // первая reloadData обязана пересобрать
        [self layoutPages];
        _vOffset = 0.0f;
        _vAnchor = MPConCenterSlot * MPConStride;
        [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];

        // изменения хранилища (внешние/избранное из экрана) → перечитать страницы
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(dataChanged:)
                                                     name:MPContactsDataDidChangeNotification
                                                   object:nil];

        MPLog(@"[Contacts] сборка %@", MPContactsBuildTag);

        // ВАЖНО: контент страниц здесь НЕ строим — вьюха ещё НЕ в окне, и iOS 6
        // не отрисует слои, созданные до addSubview (грабля «Календаря»: месяц
        // был пуст при запуске). reloadData зовётся из Hooks уже ПОСЛЕ
        // установки пивота в окно.
        [self layoutActionButtons];
        [self syncChrome];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_drvLink invalidate];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - КОЛЬЦО (2 страницы)

- (void)layoutPages {
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIScrollView *pg = (UIScrollView *)[_pages objectAtIndex:i];
        NSInteger slot = MPConMod2(i - _curPage + MPConCenterSlot);
        CGPoint co = pg.contentOffset;   // setFrame сбрасывает bounds.origin
        CGRect f = pg.frame;
        f.origin.x = slot * MPConStride;
        pg.frame = f;
        pg.contentOffset = co;
    }
}

- (void)normalizeAfterStop {
    NSInteger slot = (NSInteger)lroundf((float)(_hScroll.contentOffset.x / MPConStride));
    if (slot < 0) slot = 0;
    if (slot > MPPageCount - 1) slot = MPPageCount - 1;
    if (slot == MPConCenterSlot) {
        // прерванный анимированный скролл мог оставить offset между страницами —
        // тихо дощёлкиваем до центра (якорь предустанавливаем: дельта не
        // должна попасть в _vOffset)
        CGFloat target = MPConCenterSlot * MPConStride;
        if (fabsf(_hScroll.contentOffset.x - target) > 0.5f) {
            _vAnchor = target;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [_hScroll setContentOffset:CGPointMake(target, 0.0f) animated:NO];
            [CATransaction commit];
        }
        if (_pendingReload) { _pendingReload = NO; [self reloadData]; }
        return;
    }

    NSInteger newCur = MPConMod2(_curPage + slot - MPConCenterSlot);
    _curPage = newCur;
    _vAnchor = MPConCenterSlot * MPConStride;   // якорь до прыжка — дельта не попадает в _vOffset

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self layoutPages];
    [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];
    [CATransaction commit];

    [self syncChrome];
    if (_pendingReload) { _pendingReload = NO; [self reloadData]; }
    MPLog(@"[Contacts] кольцо: слот %ld → страница %ld", (long)slot, (long)newCur);
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Данные и действия

- (void)dataChanged:(NSNotification *)n {
    // жест/докат не прерываем — пересоберёмся, когда лента остановится
    // (normalizeAfterStop), иначе восстановление contentOffset рвёт палец
    if (_hScroll.tracking || _hScroll.dragging || _hScroll.decelerating) {
        _pendingReload = YES;
        return;
    }
    // пересборка при открытом экране контакта рвёт его анимации — даём улечься
    MPContactsDetail *d = [MPContactsDetail sharedDetail];
    if (d.superview != nil && !d.hidden) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self reloadData]; });
        return;
    }
    [self reloadData];
}

- (void)reloadData {
    // пересборка дорогая на A4: viewDidAppear и активация приходят постоянно —
    // пересобираемся только если данные реально менялись (поколение бампится
    // в invalidatePeople)
    NSUInteger gen = [MPContactsData sharedData].dataGeneration;
    if (gen == _lastGen) return;
    _lastGen = gen;
    for (UIView *pg in _pages) {
        if ([pg respondsToSelector:@selector(setQuery:)]) {
            [(MPContactsBasePage *)pg setQuery:_search.text ?: @""];
        }
        if ([pg respondsToSelector:@selector(reload)]) [(id)pg performSelector:@selector(reload)];
        // секции рисуются drawRect'ом лениво — без пинка iOS 6 не перерисует
        // их после пересборки (экран оставался пустым до следующего свайпа)
        [pg setNeedsLayout];
        [pg setNeedsDisplay];
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Поиск

// текст изменился — перечитываем ОБЕ страницы по запросу (мимо поколения
// данных: запрос меняется чаще данных)
- (void)searchChanged:(NSString *)text {
    NSString *q = text ?: @"";
    for (UIView *pg in _pages) {
        if ([pg respondsToSelector:@selector(setQuery:)]) {
            [(MPContactsBasePage *)pg setQuery:q];
        }
        if ([pg respondsToSelector:@selector(reload)]) [(id)pg performSelector:@selector(reload)];
        [pg setNeedsLayout];
        [pg setNeedsDisplay];
    }
}

- (void)focusSearch {
    MPLog(@"[Contacts] поиск: тап по полосе → фокус");
    [_search becomeFirstResponder];
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    MPLog(@"[Contacts] поиск: shouldBeginEditing");
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    MPLog(@"[Contacts] поиск: фокус получен");
    // iOS 6 иногда глотает первый фокус — добиваем на следующем ранлупе
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!textField.isFirstResponder) [textField becomeFirstResponder];
    });
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range
        replacementString:(NSString *)string {
    NSString *next = [textField.text stringByReplacingCharactersInRange:range withString:string];
    dispatch_async(dispatch_get_main_queue(), ^{ [self searchChanged:next]; });
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self searchChanged:@""]; });
    return YES;
}

- (MPContactsBasePage *)page:(NSInteger)i {
    return [_pages objectAtIndex:i];
}

- (NSInteger)slotForPage:(NSInteger)tag {
    NSInteger d = MPConMod2(tag - _curPage);
    return d == 0 ? MPConCenterSlot : 0;
}

- (void)headerTapped:(UIButton *)sender {
    NSInteger slot = [self slotForPage:sender.tag];
    if (slot == MPConCenterSlot) return;
    if (_hScroll.decelerating) {
        // iOS 6: setContentOffset:animated: при декелерации молча
        // игнорируется — сперва тихо дощёлкиваем докат до центра
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _vAnchor = MPConCenterSlot * MPConStride;
        [_hScroll setContentOffset:CGPointMake(_vAnchor, 0.0f) animated:NO];
        [CATransaction commit];
        [self normalizeAfterStop];
    }
    [_hScroll setContentOffset:CGPointMake(slot * MPConStride, 0.0f) animated:YES];
}

// программный переход (отладка)
- (void)gotoPage:(NSInteger)page animated:(BOOL)animated {
    NSInteger slot = [self slotForPage:page];
    if (slot == MPConCenterSlot) return;
    if (!animated) {
        // телепорт: якорь предустанавливаем, иначе прыжок целиком попал бы
        // в дельту didScroll и сместил виртуальный offset на страницу
        _vAnchor = slot * MPConStride;
    }
    [_hScroll setContentOffset:CGPointMake(slot * MPConStride, 0.0f) animated:animated];
}

- (void)actionTapped:(UIButton *)sender {
    if (sender.tag == 0) {
        MPLog(@"[Contacts] «добавить» — свой WP-редактор нового контакта");
        __weak MPContactsPivotView *wSelf = self;
        [[MPContactsNewEditor sharedEditor] presentInPivot:self onSuccess:^{
            // контакт записан: данные уже перечитаны по уведомлению,
            // возврат на «все» не обязателен — юзер видит обновлённый список
            (void)wSelf;
        }];
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Шапка (слотовая WP-сетка)

- (void)layoutActionButtons {
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIButton *a = _actA[i];
        if (a == nil) { _actAW[i] = 0.0f; continue; }
        _actAW[i] = ceilf([a.titleLabel.text sizeWithFont:a.titleLabel.font].width) + 4.0f;
    }
}

- (CGFloat)headerStep:(NSInteger)m {
    return _headers[m].frame.size.width + MPConHeaderGap;
}

- (CGFloat)headerQ:(NSInteger)i k:(NSInteger)k {
    CGFloat s = 0.0f;
    if (k > 0) {
        for (NSInteger j = 0; j < k; j++) s -= [self headerStep:MPConMod2(i + j)];
    } else {
        for (NSInteger j = -1; j >= k; j--) s += [self headerStep:MPConMod2(i + j)];
    }
    return s;
}

- (void)syncChrome {
    CGFloat p = _vOffset / MPConStride;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    for (NSInteger i = 0; i < MPPageCount; i++) {
        CGFloat n = fmodf((float)(p - i) + (CGFloat)MPConCenterSlot, (CGFloat)MPPageCount);
        if (n < 0.0f) n += MPPageCount;
        n -= MPConCenterSlot;
        NSInteger k = (NSInteger)floorf(n);
        CGFloat t = (float)(n - k);
        CGFloat q = [self headerQ:i k:k] * (1.0f - t) + [self headerQ:i k:k + 1] * t;
        CGRect f = _headers[i].frame;
        f.origin.x = MPConLead + q;
        _headers[i].frame = f;
    }

    // активная страница по кольцу (меняется на СЕРЕДИНЕ свайпа)
    NSInteger active = MPConMod2((NSInteger)lroundf((float)p));
    for (NSInteger i = 0; i < MPPageCount; i++) {
        [_headers[i] setSelected:(i == active)];
    }

    // действия — привязаны к разделам: у каждой страницы СВОЯ кнопка, едет
    // 1:1 с контентом своей страницы. Экранный x считаем из РЕАЛЬНОЙ
    // раскладки (слот фреймом минус offset пейджера): виртуальный _vOffset
    // безграничен (320·N через кольцо) и слоту по Mod2 несоизмерим —
    // та же грабля формулы кнопок «Календаря»
    for (NSInteger i = 0; i < MPPageCount; i++) {
        if (_actA[i] == nil) continue;
        UIView *pg = [_pages objectAtIndex:i];
        CGFloat pageX = pg.frame.origin.x - _hScroll.contentOffset.x;
        _actA[i].frame = CGRectMake(MPConLead + pageX, 0.0f, _actAW[i], MPConActionsH);
    }

    [CATransaction commit];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    _vOffset += (scrollView.contentOffset.x - _vAnchor);
    _vAnchor = scrollView.contentOffset.x;
    [self syncChrome];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) [self normalizeAfterStop];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self normalizeAfterStop];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    [self normalizeAfterStop];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Нативный редактор (уборка/возврат пивота)

- (void)hideForNativeEditor {
    _editorCovering = YES;
    [self setHidden:YES];
}

- (void)showAfterNativeEditor {
    _editorCovering = NO;
    [self setHidden:NO];
    if (self.superview != nil) [self.superview bringSubviewToFront:self];
    [self reloadData];
}

- (BOOL)isCoveringEditor {
    return _editorCovering;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - ОТЛАДКА (Darwin+префы, как «Календарь»)

- (void)driveToPage:(NSInteger)page duration:(CGFloat)dur mode:(NSInteger)mode shots:(BOOL)shots {
    if (_drvLink != nil) return;
    if (_hScroll.tracking || _hScroll.dragging || _hScroll.decelerating) {
        MPLog(@"[Contacts] отладка: отказ — живой скролл ещё идёт");
        return;
    }
    _drvFrom = _hScroll.contentOffset.x;
    _drvTo = [self slotForPage:page] * MPConStride;
    if (_drvTo == _drvFrom) {
        MPLog(@"[Contacts] отладка: страница %ld уже активна", (long)page);
        return;
    }
    _drvStart = CACurrentMediaTime();
    _drvShot = 0;
    _drvDur = MAX(0.2, dur);
    _drvShots = shots;
    _drvMode = mode;
    _drvWasScrollEnabled = _hScroll.scrollEnabled;
    _hScroll.scrollEnabled = NO;
    _drvLog = [NSMutableArray array];
    _drvLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(drvTick)];
    [_drvLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    MPLog(@"[Contacts] отладка: драйв %.0f → %.0f за %.1f с (mode %ld)",
          _drvFrom, _drvTo, _drvDur, (long)mode);
}

- (void)drvTick {
    CGFloat t = (float)((CACurrentMediaTime() - _drvStart) / _drvDur);
    BOOL done = (t >= 1.0f);
    if (done) t = 1.0f;
    CGFloat k = t;
    if (_drvMode == 1) {   // «палец»: вперёд, откат, снова вперёд
        k = t < 0.6f ? (t / 0.6f)
          : t < 0.75f ? (1.0f - (t - 0.6f) / 0.15f * 0.15f)
          : (0.85f + (t - 0.75f) / 0.25f * 0.15f);
    }
    CGFloat x = _drvFrom + (_drvTo - _drvFrom) * k;
    [_hScroll setContentOffset:CGPointMake(x, 0.0f) animated:NO];
    [_drvLog addObject:[NSString stringWithFormat:@"%.0f", x]];

    if (_drvShots) {
        static CGFloat marks[6] = {0.06f, 0.22f, 0.38f, 0.54f, 0.72f, 0.92f};
        if (_drvShot < 6 && t >= marks[_drvShot]) [self mpBurstShot];
    }

    if (done) {
        [_drvLink invalidate];
        _drvLink = nil;
        _hScroll.scrollEnabled = _drvWasScrollEnabled;
        [self normalizeAfterStop];
        if (_drvMode == 1) {
            MPLog(@"[Contacts] палец завершён: %@", [_drvLog componentsJoinedByString:@" "]);
        } else if (_drvShots) {
            MPLog(@"[Contacts] burst завершён (6 кадров)");
        }
    }
}

- (void)debugGoTo:(NSInteger)page duration:(CGFloat)dur {
    [self driveToPage:page duration:dur mode:0 shots:NO];
}

- (void)debugBurst {
    [self driveToPage:(_curPage + 1) % MPPageCount duration:2.5 mode:0 shots:YES];
}

- (void)debugFinger {
    [self driveToPage:(_curPage + 1) % MPPageCount duration:3.0 mode:1 shots:NO];
}

- (void)mpBurstShot {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0);
    [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    // пишем в Preferences — канал проверки «Календаря», запись туда разрешена
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/burst%ld.png",
                      (long)_drvShot];
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    MPLog(@"[Contacts] burst %ld (offset %.0f) → %@", (long)_drvShot, _hScroll.contentOffset.x, path);
    _drvShot++;
}

- (void)debugScrollFront:(float)fraction {
    UIScrollView *pg = [_pages objectAtIndex:_curPage];
    CGFloat maxOff = pg.contentSize.height - pg.bounds.size.height;
    if (maxOff < 1) {
        MPLog(@"[Contacts] отладка: странице %ld нечего скроллить", (long)_curPage);
        return;
    }
    CGPoint o = pg.contentOffset;
    o.y = maxOff * fraction;
    pg.contentOffset = o;
    MPLog(@"[Contacts] отладка: прокрутка страницы %ld на %.2f", (long)_curPage, fraction);
}

// прыжок на страницу (проверка пейджера)
- (void)debugGo:(NSInteger)page {
    [self gotoPage:page animated:NO];
    MPLog(@"[Contacts] отладка: переход на страницу %ld", (long)page);
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - C-обёртки для отладочных команд

static MPContactsPivotView *MPContactsSharedPivotRef(void) { return MPContactsSharedPivot; }

void MPContactsDebugScroll(float fraction) {
    MPContactsPivotView *p = MPContactsSharedPivotRef();
    if (p != nil) [p debugScrollFront:fraction];
}

void MPContactsDebugGoTo(NSInteger page, CGFloat dur) {
    MPContactsPivotView *p = MPContactsSharedPivotRef();
    if (p != nil) [p debugGoTo:page duration:dur];
}

void MPContactsDebugBurst(void) {
    MPContactsPivotView *p = MPContactsSharedPivotRef();
    if (p != nil) [p debugBurst];
}

void MPContactsDebugFinger(void) {
    MPContactsPivotView *p = MPContactsSharedPivotRef();
    if (p != nil) [p debugFinger];
}

void MPContactsDebugJump(NSInteger page) {
    MPContactsPivotView *p = MPContactsSharedPivotRef();
    if (p != nil) [p debugGo:page];
}

// одиночный снимок окна Контактов (команда conshot)
void MPContactsDebugShot(void) {
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
    if (w == nil) return;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0);
    [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    NSString *path = @"/var/mobile/Library/Preferences/conshot.png";
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    MPLog(@"[Contacts] снимок → %@", path);
}
