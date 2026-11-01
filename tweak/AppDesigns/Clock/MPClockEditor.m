#import "MPClockEditor.h"
#import "MPClockTheme.h"
#import "MPClockPages.h"
#import "MetroLauncher/MPMetroStyle.h"

#define MPContentW  288.0f
#define MPW 320.0f

@interface MPClockEditor () <UITableViewDataSource, UITableViewDelegate>
@end

// Корневая вьюха pivot (оверлей обязан закрывать весь экран и жить вне ленты
// страниц, иначе уедет вместе со свайпом). По классу, без импорта — циклов нет.
static UIView *MPPivotRoot(UIView *from) {
    for (UIView *u = from; u != nil; u = u.superview) {
        if ([NSStringFromClass([u class]) isEqualToString:@"MPClockPivotView"]) return u;
    }
    return nil;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Общая обвязка оверлеев

@implementation MPClockEditor {
    UIView *_host;          // страница, поверх которой открыты
    MPClockAlarm *_alarm;   // nil — создаём новый (будильник)
    // будильник
    UILabel *_hVal, *_mVal;
    UITextField *_nameField;
    NSInteger _h, _m, _daySetting;
    BOOL _snooze;           // «отложить» (native allowsSnooze)
    NSMutableArray *_dayBtns;
    // город
    UITableView *_zoneTable;
}

+ (MPClockEditor *)sharedEditor {
    static MPClockEditor *e = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ e = [[MPClockEditor alloc] initWithFrame:CGRectZero]; });
    return e;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.hidden = YES;
        _dayBtns = [NSMutableArray array];
    }
    return self;
}

// Очистить содержимое перед новым показом
- (void)resetContent {
    for (UIView *v in self.subviews) [v removeFromSuperview];
    [_dayBtns removeAllObjects];
    _nameField = nil;
    _zoneTable = nil;
    _hVal = nil;
    _mVal = nil;
}

// Закрыть и перечитать страницу-хозяина
- (void)close {
    UIView *host = _host;
    _host = nil;
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.2];
    self.alpha = 0.0f;
    [UIView commitAnimations];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.hidden = YES;
    });
    if ([host isKindOfClass:[MPClockBasePage class]]) {
        [(MPClockBasePage *)host reload];
    }
}

