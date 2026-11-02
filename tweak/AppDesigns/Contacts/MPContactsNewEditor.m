#import "MPContactsNewEditor.h"
#import "MPContactsTheme.h"
#import "MetroLauncher/MPMetroStyle.h"

// Поля: имя / фамилия / организация / телефон / почта. Канон поля — редактор
// «Календаря»: light 24, transparent, плейсхолдер muted, тёмная клавиатура.

@interface MPContactsNewEditor () <UITextFieldDelegate>
@property (nonatomic, copy) void (^onSuccess)(void);
@end

@implementation MPContactsNewEditor {
    UITextField *_first, *_last, *_org, *_phone, *_email;
    BOOL _saving;   // guard двойного тапа «сохранить»
}

+ (MPContactsNewEditor *)sharedEditor {
    static MPContactsNewEditor *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MPContactsNewEditor alloc] init]; });
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

- (void)presentInPivot:(UIView *)pivot onSuccess:(void (^)(void))onSuccess {
    if (self.superview != nil && !self.hidden) return;
    _saving = NO;
    self.onSuccess = onSuccess;
    self.frame = pivot.bounds;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;
    [pivot addSubview:self];
    // ГРАБЛЯ iOS 6 (Календарь): контент строим только после addSubview
    [self buildContent];

    self.alpha = 0.0f;
    self.hidden = NO;   // hidden снимаем ДО alpha-анимации
    [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1.0f; }];
    MPLog(@"[Contacts] редактор: новый контакт открыт");
}

- (void)close {
    [UIView animateWithDuration:0.18
        animations:^{ self.alpha = 0.0f; }
        completion:^(BOOL finished) {
            self.hidden = YES;
            [self removeFromSuperview];
            self.alpha = 1.0f;
        }];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Контент

- (void)buildContent {
    for (UIView *v in self.subviews) [v removeFromSuperview];

    CGFloat topInset = [MPMetroStyle statusBarInset];
    CGFloat w = self.bounds.size.width;

    // шапка: большой заголовок «Новый контакт» (ужатие 52→30) на y=24,
    // вся шапка тапается как «назад» (отмена без сохранения)
    UIControl *backStrip = [[UIControl alloc] initWithFrame:
                            CGRectMake(0.0f, topInset, w, MPConHeaderH)];
    backStrip.backgroundColor = [UIColor clearColor];
    [backStrip addTarget:self action:@selector(cancelTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:backStrip];

    UILabel *head = [[UILabel alloc] initWithFrame:
                     CGRectMake(MPConLead, 24.0f, w - MPConLead * 2.0f, 62.0f)];
    head.backgroundColor = [UIColor clearColor];
    UIFont *hf = nil;
    CGFloat hsize = 52.0f;
    for (; hsize >= 30.0f; hsize -= 2.0f) {
        hf = [MPMetroStyle lightFont:hsize];
        if ([@"Новый контакт" sizeWithFont:hf].width <= w - MPConLead * 2.0f) break;
    }
    head.font = hf;
    head.textColor = [UIColor whiteColor];
    head.text = @"Новый контакт";
    [backStrip addSubview:head];

    // строка действий под заголовком: назад (белый) | сохранить (акцент)
    CGFloat ay = topInset + MPConHeaderH;
    CGFloat ax = MPConLead;
    UIButton *back = [MPContactsTheme actionButtonWithTitle:@"назад"];
    [back addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:back];
    [self placeButton:back atX:&ax y:ay];
    UIButton *save = [MPContactsTheme actionButtonWithTitle:@"сохранить"];
    [save setTitleColor:[MPMetroStyle accentColor] forState:UIControlStateNormal];
    [save addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:save];
    [self placeButton:save atX:&ax y:ay];

    CGFloat y = topInset + MPConHeaderBottom + MPConTopGap;

    // поля: подпись muted 13 + светлое поле light 24 (канон редактора Календаря)
    NSString *labels[5] = {@"имя", @"фамилия", @"организация", @"телефон", @"почта"};
    UITextField *fields[5];
    for (NSInteger i = 0; i < 5; i++) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(MPConLead, y, w - MPConLead * 2.0f, 16.0f)];
        l.backgroundColor = [UIColor clearColor];
        l.font = [MPMetroStyle regularFont:13.0f];
        l.textColor = [MPContactsTheme mutedColor];
        l.text = labels[i];
        [self addSubview:l];
        y += 18.0f;

        UITextField *f = [[UITextField alloc] initWithFrame:
                          CGRectMake(MPConLead, y, w - MPConLead * 2.0f, 40.0f)];
        f.tag = 10 + i;
        f.font = [MPMetroStyle lightFont:24.0f];
        f.textColor = [UIColor whiteColor];
        f.backgroundColor = [UIColor clearColor];
        f.borderStyle = UITextBorderStyleNone;
        f.keyboardAppearance = UIKeyboardAppearanceAlert;
        f.returnKeyType = UIReturnKeyDone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = (i <= 1) ? UITextAutocapitalizationTypeWords
                                            : UITextAutocapitalizationTypeNone;
        f.keyboardType = (i == 3) ? UIKeyboardTypePhonePad : UIKeyboardTypeDefault;
        // плейсхолдера нет: подпись над полем уже называет его (дубль убран)
        f.delegate = self;
        // тап по подписи тоже фокусирует поле — страховка от «клавиатура не
        // вылезает» (та же грабля, что у поиска)
        l.tag = 100 + i;
        UITapGestureRecognizer *lt = [[UITapGestureRecognizer alloc]
                                      initWithTarget:self action:@selector(labelTapped:)];
        [l addGestureRecognizer:lt];
        l.userInteractionEnabled = YES;
        [self addSubview:f];
        fields[i] = f;
        y += 48.0f;
    }
    _first = fields[0]; _last = fields[1]; _org = fields[2]; _phone = fields[3]; _email = fields[4];

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

// горизонтальная укладка текстовых действий (как на карточке):
// ширина по тексту + 4 pt, шаг MPConActionsGap
- (void)placeButton:(UIButton *)b atX:(CGFloat *)x y:(CGFloat)y {
    CGFloat bw = ceilf([b.titleLabel.text sizeWithFont:b.titleLabel.font].width) + 4.0f;
    b.frame = CGRectMake(*x, y, bw, MPConActionsH);
    *x += bw + MPConActionsGap;
}

// тап по подписи поля → фокус в поле (страховка клавиатуры)
- (void)labelTapped:(UITapGestureRecognizer *)t {
    NSInteger i = t.view.tag - 100;
    UITextField *f = (UITextField *)[self viewWithTag:10 + i];
    if (f != nil) {
        MPLog(@"[Contacts] редактор: фокус поля %ld", (long)i);
        [f becomeFirstResponder];
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Действия

- (void)saveTapped {
    if (_saving) return;   // двойной тап успевал создать два контакта
    _saving = YES;
    BOOL ok = [[MPContactsData sharedData]
               createPersonWithFirstName:_first.text
                                  lastName:_last.text
                              organization:_org.text
                                     phone:_phone.text
                                     email:_email.text];
    MPLog(@"[Contacts] редактор: сохранить → %@", ok ? @"записан" : @"отклонён");
    if (ok) {
        [self close];
        if (self.onSuccess != nil) self.onSuccess();
    } else {
        _saving = NO;   // пустые поля — даём поправить
    }
}

- (void)cancelTapped {
    MPLog(@"[Contacts] редактор: отмена");
    [self close];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    // страховка клавиатуры: iOS 6 иногда глотает первый фокус
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!textField.isFirstResponder) [textField becomeFirstResponder];
    });
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
