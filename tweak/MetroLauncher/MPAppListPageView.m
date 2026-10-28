#import "MPAppListPageView.h"
#import "MPTileView.h"
#import "MPMetroStyle.h"
#import "MPAppDataSource.h"
#import "MPLayoutModel.h"
#import "MPIconTheme.h"
#import "MPIconPickerView.h"

static NSString *MPFirstLetterOf(NSString *name) {
    if (name.length == 0) return @"?";
    NSRange r = [name rangeOfComposedCharacterSequenceAtIndex:0];
    return [[name substringWithRange:r] uppercaseString];
}

#pragma mark - Ячейка

@interface MPAppListCell : UITableViewCell
@property (nonatomic, copy) NSString *bundleID;
- (void)configureWithEntry:(MPAppEntry *)entry;
- (void)setIcon:(UIImage *)icon;
@end

@implementation MPAppListCell {
    UIImageView *_iconView;
    UILabel     *_letter;
    UILabel     *_name;
    MPBadgeView *_badge;
    BOOL         _fillsIcon;   // иконка на всю клетку (тема иконок, fill-режим)
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.contentView.backgroundColor = [UIColor blackColor];
        UIView *sel = [[UIView alloc] init];
        sel.backgroundColor = [UIColor colorWithWhite:0.2f alpha:1.0f];
        self.selectedBackgroundView = sel;

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_iconView];

        _letter = [[UILabel alloc] initWithFrame:CGRectZero];
        _letter.backgroundColor = [UIColor clearColor];
        _letter.textColor = [UIColor whiteColor];
        _letter.textAlignment = NSTextAlignmentCenter;
        _letter.font = [MPMetroStyle mediumFont:15.0f];
        [_iconView addSubview:_letter];

        _name = [[UILabel alloc] initWithFrame:CGRectZero];
        _name.backgroundColor = [UIColor clearColor];
        _name.textColor = [UIColor whiteColor];
        _name.font = [MPMetroStyle regularFont:15.0f];
        _name.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_name];

        _badge = [[MPBadgeView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_badge];
    }
    return self;
}

- (void)configureWithEntry:(MPAppEntry *)entry {
    // Ячейка переиспользуется: если это то же самое приложение и иконка уже стоит,
    // не сбрасываем её — иначе при каждом reloadData/скролле картинка мигает
    // и заново дёргает загрузчик.
    BOOL sameApp = (self.bundleID != nil && [self.bundleID isEqualToString:entry.bundleID]);

    self.bundleID = entry.bundleID;
    _name.text = entry.displayName;
    [_badge setCount:entry.badge];
    [self setNeedsLayout];

    if (sameApp && _iconView.image != nil) return;

    _iconView.image = nil;
    _iconView.backgroundColor = [MPMetroStyle placeholderColor];
    _letter.text = MPFirstLetterOf(entry.displayName);
    _letter.hidden = NO;

    NSString *bid = entry.bundleID;
    __weak MPAppListCell *weakSelf = self;
    [MPIconLoader loadIconForEntry:entry completion:^(UIImage *icon) {
        MPAppListCell *cell = weakSelf;
        if (cell == nil || icon == nil) return;
        if (![cell.bundleID isEqualToString:bid]) return;     // ячейка уже переиспользована
        cell->_fillsIcon = entry.themedFill;
        [cell setIcon:icon];
    }];
}

- (void)setIcon:(UIImage *)icon {
    _iconView.image = icon;
    _iconView.backgroundColor = [UIColor clearColor];
    _letter.hidden = YES;
    [self setNeedsLayout];   // contentMode зависит от _fillsIcon, узнанного вместе с иконкой
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    UIViewContentMode want = _fillsIcon ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    if (_iconView.contentMode != want) {
        _iconView.contentMode = want;
        _iconView.clipsToBounds = _fillsIcon;
    }
    _iconView.frame = CGRectMake(12.0f, floorf((h - 29.0f) / 2.0f), 29.0f, 29.0f);
    _letter.frame = _iconView.bounds;

    CGSize bs = [_badge sizeThatFits:CGSizeZero];
    _badge.frame = CGRectMake(w - 12.0f - bs.width, floorf((h - bs.height) / 2.0f), bs.width, bs.height);

    CGFloat right = _badge.hidden ? (w - 12.0f) : (CGRectGetMinX(_badge.frame) - 8.0f);
    _name.frame = CGRectMake(52.0f, 0.0f, MAX(0.0f, right - 52.0f), h);
}

