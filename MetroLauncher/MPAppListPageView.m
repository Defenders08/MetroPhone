#import "MPAppListPageView.h"
#import "MPTileView.h"
#import "MPMetroStyle.h"
#import "MPAppDataSource.h"
#import "MPLayoutModel.h"

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
        [cell setIcon:icon];
    }];
}

- (void)setIcon:(UIImage *)icon {
    _iconView.image = icon;
    _iconView.backgroundColor = [UIColor clearColor];
    _letter.hidden = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
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
@end

@implementation MPAppListPageView {
    UITextField *_searchField;
    UITableView *_table;
    NSArray     *_allEntries;     // все приложения (отсортированы)
    NSArray     *_sections;       // NSArray<NSDictionary{title, items}>
    UIColor     *_appliedAccent;  // под каким акцентом собрана таблица (см. applyStyle)
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
        // WP8: долгое нажатие на строке — закрепить плитку на стартовом экране
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(rowLongPressed:)];
        lp.minimumPressDuration = 0.55;
        [_table addGestureRecognizer:lp];
        [self addSubview:_table];
    }
    return self;
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
        [_table reloadData];
    }
}

- (void)dismissKeyboard {
    [_searchField resignFirstResponder];
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
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 30.0f)];
    v.backgroundColor = [UIColor blackColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12.0f, 0, tableView.bounds.size.width - 24.0f, 30.0f)];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [MPMetroStyle accentColor];
    l.font = [MPMetroStyle thinFont:20.0f];
    l.text = [[_sections objectAtIndex:section] objectForKey:@"title"];
    [v addSubview:l];
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

// Закрепление (pin) плитки из списка — возвращает откреплённую или добавляет новую (small)
- (void)rowLongPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [_table indexPathForRowAtPoint:[g locationInView:_table]];
    if (ip == nil) return;
    MPAppEntry *entry = [[[_sections objectAtIndex:ip.section] objectForKey:@"items"] objectAtIndex:ip.row];
    if (entry == nil) return;
    MPLog(@"список: закрепление плитки %@", entry.bundleID);
    [[MPLayoutModel sharedModel] pinBundleID:entry.bundleID];
    [[MPLayoutModel sharedModel] save];
    // Сетка плиток узнаёт о новой плите через то же уведомление, что и об
    // изменении списка: MPHomeController перечитает приложения и пересоберёт плитки.
    [[NSNotificationCenter defaultCenter] postNotificationName:MPAppsChangedNotification object:nil];
}

@end
