#import "MPContactsPages.h"
#import "MPContactsTheme.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog

// Секции рисуются напрямую (drawRect): на iPhone 4 тысячи кнопок-ячеек
// недопустимы. Тап по строке различается по координате. Секции-вьюхи — НЕ
// скроллвью, setFrame им безвреден (грабля «setFrame сбрасывает
// bounds.origin» касается только страниц).
//
// ПОИСК живёт на пивоте (полоса над страницами), не здесь: поле внутри
// двух вложенных UIScrollView не получало клавиатуру. Страницы только
// рисуют секции по присланному запросу (query).

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Базовая страница

@implementation MPContactsBasePage
@synthesize onSelectPerson = _onSelectPerson, query = _query;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.showsVerticalScrollIndicator = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.alwaysBounceVertical = YES;
    }
    return self;
}

- (void)reload {}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Секция-буква (drawRect + тап по координате)

@interface MPContactsSectionView : UIView {
    MPContactsSection *_section;
}
@property (nonatomic, copy) void (^onSelectPerson)(MPContactsPerson *person);
- (id)initWithFrame:(CGRect)frame section:(MPContactsSection *)section;
@end

@implementation MPContactsSectionView

- (id)initWithFrame:(CGRect)frame section:(MPContactsSection *)section {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        _section = section;
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(tapped:)];
        [self addGestureRecognizer:t];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    // буква секции: light 17 muted — канон заголовков секций «Настроек»
    UIFont *lf = [MPMetroStyle lightFont:17.0f];
    [[MPContactsTheme mutedColor] setFill];
    [_section.letter drawAtPoint:CGPointMake(MPConLead, 8.0f) withFont:lf];

    // строки: имя light 24 белым на y+7 (канон строки 56); длинное имя
    // ужимаем размером 24→16, секции рисуются по своим границам
    UIFont *nf = [MPMetroStyle lightFont:24.0f];
    [[UIColor whiteColor] setFill];
    CGFloat maxW = self.bounds.size.width - MPConLead * 2.0f;
    CGFloat y = MPConSectionH;
    for (MPContactsPerson *p in _section.people) {
        NSString *nm = p.name.length > 0 ? p.name : @"Без имени";
        CGFloat size = 24.0f;
        for (; size >= 16.0f; size -= 2.0f) {
            nf = [MPMetroStyle lightFont:size];
            if ([nm sizeWithFont:nf].width <= maxW) break;
        }
        [nm drawAtPoint:CGPointMake(MPConLead, y + 7.0f) withFont:nf];
        y += MPConRowH;
    }
}

- (void)tapped:(UITapGestureRecognizer *)t {
    // locationInView: у обычной вьюхи — координаты внутри секции
    CGPoint pt = [t locationInView:self];
    if (pt.y < MPConSectionH) {
        MPLog(@"[Contacts] тап по заголовку секции (y=%.0f) — игнор", pt.y);
        return;
    }
    NSInteger row = (NSInteger)((pt.y - MPConSectionH) / MPConRowH);
    if (row < 0 || row >= (NSInteger)_section.people.count) {
        MPLog(@"[Contacts] тап мимо строки (y=%.0f, строка %ld из %ld)",
              pt.y, (long)row + 1, (long)_section.people.count);
        return;
    }
    MPContactsPerson *p = _section.people[row];
    MPLog(@"[Contacts] тап по строке: %@", p.name);
    if (self.onSelectPerson != nil) self.onSelectPerson(p);
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Страница «все»

@implementation MPContactsAllPage

- (void)reload {
    [self rebuild];
}

// общий сборщик контента: секции из данных по текущему запросу (query)
- (void)rebuild {
    for (UIView *v in [self.subviews copy]) {
        [v removeFromSuperview];
    }

    NSArray *sections = [MPContactsData.sharedData sectionsMatching:self.query ?: @""];
    CGFloat y = 4.0f;   // полоса поиска теперь на пивоте — страница начинается сразу
    for (MPContactsSection *s in sections) {
        CGFloat h = MPConSectionH + s.people.count * MPConRowH;
        MPContactsSectionView *sv = [[MPContactsSectionView alloc]
                                     initWithFrame:CGRectMake(0.0f, y, 320.0f, h)
                                     section:s];
        __weak MPContactsAllPage *wSelf = self;
        sv.onSelectPerson = ^(MPContactsPerson *p) {
            if (wSelf.onSelectPerson != nil) wSelf.onSelectPerson(p);
        };
        [self addSubview:sv];
        y += h;
    }
    self.contentSize = CGSizeMake(320.0f, y + 16.0f);

    // секции рисуются drawRect'ом лениво — без пинка iOS 6 не перерисует их
    // после пересборки (экран оставался пустым до следующего свайпа)
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Страница «избранное»

@implementation MPContactsFavPage

- (void)reload {
    for (UIView *v in [self.subviews copy]) {
        [v removeFromSuperview];
    }

    NSString *q = self.query ?: @"";
    NSArray *sections = [MPContactsData.sharedData favoriteSectionsMatching:q];
    CGFloat y = 4.0f;
    if (sections.count == 0) {
        // пусто: WP-подсказка (своя для поиска и для пустого избранного)
        UILabel *hint = [[UILabel alloc] initWithFrame:
                         CGRectMake(MPConLead, 24.0f, 320.0f - MPConLead * 2.0f, 120.0f)];
        hint.backgroundColor = [UIColor clearColor];
        hint.numberOfLines = 0;
        hint.font = [MPMetroStyle lightFont:20.0f];
        hint.textColor = [MPContactsTheme mutedColor];
        hint.text = q.length > 0
            ? @"Никого не найдено."
            : @"Здесь будут избранные люди.\nОткрой контакт и нажми «в избранное».";
        [self addSubview:hint];
        y = 160.0f;
    }
    for (MPContactsSection *s in sections) {
        CGFloat h = MPConSectionH + s.people.count * MPConRowH;
        MPContactsSectionView *sv = [[MPContactsSectionView alloc]
                                     initWithFrame:CGRectMake(0.0f, y, 320.0f, h)
                                     section:s];
        __weak MPContactsFavPage *wSelf = self;
        sv.onSelectPerson = ^(MPContactsPerson *p) {
            if (wSelf.onSelectPerson != nil) wSelf.onSelectPerson(p);
        };
        [self addSubview:sv];
        y += h;
    }
    self.contentSize = CGSizeMake(320.0f, y + 16.0f);

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

@end