@end

#pragma mark - Страница списка

@interface MPAppListPageView () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
// Определён ниже по файлу; объявление нужно старому clang при полной пересборке
- (void)dismissContextMenu;
@end

@implementation MPAppListPageView {
    UITextField *_searchField;
    UITableView *_table;
    NSArray     *_allEntries;     // все приложения (отсортированы)
    NSArray     *_sections;       // NSArray<NSDictionary{title, items}>
    UIColor     *_appliedAccent;  // под каким акцентом собрана таблица (см. applyStyle)
    NSMutableDictionary *_headerViews;  // заголовок секции → вьюха (без пересоздания при скролле)

    MPAppEntry  *_menuEntry;      // приложение, для которого открыто контекстное меню
    UIView      *_menuDim;        // затемнение фона (тап = закрыть меню)
    UIView      *_menuSheet;      // тёмная панель, выезжающая снизу (WP8.1)
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        _topInset = 20.0f;

        _searchField = [[UITextField alloc] initWithFrame:CGRectZero];
        _searchField.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
        _searchField.textColor = [UIColor whiteColor];
        _searchField.font = [MPMetroStyle regularFont:15.0f];
        _searchField.placeholder = @"поиск";
        _searchField.borderStyle = UITextBorderStyleNone;
        _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
        _searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
        _searchField.returnKeyType = UIReturnKeyDone;
        _searchField.keyboardAppearance = UIKeyboardAppearanceAlert;
        _searchField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _searchField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 36)];
        _searchField.leftViewMode = UITextFieldViewModeAlways;
        _searchField.delegate = self;
        [_searchField addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_searchField];

        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _table.backgroundColor = [UIColor blackColor];
        _table.separatorStyle = UITableViewCellSeparatorStyleNone;
        _table.rowHeight = 44.0f;
        _table.dataSource = self;
        _table.delegate = self;
        // WP8: долгое нажатие на строке — контекстное меню закрепления плитки
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(rowLongPressed:)];
        lp.minimumPressDuration = 0.55;
        [_table addGestureRecognizer:lp];
        [self addSubview:_table];

        _headerViews = [[NSMutableDictionary alloc] init];
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
    CGFloat g = 6.0f;
    CGFloat rowH = 36.0f;
    CGFloat y = _topInset + g;
    _searchField.frame = CGRectMake(g, y, w - g * 2.0f, rowH);   // поле на всю ширину
    CGFloat ty = y + rowH + g;
    _table.frame = CGRectMake(0.0f, ty, w, h - ty);
}

#pragma mark - Данные

- (void)reloadApps:(NSArray *)apps {
    _allEntries = apps ?: @[];
    [self rebuildSections];
    [_headerViews removeAllObjects];     // заголовки могли смениться вместе со списком
    [_table reloadData];
}

- (void)applyStyle {
    // Кнопка «iOS» — всегда в актуальном акценте (это дёшево).
    // Таблицу пересобираем только когда реально сменился акцент: reloadData на
    // каждом показе лаунчера — это пересоздание всех ячеек и заметный рывок.
    // Заголовки секций красятся при создании, поэтому смена цвета требует reload.
    UIColor *accent = [MPMetroStyle accentColor];
    if (_appliedAccent == nil || ![accent isEqual:_appliedAccent]) {
        _appliedAccent = accent;
        [_headerViews removeAllObjects]; // цвет заголовков прошиваем заново
        [_table reloadData];
    }
}

- (void)dismissKeyboard {
    [_searchField resignFirstResponder];
    [self dismissContextMenu];       // уход со страницы/лаунчера закрывает и меню
}

// Секции по первой букве; всё, что не буква (цифры, символы), — в секцию «#».
- (void)rebuildSections {
    NSString *q = [_searchField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];

    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (MPAppEntry *e in _allEntries) {
        if (q.length > 0 && [e.displayName rangeOfString:q options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        NSString *letter = MPFirstLetterOf(e.displayName);
        unichar c = letter.length > 0 ? [letter characterAtIndex:0] : '#';
        NSString *key = [letters characterIsMember:c] ? letter : @"#";
        NSMutableArray *arr = [groups objectForKey:key];
        if (arr == nil) { arr = [NSMutableArray array]; [groups setObject:arr forKey:key]; }
        [arr addObject:e];
    }
    NSArray *keys = [[groups allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if ([a isEqualToString:@"#"]) return NSOrderedAscending;     // «#» всегда первым
        if ([b isEqualToString:@"#"]) return NSOrderedDescending;
        return [a compare:b];
    }];
    NSMutableArray *sections = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *k in keys) {
        [sections addObject:@{ @"title": k, @"items": [groups objectForKey:k] }];
    }
    _sections = sections;
}

#pragma mark - Поиск

- (void)searchChanged {
    // rebuildSections+reloadData на каждый символ пересоздаёт все видимые ячейки:
    // быстрый набор debounce-им на 0,2 с — итоговая секция та же, моргания нет
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applySearch) object:nil];
    [self performSelector:@selector(applySearch) withObject:nil afterDelay:0.2];
}

