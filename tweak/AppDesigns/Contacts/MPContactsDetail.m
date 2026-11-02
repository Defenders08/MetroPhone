#import "MPContactsDetail.h"
#import "MPContactsTheme.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <objc/runtime.h>

// Вёрстка — канон шапок проекта: большой заголовок light 52 (имя контакта),
// строка текстовых действий под ним («назад», «позвонить», «смс», «почта»),
// вся шапка тапается как «назад» (канон «Настроек»: шапка = кнопка).
// Контент: квадратная ава + организация, избранное, изменить, поля секциями.

@interface MPContactsDetail ()
@property (nonatomic, retain) MPContactsPerson *person;
@property (nonatomic, retain) UIScrollView *content;
@property (nonatomic, retain) UIButton *favButton;
@end

@implementation MPContactsDetail {
    BOOL _closing;   // guard двойного тапа «назад»
}

+ (MPContactsDetail *)sharedDetail {
    static MPContactsDetail *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MPContactsDetail alloc] init]; });
    return s;
}

- (id)init {
    self = [super init];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.hidden = YES;
    }
    return self;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Показ/скрытие

- (void)presentInPivot:(UIView *)pivot person:(MPContactsPerson *)person {
    @try {
        // guard двойного present: повторный вызов пересобирал бы экран под пальцем
        if (self.superview != nil && !self.hidden) return;
        _closing = NO;
        self.person = person;
        self.frame = pivot.bounds;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;

        // ГРАБЛЯ iOS 6 (Календарь): слои, построенные ДО addSubview, не
        // отрисовываются — сначала кладём вьюху в окно, потом строим контент
        [pivot addSubview:self];
        [self buildContent];

        // ГРАБЛЯ: hidden снимаем ДО alpha-анимации — скрытая вьюха не
        // рендерится и не получает касания, анимация alpha её не оживляет
        self.alpha = 0.0f;
        self.hidden = NO;
        [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1.0f; }];
        MPLog(@"[Contacts] карточка: %@ (телефонов %ld, почт %ld)", person.name,
              (long)person.phones.count, (long)person.emails.count);
    } @catch (NSException *e) {
        MPLog(@"[Contacts] !! карточка: %@ — %@", e.name, e.reason);
    }
}