// Текстовая кнопка-действие редактора (акцент medium 15 — канон бар-кнопок)
- (UIButton *)textButton:(NSString *)title x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w action:(SEL)sel {
    UIButton *b = [MPClockTheme actionButtonWithTitle:title];
    b.titleLabel.font = [MPMetroStyle mediumFont:15.0f];
    [b setTitleColor:[MPMetroStyle accentColor] forState:UIControlStateNormal];
    b.frame = CGRectMake(x, y, w, 40.0f);
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (void)showHeader:(NSString *)title y:(CGFloat *)y {
    // шапка редактора — как в «Настройках»: light 52 с ужатием 52→38→30
    CGFloat size = 52.0f;
    UIFont *f = nil;
    for (; size >= 30.0f; size -= 2.0f) {
        f = [MPMetroStyle lightFont:size];
        if ([title sizeWithFont:f].width <= MPContentW) break;
    }
    CGFloat lh = ceilf([title sizeWithFont:f].height) + 4.0f;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(MPClockLead, *y, MPContentW, lh)];
    l.backgroundColor = [UIColor clearColor];
    l.font = f;
    l.textColor = [UIColor whiteColor];
    l.text = title;
    [self addSubview:l];
    *y += lh + 20.0f;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Редактор будильника

- (void)presentInPage:(UIView *)host alarm:(MPClockAlarm *)alarm {
    if (host == nil || host.superview == nil) return;
    [self resetContent];
    _host = host;
    _alarm = alarm;
    _h = alarm ? alarm.hour : 8;
    _m = alarm ? alarm.minute : 0;
    _daySetting = alarm ? alarm.daySetting : 0;
    _snooze = alarm ? alarm.snooze : YES;

    // оверлей — во весь pivot, поверх лент (не внутри клипа страниц!)
    UIView *pivot = MPPivotRoot(host);
    CGRect full = (pivot != nil) ? pivot.bounds : CGRectMake(0.0f, 0.0f, MPW, 460.0f);
    self.frame = full;
    // ВАЖНО: снять hidden из init/close — скрытая вьюха не рендерится и
    // не получает касания, анимация alpha её не оживляет
    self.hidden = NO;
    self.alpha = 0.0f;

    CGFloat y = 20.0f;
    [self showHeader:(alarm ? @"Будильник" : @"Новый будильник") y:&y];

    // удаление — текстовое действие у правого края шапки; красный палитры
    // (правило проекта: красный сохраняется для опасных действий)
    if (alarm != nil) {
        UIButton *del = [MPClockTheme actionButtonWithTitle:@"удалить"];
        [del setTitleColor:[MPClockTheme dangerColor] forState:UIControlStateNormal];
        [del addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
        CGFloat dw = [@"удалить" sizeWithFont:del.titleLabel.font].width;
        del.frame = CGRectMake(MPClockLead + MPContentW - ceilf(dw) - 4.0f, 20.0f,
                               ceilf(dw) + 4.0f, 28.0f);
        [self addSubview:del];
    }

    // имя (опционально)
    _nameField = [[UITextField alloc] initWithFrame:CGRectMake(MPClockLead, y, MPContentW, 34.0f)];
    _nameField.backgroundColor = [UIColor clearColor];
    _nameField.font = [MPMetroStyle lightFont:20.0f];
    _nameField.textColor = [UIColor whiteColor];
    _nameField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"имя (необязательно)"
            attributes:@{NSForegroundColorAttributeName: [MPClockTheme placeholderColor],
                         NSFontAttributeName: [MPMetroStyle lightFont:20.0f]}];
    _nameField.text = alarm ? alarm.title : @"";
    _nameField.returnKeyType = UIReturnKeyDone;
    _nameField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self addSubview:_nameField];
    y += 52.0f;

    // пикер времени: единая колонка 80 pt (как в таймере): «−»/«+» акцентные
    // текстовые 46×30 по центру колонки, значение thin 34, подпись 13/0.6;
    // 2 колонки, межколонник 12, группа центрирована в контенте
    CGFloat colX = MPClockLead + (MPContentW - 2 * 80.0f - 12.0f) / 2.0f;
    _hVal = [self timeColumnWithMinus:@selector(hMinus) plus:@selector(hPlus)
                                 name:@"часы" x:colX y:y];
    _mVal = [self timeColumnWithMinus:@selector(mMinus) plus:@selector(mPlus)
                                 name:@"минуты" x:colX + 92.0f y:y];
    [self refreshTime];
    y += 130.0f;

    // дни недели: подпись-секция (light 17, 0.6 — канон заголовков групп) и
    // текстовые кнопки: выбран = акцент, нет = muted («коробок нет»)
    UILabel *dl = [[UILabel alloc] initWithFrame:CGRectMake(MPClockLead, y, MPContentW, 22.0f)];
    dl.backgroundColor = [UIColor clearColor];
    dl.font = [MPMetroStyle lightFont:17.0f];
    dl.textColor = [MPClockTheme mutedColor];
    dl.text = @"повтор";
    [self addSubview:dl];
    y += 26.0f;
    static NSString *names[7] = {@"вс", @"пн", @"вт", @"ср", @"чт", @"пт", @"сб"};
    CGFloat bx = MPClockLead;
    for (int i = 0; i < 7; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(bx, y, 34.0f, 32.0f);
        b.titleLabel.font = [MPMetroStyle lightFont:20.0f];
        [b setTitle:names[i] forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:self action:@selector(dayTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [_dayBtns addObject:b];
        bx += 36.0f;
    }
    [self refreshDays];
    y += 40.0f;

    // «отложить» (snooze): секция light 17 слева, WP-тумблер 46×22 справа
    UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(MPClockLead, y + 2.0f, 150.0f, 26.0f)];
    sl.backgroundColor = [UIColor clearColor];
    sl.font = [MPMetroStyle lightFont:17.0f];
    sl.textColor = [MPClockTheme mutedColor];
    sl.text = @"отложить";
    [self addSubview:sl];
    MPWPToggle *sn = [[MPWPToggle alloc] initWithFrame:CGRectMake(MPClockLead + MPContentW - 46.0f, y, 46.0f, 22.0f)
                                                   on:_snooze
                                               change:^(BOOL on) { _snooze = on; }];
    [self addSubview:sn];
    y += 40.0f;

    // «сохранить»/«отмена» — текст (канон «Настроек»: действия акцентом,
    // коробок нет); кадры ниже — зона тапа 40
    CGFloat bw = (MPContentW - 10.0f) / 2.0f;
    [self textButton:@"сохранить" x:MPClockLead y:y w:bw action:@selector(saveTapped)];
    [self textButton:@"отмена" x:MPClockLead + bw + 10.0f y:y w:bw action:@selector(closeTapped)];
    y += 44.0f;

    [MPPivotRoot(host) addSubview:self];
    MPLog(@"[Clock] редактор будильника открыт (%@)", alarm ? alarm.alarmId : @"новый");
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.2];
    self.alpha = 1.0f;
    [UIView commitAnimations];
}