- (void)applySearch {
    [self rebuildSections];
    [_table reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    dispatch_async(dispatch_get_main_queue(), ^{ [self searchChanged]; });   // текст очищается после возврата
    return YES;
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[[_sections objectAtIndex:section] objectForKey:@"items"] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"MPAppListCell";
    MPAppListCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (cell == nil) cell = [[MPAppListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    MPAppEntry *e = [[[_sections objectAtIndex:indexPath.section] objectForKey:@"items"] objectAtIndex:indexPath.row];
    [cell configureWithEntry:e];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 30.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    // Заголовки кэшируются по названию секции: на каждый показ при скролле раньше
    // создавались UIView+UILabel заново (~20 секций — волна аллокаций в скролле).
    // Названия уникальны внутри таблицы (сгруппированы по букве), так что коллизий нет.
    NSString *title = [[_sections objectAtIndex:section] objectForKey:@"title"];
    UIView *v = [_headerViews objectForKey:title];
    if (v != nil) return v;
    v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30.0f)];
    v.backgroundColor = [UIColor blackColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12.0f, 0, tableView.bounds.size.width - 24.0f, 30.0f)];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [MPMetroStyle accentColor];
    l.font = [MPMetroStyle thinFont:20.0f];
    l.text = title;
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    [_headerViews setObject:v forKey:title];
    return v;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MPAppEntry *e = [[[_sections objectAtIndex:indexPath.section] objectForKey:@"items"] objectAtIndex:indexPath.row];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [_searchField resignFirstResponder];
    MPLog(@"запуск из списка %@", e.bundleID);
    [[MPAppDataSource sharedDataSource] launchAppWithBundleID:e.bundleID];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [_searchField resignFirstResponder];     // keyboardDismissMode есть только с iOS 7
}

// WP8.1: долгое нажатие на строке — контекстное меню «закрепить/открепить»
- (void)rowLongPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [_table indexPathForRowAtPoint:[g locationInView:_table]];
    if (ip == nil) return;
    MPAppEntry *entry = [[[_sections objectAtIndex:ip.section] objectForKey:@"items"] objectAtIndex:ip.row];
    if (entry == nil) return;
    [self showContextMenuForEntry:entry];
}

#pragma mark - Контекстное меню (панель снизу, как в WP 8.1)