- (void)dismiss {
    if (_closing) return;
    _closing = YES;
    [UIView animateWithDuration:0.18
        animations:^{ self.alpha = 0.0f; }
        completion:^(BOOL finished) {
            self.hidden = YES;
            [self removeFromSuperview];
            self.alpha = 1.0f;
            _closing = NO;
        }];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Контент

- (void)buildContent {
    for (UIView *v in self.subviews) [v removeFromSuperview];

    CGFloat topInset = [MPMetroStyle statusBarInset];
    CGFloat w = self.bounds.size.width;

    // ── шапка: большой заголовок = имя контакта (ужатие 52→30) на y=24,
    // вся шапка тапается как «назад» ──
    UIControl *backStrip = [[UIControl alloc] initWithFrame:
                            CGRectMake(0.0f, topInset, w, MPConHeaderH)];
    backStrip.backgroundColor = [UIColor clearColor];
    [backStrip addTarget:self action:@selector(dismiss)
        forControlEvents:UIControlEventTouchUpInside];
    UILabel *nameBig = [[UILabel alloc] initWithFrame:
                        CGRectMake(MPConLead, 24.0f, w - MPConLead * 2.0f, 62.0f)];
    nameBig.backgroundColor = [UIColor clearColor];
    UIFont *hf = nil;
    CGFloat size = 52.0f;
    for (; size >= 30.0f; size -= 2.0f) {
        hf = [MPMetroStyle lightFont:size];
        if ([self.person.name sizeWithFont:hf].width <= w - MPConLead * 2.0f) break;
    }
    nameBig.font = hf;
    nameBig.textColor = [UIColor whiteColor];
    nameBig.text = self.person.name;
    [backStrip addSubview:nameBig];
    [self addSubview:backStrip];

    // ── строка действий под заголовком: назад | позвонить | смс | почта
    // (по доступности). Ряд подбирает кегль 24→16, чтобы влезть в 320 ──
    CGFloat ay = topInset + MPConHeaderH;
    CGFloat ax = MPConLead;
    NSString *phone = [self.person primaryPhone];
    NSString *email = [self.person primaryEmail];
    NSMutableArray *acts = [NSMutableArray arrayWithObject:@"назад"];
    if (phone != nil) [acts addObject:@"позвонить"];
    if (phone != nil) [acts addObject:@"смс"];
    if (email != nil) [acts addObject:@"почта"];
    CGFloat asize = 24.0f;
    for (;;) {
        CGFloat total = MPConActionsGap * (acts.count - 1);
        for (NSString *t in acts) {
            total += ceilf([t sizeWithFont:[MPMetroStyle lightFont:asize]].width) + 4.0f;
        }
        if (total <= w - MPConLead * 2.0f || asize <= 16.0f) break;
        asize -= 2.0f;
    }
    for (NSString *t in acts) {
        UIButton *a = [MPContactsTheme actionButtonWithTitle:t size:asize];
        [self addSubview:a];
        if ([t isEqualToString:@"назад"]) {
            [a addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        } else if ([t isEqualToString:@"позвонить"]) {
            [a addTarget:self action:@selector(callTapped) forControlEvents:UIControlEventTouchUpInside];
        } else if ([t isEqualToString:@"смс"]) {
            [a addTarget:self action:@selector(smsTapped) forControlEvents:UIControlEventTouchUpInside];
        } else {
            [a addTarget:self action:@selector(mailTapped) forControlEvents:UIControlEventTouchUpInside];
        }
        [self placeButton:a atX:&ax y:ay];
    }

    // контент в вертикальном скролле, сразу под строкой действий
    CGFloat contentTop = ay + MPConActionsH + MPConTopGap;
    self.content = [[UIScrollView alloc] initWithFrame:
                    CGRectMake(0.0f, contentTop, w,
                               self.bounds.size.height - contentTop)];
    self.content.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                    UIViewAutoresizingFlexibleHeight;
    self.content.showsHorizontalScrollIndicator = NO;
    self.content.alwaysBounceVertical = YES;
    [self addSubview:self.content];

    // ── ава квадратная + организация справа от неё ──
    CGFloat av = 84.0f;
    CGFloat avY = 12.0f;
    // фото грузим лениво, только сейчас (в списках фото нет — скорость запуска)
    if (self.person.photo == nil) {
        self.person.photo = [MPContactsData.sharedData photoForPerson:self.person];
    }
    if (self.person.photo != nil) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:self.person.photo];
        iv.frame = CGRectMake(MPConLead, avY, av, av);
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        [self.content addSubview:iv];
    } else {
        UILabel *ini = [[UILabel alloc] initWithFrame:CGRectMake(MPConLead, avY, av, av)];
        ini.backgroundColor = [MPMetroStyle accentColor];
        ini.textAlignment = NSTextAlignmentCenter;
        ini.font = [MPMetroStyle lightFont:32.0f];
        ini.textColor = [UIColor whiteColor];
        ini.text = self.person.initials;
        [self.content addSubview:ini];
    }

    if (self.person.organization.length > 0) {
        CGFloat orgX = MPConLead + av + 14.0f;
        UILabel *org = [[UILabel alloc] initWithFrame:
                        CGRectMake(orgX, avY, w - orgX - MPConLead, 40.0f)];
        org.backgroundColor = [UIColor clearColor];
        org.font = [MPMetroStyle lightFont:20.0f];
        org.textColor = [MPContactsTheme mutedColor];
        org.adjustsFontSizeToFitWidth = YES;
        org.minimumFontSize = 13.0f;
        org.numberOfLines = 2;
        org.text = self.person.organization;
        [self.content addSubview:org];
    }

    CGFloat y = avY + av + 16.0f;

    // ── избранное + изменить ──
    self.favButton = [MPContactsTheme bigTextAction:@"в избранное" secondary:YES];
    self.favButton.frame = CGRectMake(MPConLead, y, w - MPConLead * 2.0f, 34.0f);
    [self.favButton addTarget:self action:@selector(favTapped)
              forControlEvents:UIControlEventTouchUpInside];
    [self syncFavButton];
    [self.content addSubview:self.favButton];
    y += 40.0f;

    UIButton *edit = [MPContactsTheme bigTextAction:@"изменить" secondary:NO];
    edit.frame = CGRectMake(MPConLead, y, w - MPConLead * 2.0f, 34.0f);
    [edit addTarget:self action:@selector(editTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.content addSubview:edit];
    y += 52.0f;

    // ── поля: WP-секции «телефон» / «почта» ──
    if (self.person.phones.count > 0) y = [self addSectionHeader:@"телефон" atY:y];
    y = [self addFields:self.person.phones atY:y];
    if (self.person.emails.count > 0) y = [self addSectionHeader:@"почта" atY:y];
    y = [self addFields:self.person.emails atY:y];

    self.content.contentSize = CGSizeMake(w, y + 16.0f);
    [self.content setNeedsLayout];
    [self.content setNeedsDisplay];
}

// горизонтальная укладка текстовых действий: ширина по тексту + 4 pt,
// шаг MPConActionsGap (канон строк действий «Часов»/«Календаря»)
- (void)placeButton:(UIButton *)b atX:(CGFloat *)x y:(CGFloat)y {
    CGFloat bw = ceilf([b.titleLabel.text sizeWithFont:b.titleLabel.font].width) + 4.0f;
    b.frame = CGRectMake(*x, y, bw, MPConActionsH);
    *x += bw + MPConActionsGap;
}

// WP-заголовок секции полей («телефон», «почта»)
- (CGFloat)addSectionHeader:(NSString *)title atY:(CGFloat)y {
    UILabel *h = [[UILabel alloc] initWithFrame:
                  CGRectMake(MPConLead, y, self.bounds.size.width - MPConLead * 2.0f, 30.0f)];
    h.backgroundColor = [UIColor clearColor];
    h.font = [MPMetroStyle regularFont:13.0f];
    h.textColor = [MPContactsTheme mutedColor];
    h.text = title;
    [self.content addSubview:h];
    return y + 30.0f;
}

// строки полей — UIControl + две подписи; тап открывает tel:/sms:/mailto:.
// Канон строки 56 «Часов»: значение light 24 на y+7, метка muted 13 на y+32
- (CGFloat)addFields:(NSArray *)fields atY:(CGFloat)y {
    for (MPContactsFieldValue *fv in fields) {
        UIControl *row = [[UIControl alloc] initWithFrame:
                          CGRectMake(MPConLead, y, self.bounds.size.width - MPConLead * 2.0f,
                                     MPConDetailRowH)];
        row.backgroundColor = [UIColor clearColor];

        UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 7.0f, row.bounds.size.width, 30.0f)];
        val.backgroundColor = [UIColor clearColor];
        val.font = [MPMetroStyle lightFont:24.0f];
        val.textColor = [UIColor whiteColor];
        val.adjustsFontSizeToFitWidth = YES;   // длинные номера/адреса — ужать, не обрезать
        val.minimumFontSize = 16.0f;
        val.text = fv.value;
        [row addSubview:val];

        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 32.0f, row.bounds.size.width, 16.0f)];
        lbl.backgroundColor = [UIColor clearColor];
        lbl.font = [MPMetroStyle regularFont:13.0f];
        lbl.textColor = [MPContactsTheme mutedColor];
        lbl.text = fv.label;
        [row addSubview:lbl];

        objc_setAssociatedObject(row, "mpOpenURL", fv.value, OBJC_ASSOCIATION_RETAIN);
        [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.content addSubview:row];
        y += MPConDetailRowH;
    }
    return y;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Действия