// Колонка пикера времени — единая геометрия с таймером: «−» / значение /
// «+» / подпись в колонке 80 pt; baseY — верх колонки
- (UILabel *)timeColumnWithMinus:(SEL)minus plus:(SEL)plus name:(NSString *)name
                               x:(CGFloat)x y:(CGFloat)baseY {
    UIButton *minusB = [MPClockTheme bigTextAction:@"−" secondary:NO];
    minusB.frame = CGRectMake(x + 17.0f, baseY, 46.0f, 30.0f);
    minusB.titleLabel.font = [MPMetroStyle lightFont:20.0f];
    minusB.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [minusB addTarget:self action:minus forControlEvents:UIControlEventTouchUpInside];

    UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(x, baseY + 34.0f, 80.0f, 46.0f)];
    val.backgroundColor = [UIColor clearColor];
    val.font = [MPMetroStyle thinFont:34.0f];
    val.textColor = [UIColor whiteColor];
    val.textAlignment = NSTextAlignmentCenter;

    UIButton *plusB = [MPClockTheme bigTextAction:@"+" secondary:NO];
    plusB.frame = CGRectMake(x + 17.0f, baseY + 80.0f, 46.0f, 30.0f);
    plusB.titleLabel.font = [MPMetroStyle lightFont:20.0f];
    plusB.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    [plusB addTarget:self action:plus forControlEvents:UIControlEventTouchUpInside];

    UILabel *nameL = [[UILabel alloc] initWithFrame:CGRectMake(x, baseY + 112.0f, 80.0f, 18.0f)];
    nameL.backgroundColor = [UIColor clearColor];
    nameL.font = [MPMetroStyle regularFont:13.0f];
    nameL.textColor = [MPClockTheme mutedColor];
    nameL.textAlignment = NSTextAlignmentCenter;
    nameL.text = name;

    [self addSubview:minusB];
    [self addSubview:val];
    [self addSubview:plusB];
    [self addSubview:nameL];
    return val;
}

- (void)refreshTime {
    _hVal.text = [NSString stringWithFormat:@"%ld", (long)_h];
    _mVal.text = [NSString stringWithFormat:@"%02ld", (long)_m];
}

- (void)hMinus { if (_h > 0)  { _h--;  [self refreshTime]; } }
- (void)hPlus  { if (_h < 23) { _h++;  [self refreshTime]; } }
- (void)mMinus { if (_m > 0)  { _m--;  [self refreshTime]; } }
- (void)mPlus  { if (_m < 59) { _m++;  [self refreshTime]; } }

// Дни: текст акцентом у выбранного, muted у остальных (без плашек)
- (void)refreshDays {
    for (UIButton *b in _dayBtns) {
        BOOL on = (_daySetting & (1 << b.tag)) != 0;
        [b setTitleColor:on ? [MPMetroStyle accentColor] : [MPClockTheme mutedColor]
               forState:UIControlStateNormal];
    }
}

- (void)dayTapped:(UIButton *)sender {
    _daySetting ^= (1 << sender.tag);
    [self refreshDays];
}