- (void)showContextMenuForEntry:(MPAppEntry *)entry {
    if (_menuSheet != nil) [self dismissContextMenu];   // повторное нажатие — меню перерисуется
    [self dismissKeyboard];                             // меню не открывается из-под клавиатуры
    _menuEntry = entry;

    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat headerH = 48.0f;    // имя приложения
    CGFloat itemH   = 60.0f;    // один пункт действия

    // Пункты действия: смена иконки всегда; сброс — если переопределение задано;
    // закрепление/открепление — по состоянию плитки
    NSMutableArray *items = [NSMutableArray array];   // @[ @[заголовок, селектор] ... ]
    [items addObject:@[ @"сменить иконку", NSStringFromSelector(@selector(menuChangeIconTapped)) ]];
    if ([MPIconTheme hasCustomChoiceForBundleID:entry.bundleID]) {
        [items addObject:@[ @"сбросить иконку", NSStringFromSelector(@selector(menuResetIconTapped)) ]];
    }
    BOOL pinned = ([[MPLayoutModel sharedModel] isBundleIDExcluded:entry.bundleID] == NO);
    [items addObject:@[ (pinned ? @"открепить от начального экрана" : @"закрепить на начальном экране"),
                        NSStringFromSelector(pinned ? @selector(menuUnpinTapped) : @selector(menuPinTapped)) ]];

    CGFloat sheetH = headerH + itemH * (CGFloat)items.count;

    _menuDim = [[UIView alloc] initWithFrame:self.bounds];
    _menuDim.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
    _menuDim.alpha = 0.0f;
    _menuDim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(menuDismissTapped)];
    [_menuDim addGestureRecognizer:tap];
    [self addSubview:_menuDim];

    _menuSheet = [[UIView alloc] initWithFrame:CGRectMake(0.0f, h, w, sheetH)];
    _menuSheet.backgroundColor = [UIColor colorWithWhite:0.09f alpha:1.0f];
    _menuSheet.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

    // Шапка — имя приложения акцентом (как заголовки секций)
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12.0f, 0.0f, w - 24.0f, headerH)];
    title.backgroundColor = [UIColor clearColor];
    title.textColor = [MPMetroStyle accentColor];
    title.font = [MPMetroStyle thinFont:22.0f];
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.text = entry.displayName;
    [_menuSheet addSubview:title];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0.0f, headerH - 1.0f, w, 1.0f)];
    sep.backgroundColor = [UIColor colorWithWhite:0.22f alpha:1.0f];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_menuSheet addSubview:sep];

    for (NSUInteger i = 0; i < items.count; i++) {
        NSArray *item = [items objectAtIndex:i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(0.0f, headerH + itemH * (CGFloat)i, w, itemH);
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.titleEdgeInsets = UIEdgeInsetsMake(0.0f, 12.0f, 0.0f, 12.0f);
        [b setTitle:[item objectAtIndex:0] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.titleLabel.font = [MPMetroStyle lightFont:20.0f];
        b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [b addTarget:self action:NSSelectorFromString([item objectAtIndex:1])
        forControlEvents:UIControlEventTouchUpInside];
        [_menuSheet addSubview:b];
    }

    [self addSubview:_menuSheet];
    [UIView animateWithDuration:0.25 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        _menuDim.alpha = 1.0f;
        _menuSheet.frame = CGRectMake(0.0f, h - sheetH, w, sheetH);
    } completion:nil];
}

- (void)menuPinTapped {
    MPLog(@"список: закрепление плитки %@", _menuEntry.bundleID);
    [[MPLayoutModel sharedModel] pinBundleID:_menuEntry.bundleID];
    [[MPLayoutModel sharedModel] save];
    [self dismissContextMenu];
    [self postAppsChanged];
}

// Пикер сам применяет выбор и перезагружает плитки; здесь только открыть
- (void)menuChangeIconTapped {
    MPAppEntry *entry = _menuEntry;
    NSString *bid = [entry.bundleID copy];
    NSString *name = [entry.displayName copy];
    [self dismissContextMenu];
    if (bid == nil) return;
    [MPIconPickerView showFromView:self forBundleID:bid appName:name];
}

- (void)menuResetIconTapped {
    NSString *bid = [_menuEntry.bundleID copy];
    [self dismissContextMenu];
    if (bid == nil) return;
    MPLog(@"список: сброс иконки %@", bid);
    [MPIconTheme removeCustomChoiceForBundleID:bid];
    [MPIconTheme notifyIconsChanged];
    [MPIconLoader clearCache];
    [self postAppsChanged];
}

- (void)menuUnpinTapped {
    MPLog(@"список: открепление плитки %@", _menuEntry.bundleID);
    [[MPLayoutModel sharedModel] excludeBundleID:_menuEntry.bundleID];
    [[MPLayoutModel sharedModel] save];
    [self dismissContextMenu];
    [self postAppsChanged];
}

- (void)menuDismissTapped {
    [self dismissContextMenu];
}

- (void)dismissContextMenu {
    if (_menuSheet == nil) return;
    UIView *dim = _menuDim, *sheet = _menuSheet;
    _menuDim = nil;
    _menuSheet = nil;
    _menuEntry = nil;
    CGFloat h = self.bounds.size.height;
    [UIView animateWithDuration:0.22 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                     animations:^{
        dim.alpha = 0.0f;
        sheet.frame = CGRectMake(0.0f, h, sheet.bounds.size.width, sheet.bounds.size.height);
    } completion:^(BOOL finished) {
        [dim removeFromSuperview];
        [sheet removeFromSuperview];
    }];
}

// Сетка плиток узнаёт об изменении через то же уведомление, что и об изменении
// списка: MPHomeController перечитает приложения и пересоберёт плитки.
- (void)postAppsChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:MPAppsChangedNotification object:nil];
}

@end