- (void)callTapped {
    NSString *p = [self.person primaryPhone];
    if (p == nil) return;
    MPLog(@"[Contacts] действие: позвонить");
    [self openScheme:[NSString stringWithFormat:@"tel:%@", [self stripPhone:p]]];
}

- (void)smsTapped {
    NSString *p = [self.person primaryPhone];
    if (p == nil) return;
    MPLog(@"[Contacts] действие: смс");
    [self openScheme:[NSString stringWithFormat:@"sms:%@", [self stripPhone:p]]];
}

- (void)mailTapped {
    NSString *e = [self.person primaryEmail];
    if (e == nil) return;
    MPLog(@"[Contacts] действие: почта");
    [self openScheme:[NSString stringWithFormat:@"mailto:%@", e]];
}

// телефон для tel:/sms:: только цифры и «+» — пробелы/скобки убивают схему
- (NSString *)stripPhone:(NSString *)phone {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < phone.length; i++) {
        unichar c = [phone characterAtIndex:i];
        if (isdigit(c) || c == '+') [out appendFormat:@"%C", c];
    }
    return out;
}

- (void)rowTapped:(UIControl *)row {
    NSString *value = objc_getAssociatedObject(row, "mpOpenURL");
    if (value.length == 0) return;
    // почта → mailto, остальное считаем телефоном
    BOOL isMail = [value containsString:@"@"];
    NSString *url = isMail ? [NSString stringWithFormat:@"mailto:%@", value]
                           : [NSString stringWithFormat:@"tel:%@", [self stripPhone:value]];
    MPLog(@"[Contacts] тап по полю: %@", value);
    [self openScheme:url];
}

- (void)openScheme:(NSString *)urlStr {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (url == nil) return;
    @try {
        [[UIApplication sharedApplication] openURL:url];
    } @catch (NSException *e) {
        MPLog(@"[Contacts] !! openURL %@ — %@", urlStr, e.reason);
    }
}

- (void)favTapped {
    BOOL now = ![MPContactsData.sharedData isFavorite:self.person.recordID];
    [MPContactsData.sharedData setFavorite:now forRecordID:self.person.recordID];
    [self syncFavButton];
    MPLog(@"[Contacts] избранное: %@ → %@", self.person.name, now ? @"да" : @"нет");
}

- (void)syncFavButton {
    BOOL fav = [MPContactsData.sharedData isFavorite:self.person.recordID];
    // акцент = закреплено; вторичное muted = ещё не в избранном
    NSString *title = fav ? @"в избранном" : @"в избранное";
    UIColor *color = fav ? [MPMetroStyle accentColor] : [MPContactsTheme mutedColor];
    [self.favButton setTitle:title forState:UIControlStateNormal];
    [self.favButton setTitleColor:color forState:UIControlStateNormal];
}

- (void)editTapped {
    MPLog(@"[Contacts] действие: изменить → нативный редактор");
    if (self.onEdit != nil) self.onEdit(self.person);
}

@end