- (void)saveTapped {
    MPClockAlarm *a = _alarm ?: [[MPClockAlarm alloc] init];
    a.hour = _h;
    a.minute = _m;
    a.daySetting = _daySetting;
    a.title = _nameField.text ?: @"";
    a.snooze = _snooze;
    [MPClockData upsertAlarm:a];
    [_nameField resignFirstResponder];
    [self close];
}

- (void)deleteTapped {
    if (_alarm != nil) [MPClockData removeAlarm:_alarm];
    [self close];
}

- (void)closeTapped {
    [_nameField resignFirstResponder];
    [self close];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Список таймзон (добавление города)

- (void)presentCityPickerInPage:(UIView *)host {
    if (host == nil || host.superview == nil) return;
    [self resetContent];
    _host = host;

    UIView *pivot = MPPivotRoot(host);
    CGRect full = (pivot != nil) ? pivot.bounds : CGRectMake(0.0f, 0.0f, MPW, 460.0f);
    self.frame = full;
    self.hidden = NO;   // см. presentInPage: без этого оверлей мёртв
    self.alpha = 0.0f;

    CGFloat y = 20.0f;
    [self showHeader:@"Добавить город" y:&y];

    // «отмена» в списке городов — текстовая (канон: коробок нет)
    UIButton *cancel = [MPClockTheme actionButtonWithTitle:@"отмена"];
    [cancel setTitleColor:[MPMetroStyle accentColor] forState:UIControlStateNormal];
    cancel.titleLabel.font = [MPMetroStyle mediumFont:15.0f];
    cancel.frame = CGRectMake(MPClockLead, y, MPContentW, 40.0f);
    cancel.titleLabel.font = [MPMetroStyle lightFont:15.0f];
    [cancel addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:cancel];
    y += 52.0f;

    _zoneTable = [[UITableView alloc] initWithFrame:
                  CGRectMake(0.0f, y, full.size.width, full.size.height - y - 8.0f)
                  style:UITableViewStylePlain];
    _zoneTable.dataSource = self;
    _zoneTable.delegate = self;
    _zoneTable.backgroundColor = [UIColor blackColor];
    _zoneTable.separatorStyle = UITableViewCellSeparatorStyleNone;
    _zoneTable.rowHeight = 56.0f;   // как строки мировых часов
    [self addSubview:_zoneTable];

    [MPPivotRoot(host) addSubview:self];
    MPLog(@"[Clock] список городов открыт");
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.2];
    self.alpha = 1.0f;
    [UIView commitAnimations];
}

// Зоны, отсортированные по локализованному имени (кэш на процесс)
- (NSArray *)sortedZones {
    static NSArray *zones = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *zid in [NSTimeZone knownTimeZoneNames]) {
            MPClockCity *c = [MPClockCity cityWithZoneID:zid];
            if (c.name.length > 0) [list addObject:c];
        }
        [list sortUsingComparator:^NSComparisonResult(MPClockCity *a, MPClockCity *b) {
            return [a.name compare:b.name options:NSCaseInsensitiveSearch];
        }];
        zones = [list copy];
    });
    return zones;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self sortedZones].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"MPZoneCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:cellID];
        cell.backgroundColor = [UIColor blackColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [MPMetroStyle lightFont:24.0f];   // как города в списке
        cell.textLabel.highlightedTextColor = [MPClockTheme mutedColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        // подсветка нажатия — «парение» канона: без подложки, текст тускнеет
        cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
        cell.selectedBackgroundView.backgroundColor = [UIColor clearColor];
    }
    MPClockCity *c = [[self sortedZones] objectAtIndex:indexPath.row];
    cell.textLabel.text = c.name;
    return cell;
}

// текст строки — по левой линии 16, как города в мировых часах
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.indentationLevel = 0;
    cell.indentationWidth = 0.0f;
    cell.textLabel.frame = CGRectMake(16.0f, 0.0f,
                                      tableView.bounds.size.width - 32.0f,
                                      cell.bounds.size.height);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MPClockCity *c = [[self sortedZones] objectAtIndex:indexPath.row];
    [MPClockData addCityWithZoneID:c.zoneID];
    MPLog(@"[Clock] город добавлен: %@", c.zoneID);
    [self close];
}

@end
