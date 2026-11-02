#import "MPCalcView.h"
#import "MPCalcTheme.h"
#import "MetroLauncher/MPMetroStyle.h"
#import <QuartzCore/QuartzCore.h>

//──────────────────────────────────────────────────────────────────────────────
// WP8.1-калькулятор (референс юзера, 320×480):
//   дисплей — крупная светлая строка справа (light 64, ужатие по ширине);
//   портрет — сетка 4×6: C MC MR M+ / ⌫ ± % ÷ / 7 8 9 × / 4 5 6 − / 1 2 3 +
//             / 0(×2) , =;  «=» акцентная, остальные #333 с белым light-текстом.
//   ландшафт — слева 2 колонки научных клавиш (sin cos tan ln log √ x² x^y
//             1/x x! π e), базовая сетка сдвигается вправо без изменений.
// Логика — калькулятор с приоритетами (как Windows): стек операторов,
// промежуточные результаты после каждого оператора, «=» дочитывает стек.
// x^y — приоритет 3, правоассоциативный; тригонометрия в градусах.
// Ориентация — своя (нативная ротация заблокирована хуком): трансформ ±90°
// с анимацией; лежащий горизонтально (FaceUp/Down) игнорируем.
// Глиф backspace рисуем сами (⌫ в шрифтах iOS 6 не гарантирован).
//──────────────────────────────────────────────────────────────────────────────

// Теги клавиш: 0..9 — цифры, дальше — действия
#define MPTagClear      100
#define MPTagMemClear   101
#define MPTagMemRecall  102
#define MPTagMemAdd     103
#define MPTagBackspace  110
#define MPTagNegate     111
#define MPTagPercent    112
#define MPTagDiv        113
#define MPTagMul        114
#define MPTagSub        115
#define MPTagAdd        116
#define MPTagDot        117
#define MPTagEquals     118
// научные (видны только в ландшафте)
#define MPTagSin        120
#define MPTagCos        121
#define MPTagTan        122
#define MPTagLn         123
#define MPTagLog        124
#define MPTagSqrt       125
#define MPTagSqr        126
#define MPTagPow        127
#define MPTagInv        128
#define MPTagFact       129
#define MPTagPi         130
#define MPTagEuler      131

// Применить оператор; деление на ноль и т.п. — NaN (ловится вызывающим)
static double MPCalcApply(double a, NSString *op, double b) {
    if ([op isEqualToString:@"+"]) return a + b;
    if ([op isEqualToString:@"−"]) return a - b;
    if ([op isEqualToString:@"×"]) return a * b;
    if ([op isEqualToString:@"^"]) {
        if (a == 0.0 && b < 0.0) return NAN;
        return pow(a, b);
    }
    if (b == 0.0) return NAN;
    return a / b;
}

static int MPCalcPrec(NSString *op) {
    if ([op isEqualToString:@"^"]) return 3;
    return ([op isEqualToString:@"+"] || [op isEqualToString:@"−"]) ? 1 : 2;
}

// Единый форматтер чисел: локаль устройства (разделители, группировка разрядов)
static NSNumberFormatter *MPCalcFormatter(void) {
    static NSNumberFormatter *f = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSNumberFormatter alloc] init];
        f.numberStyle = NSNumberFormatterDecimalStyle;
        f.locale = [NSLocale currentLocale];
        f.maximumFractionDigits = 12;
        f.minimumFractionDigits = 0;
        f.usesGroupingSeparator = YES;
    });
    return f;
}

#pragma mark - Клавиша

// Кнопка с WP-подсветкой (нажатая — светлее) и опциональным своим глифом
@interface MPKeyButton : UIButton
@property (nonatomic, assign) BOOL isAccent;     // «=»: фон акцент, текст чёрный
@property (nonatomic, assign) BOOL isBackspace;  // глиф ⌫ рисуем в drawRect
@end

@implementation MPKeyButton

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (self.isAccent) {
        UIColor *a = [MPMetroStyle accentColor];
        self.backgroundColor = highlighted ? [a colorWithAlphaComponent:0.75f] : a;
    } else {
        self.backgroundColor = highlighted ? [MPCalcTheme keyPressedColor]
                                           : [MPCalcTheme keyColor];
    }
    if (self.isBackspace) [self setNeedsDisplay];   // цвет глифа следует подсветке
}

// Глиф backspace: контурный пятиугольник со стрелкой влево и крестиком.
// Канонические пропорции ⌫ — прямоугольник 1.35:1 (по высоте клавиши),
// остриё 28% ширины, крест по центру прямоугольной части, скруглённые
// сочленения. В узкой клавише упираем в ширину (ландшафтные ряды низкие).
- (void)drawRect:(CGRect)rect {
    if (!self.isBackspace) return;
    CGFloat gh = rect.size.height * 0.46f;
    CGFloat gw = gh * 1.35f;
    if (gw > rect.size.width * 0.70f) {
        gw = rect.size.width * 0.70f;
        gh = gw / 1.35f;
    }
    CGRect r = CGRectMake((rect.size.width - gw) / 2.0f, (rect.size.height - gh) / 2.0f, gw, gh);
    CGFloat x = r.origin.x, y = r.origin.y, w = r.size.width, h = r.size.height;

    UIColor *ink = self.highlighted ? [MPCalcTheme keyPressedColor] : [MPCalcTheme keyTextColor];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, ink.CGColor);
    CGContextSetFillColorWithColor(ctx, ink.CGColor);
    CGContextSetLineWidth(ctx, 1.6f);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextSetLineCap(ctx, kCGLineCapRound);

    // корпус: остриё слева, прямоугольник справа
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, x, y + h / 2.0f);
    CGPathAddLineToPoint(p, NULL, x + w * 0.28f, y);
    CGPathAddLineToPoint(p, NULL, x + w, y);
    CGPathAddLineToPoint(p, NULL, x + w, y + h);
    CGPathAddLineToPoint(p, NULL, x + w * 0.28f, y + h);
    CGPathCloseSubpath(p);
    CGContextAddPath(ctx, p);
    CGContextStrokePath(ctx);
    CGPathRelease(p);

    // крестик по центру прямоугольной части
    CGFloat cx = x + w * 0.66f, cy = y + h / 2.0f, a = h * 0.22f;
    CGContextMoveToPoint(ctx, cx - a, cy - a);
    CGContextAddLineToPoint(ctx, cx + a, cy + a);
    CGContextMoveToPoint(ctx, cx + a, cy - a);
    CGContextAddLineToPoint(ctx, cx - a, cy + a);
    CGContextStrokePath(ctx);
}

@end

#pragma mark - MPCalcView

@implementation MPCalcView {
    UILabel *_display;      // строка результата/ввода
    UILabel *_memLabel;     // индикатор «M» при непустой памяти
    NSMutableArray *_keys;  // @{btn, row, col, span, sci} — позиции ОБЕИХ раскладок
    // состояние вычислений
    NSMutableArray *_stack;      // @{op, v}: операнд + оператор, ждущий правого операнда
    double _current;             // правое значение (ввод/результат)
    NSMutableString *_entry;     // строка ввода; nil — не вводим
    BOOL _error;                 // ошибка — гасится любой клавишей
    NSString *_errorText;        // «Деление на ноль невозможно» / «Ошибка»
    double _memory;
    BOOL _landscape;             // текущая раскладка сетки (6 колонок в ландшафте)
    // кэш ужатия шрифта дисплея: пересчёт только при смене текста/ширины
    NSString *_dispFontText;
    CGFloat _dispFontWidth;
    CGFloat _dispFontSize;
    NSTimer *_orientTimer;       // опрос датчика в неоднозначном положении
    NSInteger _appliedOrient;    // последняя применённая ориентация (пропуск дублей)
}

+ (MPCalcView *)installedCalcInView:(UIView *)host {
    for (UIView *v in host.subviews) {
        if ([v isKindOfClass:[MPCalcView class]]) {
            [host bringSubviewToFront:v];
            return (MPCalcView *)v;
        }
    }
    MPCalcView *c = [[MPCalcView alloc] initWithFrame:host.bounds];
    [host addSubview:c];
    MPLog(@"[Calc] вьюха установлена (%.0f×%.0f)", host.bounds.size.width, host.bounds.size.height);
    return c;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.tag = MPCalcViewTag;
        _stack = [[NSMutableArray alloc] init];
        _keys = [[NSMutableArray alloc] init];
        _errorText = @"";

        _display = [[UILabel alloc] initWithFrame:CGRectZero];
        _display.backgroundColor = [UIColor clearColor];
        _display.textColor = [UIColor whiteColor];
        _display.textAlignment = NSTextAlignmentRight;   // NSTextAlignment: SDK 10.3 считает UITextAlignment ошибкой
        _display.font = [MPMetroStyle lightFont:64.0f];
        _display.text = @"0";
        [self addSubview:_display];

        _memLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _memLabel.backgroundColor = [UIColor clearColor];
        _memLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.4f];   // приглушённый индикатор
        _memLabel.font = [MPMetroStyle lightFont:16.0f];
        _memLabel.text = @"M";
        _memLabel.hidden = YES;
        [self addSubview:_memLabel];

        [self buildKeys];
        // раскладку делает layoutSubviews — frame задаётся по реальным границам

        // ЛАНДШАФТ: у калькулятора нет UIKit-цикла ротации (CalculatorController —
        // NSObject, нативную ротацию блокирует хук), поворачиваемся сами:
        // устройство → трансформ нашей вьюхи в координатах окна
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deviceOrientationChanged)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_orientTimer invalidate];
}

// Поворот под устройство: портрет — идентичность, ландшафт — повёрнутый кадр
// (480×320, центрированный в окне 320×480). Лежащий горизонтально (FaceUp/Down)
// — не «отбой», а сигнал опрашивать датчик: иначе обратный поворот в портрет
// запаздывал до следующей встряски. Всё с анимацией.
- (void)applyOrientation {
    UIWindow *w = self.window;
    if (w == nil) return;
    UIDeviceOrientation d = [[UIDevice currentDevice] orientation];
    UIInterfaceOrientation o = UIInterfaceOrientationPortrait;
    if (d == UIDeviceOrientationLandscapeLeft || d == UIDeviceOrientationLandscapeRight) {
        o = (d == UIDeviceOrientationLandscapeLeft) ? UIInterfaceOrientationLandscapeLeft
                                                    : UIInterfaceOrientationLandscapeRight;
    } else if (d == UIDeviceOrientationPortraitUpsideDown) {
        o = UIInterfaceOrientationPortraitUpsideDown;
    } else if (d == UIDeviceOrientationPortrait) {
        o = UIInterfaceOrientationPortrait;
    } else {
        // плоско/неизвестно: запускаем короткий опрос датчика — как только
        // положение станет определённым, повернёмся (без ожидания встряски)
        if (_orientTimer == nil) {
            _orientTimer = [NSTimer timerWithTimeInterval:0.25
                                                   target:self
                                                 selector:@selector(pollOrientation)
                                                 userInfo:nil
                                                  repeats:YES];
            [[NSRunLoop mainRunLoop] addTimer:_orientTimer forMode:NSRunLoopCommonModes];
        }
        return;
    }
    if (_orientTimer != nil) {
        [_orientTimer invalidate];
        _orientTimer = nil;
    }
    if (_appliedOrient == (NSInteger)o) return;   // уже в этой ориентации — не дёргаем
    _appliedOrient = (NSInteger)o;
    [[UIApplication sharedApplication] setStatusBarOrientation:o animated:NO];

    CGFloat W = w.bounds.size.width, H = w.bounds.size.height;
    _landscape = UIInterfaceOrientationIsLandscape(o);

    [UIView animateWithDuration:0.25 delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        if (o == UIInterfaceOrientationPortrait) {
            self.transform = CGAffineTransformIdentity;
            self.frame = w.bounds;
        } else if (o == UIInterfaceOrientationPortraitUpsideDown) {
            self.transform = CGAffineTransformMakeRotation(M_PI);
            self.center = w.center;
            self.bounds = CGRectMake(0.0f, 0.0f, W, H);
        } else {
            // устройство повёрнуто влево (верх влево, «домой» справа) — контент
            // против часовой (−90°); вправо — по часовой (+90°)
            CGFloat angle = (o == UIInterfaceOrientationLandscapeLeft) ? -M_PI_2 : M_PI_2;
            self.transform = CGAffineTransformMakeRotation(angle);
            self.center = w.center;
            self.bounds = CGRectMake(0.0f, 0.0f, H, W);   // «ландшафтный» кадр
        }
        // научные клавиши: в ландшафте проявляются, в портрете убираются
        for (NSDictionary *k in self->_keys) {
            UIButton *b = k[@"btn"];
            BOOL sci = [k[@"sci"] boolValue];
            b.userInteractionEnabled = !sci || self->_landscape;
            [b setAlpha:sci ? (self->_landscape ? 1.0f : 0.0f) : 1.0f];
        }
        [self setNeedsLayout];
        [self layoutIfNeeded];   // перестановка сетки в том же анимационном блоке
        [self updateDisplay];    // ужатие шрифта по новой ширине
    } completion:nil];
}

- (void)deviceOrientationChanged {
    [self applyOrientation];
}

// Опрос датчика, пока положение неоднозначное (лежит плашмя): как только
// телефон окажется в определённой ориентации — поворачиваемся
- (void)pollOrientation {
    UIDeviceOrientation d = [[UIDevice currentDevice] orientation];
    if (d == UIDeviceOrientationPortrait || d == UIDeviceOrientationPortraitUpsideDown ||
        d == UIDeviceOrientationLandscapeLeft || d == UIDeviceOrientationLandscapeRight) {
        [self applyOrientation];
    }
}

// Сетка клавиш: базовая 4×6 (референс) + 12 научных (колонки 0–1 ландшафта)
- (void)buildKeys {
    // kind: 0 обычная, 1 акцент («=»), 2 backspace (свой глиф)
    NSArray *rows = @[
        // row 0: память и сброс
        @[@"C",     @(MPTagClear),     @0, @22],
        @[@"MC",    @(MPTagMemClear),  @0, @22],
        @[@"MR",    @(MPTagMemRecall), @0, @22],
        @[@"M+",    @(MPTagMemAdd),    @0, @22],
        // row 1: правки и деление
        @[@"",      @(MPTagBackspace), @2, @26],
        @[@"±",     @(MPTagNegate),    @0, @26],
        @[@"%",     @(MPTagPercent),   @0, @26],
        @[@"÷",     @(MPTagDiv),       @0, @26],
        // rows 2–4: цифры и операторы
        @[@"7", @7, @0, @26], @[@"8", @8, @0, @26], @[@"9", @9, @0, @26], @[@"×", @(MPTagMul), @0, @26],
        @[@"4", @4, @0, @26], @[@"5", @5, @0, @26], @[@"6", @6, @0, @26], @[@"−", @(MPTagSub), @0, @26],
        @[@"1", @1, @0, @26], @[@"2", @2, @0, @26], @[@"3", @3, @0, @26], @[@"+", @(MPTagAdd), @0, @26],
        // row 5: «0» на две колонки, запятая, «=»
        @[@"0", @0, @0, @26],
        @[@",", @(MPTagDot),  @0, @26],
        @[@"=", @(MPTagEquals), @1, @26],
    ];

    NSInteger row = 0, col = 0;
    for (NSArray *spec in rows) {
        MPKeyButton *b = [MPKeyButton buttonWithType:UIButtonTypeCustom];
        b.tag = [spec[1] integerValue];
        NSInteger kind = [spec[2] integerValue];
        b.isAccent = (kind == 1);
        b.isBackspace = (kind == 2);
        b.titleLabel.font = [MPMetroStyle lightFont:[spec[3] floatValue]];
        UIColor *ink = b.isAccent ? [UIColor blackColor] : [MPCalcTheme keyTextColor];
        [b setTitle:spec[0] forState:UIControlStateNormal];
        [b setTitleColor:ink forState:UIControlStateNormal];
        [b setTitleColor:ink forState:UIControlStateHighlighted];
        [b setTitleColor:ink forState:UIControlStateSelected];
        [b addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];

        NSInteger span = (b.tag == 0) ? 2 : 1;   // «0» — на две колонки
        [_keys addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          b, @"btn", @(row), @"row", @(col), @"col",
                          @(span), @"span", @(NO), @"sci", nil]];
        col += span;
        if (col >= MPCalcCols) { col = 0; row++; }
    }

    // научные: колонки 0–1 ландшафтной раскладки (6 колонок), в портрете скрыты
    NSArray *sci = @[
        @[@"sin", @(MPTagSin),   @0, @0],
        @[@"cos", @(MPTagCos),   @1, @0],
        @[@"tan", @(MPTagTan),   @0, @1],
        @[@"ln",  @(MPTagLn),    @1, @1],
        @[@"x²",  @(MPTagSqr),   @0, @2],
        @[@"x^y", @(MPTagPow),   @1, @2],
        @[@"√",   @(MPTagSqrt),  @0, @3],
        @[@"log", @(MPTagLog),   @1, @3],
        @[@"1/x", @(MPTagInv),   @0, @4],
        @[@"x!",  @(MPTagFact),  @1, @4],
        @[@"π",   @(MPTagPi),    @0, @5],
        @[@"e",   @(MPTagEuler), @1, @5],
    ];
    for (NSArray *spec in sci) {
        MPKeyButton *b = [MPKeyButton buttonWithType:UIButtonTypeCustom];
        b.tag = [spec[1] integerValue];
        b.titleLabel.font = [MPMetroStyle lightFont:20.0f];
        UIColor *ink = [MPCalcTheme keyTextColor];
        [b setTitle:spec[0] forState:UIControlStateNormal];
        [b setTitleColor:ink forState:UIControlStateNormal];
        [b setTitleColor:ink forState:UIControlStateHighlighted];
        [b setTitleColor:ink forState:UIControlStateSelected];
        [b addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [_keys addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          b, @"btn", spec[3], @"row", spec[2], @"col",
                          @1, @"span", @(YES), @"sci", nil]];
        b.userInteractionEnabled = NO;
        b.alpha = 0.0f;
    }

    // при первом появлении клавиши серые — фон выставит setHighlighted:NO
    for (NSDictionary *k in _keys) { MPKeyButton *b = k[@"btn"]; b.highlighted = NO; }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    if (W < 100.0f) return;

    NSInteger cols = _landscape ? 6 : MPCalcCols;
    NSInteger basicShift = _landscape ? 2 : 0;   // базовая сетка уезжает вправо

    CGFloat topInset = [MPMetroStyle statusBarInset];
    CGFloat gridTop = topInset + MPCalcDisplayH;
    CGFloat gridH = H - gridTop - MPCalcMargin;
    if (gridH < MPCalcRows * 20.0f) return;   // слишком тесно (промежуточный кадр)

    CGFloat bw = (W - 2.0f * MPCalcMargin - (cols - 1) * MPCalcGap) / cols;
    CGFloat bh = (gridH - (MPCalcRows - 1) * MPCalcGap) / MPCalcRows;

    _display.frame = CGRectMake(MPCalcMargin + 8.0f, topInset + 30.0f,
                                W - 2.0f * MPCalcMargin - 16.0f, MPCalcDisplayH - 40.0f);
    _memLabel.frame = CGRectMake(MPCalcMargin + 8.0f, topInset + 6.0f, 24.0f, 18.0f);

    for (NSDictionary *k in _keys) {
        UIButton *b = k[@"btn"];
        NSInteger r = [k[@"row"] integerValue], c = [k[@"col"] integerValue];
        NSInteger span = [k[@"span"] integerValue];
        BOOL sci = [k[@"sci"] boolValue];
        NSInteger colIndex = sci ? c : (basicShift + c);   // научные — в колонках 0–1
        CGFloat x = MPCalcMargin + colIndex * (bw + MPCalcGap);
        CGFloat y = gridTop + r * (bh + MPCalcGap);
        b.frame = CGRectMake(x, y, bw * span + (span - 1) * MPCalcGap, bh);
    }
    [self updateDisplay];   // ужатие шрифта зависит от ширины
}

#pragma mark - Ввод

- (void)keyTapped:(UIButton *)b {
    NSInteger tag = b.tag;
    if (tag <= 9) { [self digitPressed:tag]; return; }
    switch (tag) {
        case MPTagClear:     [self clearAll];      break;
        case MPTagMemClear:  [self memClear];      break;
        case MPTagMemRecall: [self memRecall];     break;
        case MPTagMemAdd:    [self memAdd];        break;
        case MPTagBackspace: [self backspace];     break;
        case MPTagNegate:    [self negate];        break;
        case MPTagPercent:   [self percent];       break;
        case MPTagDot:       [self dotPressed];    break;
        case MPTagEquals:    [self equals];        break;
        case MPTagDiv:       [self operatorPressed:@"÷"]; break;
        case MPTagMul:       [self operatorPressed:@"×"]; break;
        case MPTagSub:       [self operatorPressed:@"−"]; break;
        case MPTagAdd:       [self operatorPressed:@"+"]; break;
        case MPTagPow:       [self operatorPressed:@"^"]; break;
        case MPTagSin:       [self unaryPressed:@"sin"];  break;
        case MPTagCos:       [self unaryPressed:@"cos"];  break;
        case MPTagTan:       [self unaryPressed:@"tan"];  break;
        case MPTagLn:        [self unaryPressed:@"ln"];   break;
        case MPTagLog:       [self unaryPressed:@"log"];  break;
        case MPTagSqrt:      [self unaryPressed:@"√"];    break;
        case MPTagSqr:       [self unaryPressed:@"x²"];   break;
        case MPTagInv:       [self unaryPressed:@"1/x"];  break;
        case MPTagFact:      [self unaryPressed:@"x!"];   break;
        case MPTagPi:        [self constantPressed:M_PI]; break;
        case MPTagEuler:     [self constantPressed:M_E];  break;
    }
}

- (double)entryValue {
    return [_entry doubleValue];   // вход всегда с «.» — doubleValue понимает
}

// Ввод строку в число: правое значение становится результатом ввода
- (void)commitEntry {
    if (_entry == nil) return;
    _current = [self entryValue];
    _entry = nil;
}

- (void)digitPressed:(NSInteger)d {
    if (_error) [self clearAll];
    if (_entry == nil) _entry = [[NSMutableString alloc] init];
    // ведущий ноль не дублируем: «0» + цифра заменяет ноль
    if ([_entry isEqualToString:@"0"]) [_entry setString:@""];
    if ([_entry length] >= 15) return;   // лимит разрядов как в WP
    [_entry appendFormat:@"%d", (int)d];
    [self updateDisplay];
}

- (void)dotPressed {
    if (_error) [self clearAll];
    if (_entry == nil) _entry = [[NSMutableString alloc] initWithString:@"0"];
    if ([_entry rangeOfString:@"."].location == NSNotFound) [_entry appendString:@"."];
    [self updateDisplay];
}

// Дочитывает стек: применяет операторы с приоритетом >= prec
// (для правоассоциативного «^» равный приоритет НЕ дочитывается)
- (void)applyStackTo:(int)prec rightAssoc:(BOOL)ra {
    while (_stack.count > 0) {
        NSDictionary *top = [_stack lastObject];
        int topPrec = MPCalcPrec(top[@"op"]);
        if (topPrec < prec || (topPrec == prec && ra)) break;
        double r = MPCalcApply([top[@"v"] doubleValue], top[@"op"], _current);
        if (isnan(r)) { [self failWithText:@"Деление на ноль невозможно"]; return; }
        _current = r;
        [_stack removeLastObject];
    }
}

- (void)operatorPressed:(NSString *)op {
    if (_error) return;
    [self commitEntry];
    [self applyStackTo:MPCalcPrec(op) rightAssoc:([op isEqualToString:@"^"])];
    if (_error) return;
    [_stack addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                       [NSNumber numberWithDouble:_current], @"v", op, @"op", nil]];
    [self updateDisplay];
}

// Унарные научные функции: применяются к текущему значению немедленно
- (void)unaryPressed:(NSString *)f {
    if (_error) return;
    [self commitEntry];
    double v = _current, r = v;
    BOOL ok = YES;
    if ([f isEqualToString:@"sin"])      r = sin(v * M_PI / 180.0);
    else if ([f isEqualToString:@"cos"]) r = cos(v * M_PI / 180.0);
    else if ([f isEqualToString:@"tan"]) r = tan(v * M_PI / 180.0);
    else if ([f isEqualToString:@"ln"])  { ok = v > 0.0;  r = log(v); }
    else if ([f isEqualToString:@"log"]) { ok = v > 0.0;  r = log10(v); }
    else if ([f isEqualToString:@"√"])   { ok = v >= 0.0; r = sqrt(v); }
    else if ([f isEqualToString:@"x²"])  r = v * v;
    else if ([f isEqualToString:@"1/x"]) { ok = v != 0.0; r = 1.0 / v; }
    else if ([f isEqualToString:@"x!"]) {
        ok = (v >= 0.0 && v == floor(v) && v <= 170.0);
        if (ok) {
            r = 1.0;
            for (double i = 2.0; i <= v; i += 1.0) r *= i;
        }
    }
    if (!ok || isnan(r) || isinf(r)) { [self failWithText:@"Ошибка"]; return; }
    _current = r;
    _entry = nil;
    [self updateDisplay];
}

// Константы π и e: заменяют текущее значение
- (void)constantPressed:(double)c {
    if (_error) [self clearAll];
    [self commitEntry];
    _current = c;
    _entry = nil;
    [self updateDisplay];
}

- (void)equals {
    if (_error) return;
    [self commitEntry];
    [self applyStackTo:0 rightAssoc:NO];
    if (_error) return;
    [self updateDisplay];
}

- (void)clearAll {
    [_stack removeAllObjects];
    _current = 0.0;
    _entry = nil;
    _error = NO;
    [self updateDisplay];
}

- (void)negate {
    if (_error) return;
    if (_entry != nil) {
        if ([_entry hasPrefix:@"-"]) [_entry replaceCharactersInRange:NSMakeRange(0, 1) withString:@""];
        else [_entry insertString:@"-" atIndex:0];
    } else {
        _current = -_current;
    }
    [self updateDisplay];
}

- (void)backspace {
    if (_error) { [self clearAll]; return; }
    if (_entry == nil) {
        // правим результат: переводим в строку ввода и стираем разряд
        _entry = [[NSMutableString alloc] initWithFormat:@"%.12g", _current];
    }
    if ([_entry length] > 0) [_entry deleteCharactersInRange:NSMakeRange([_entry length] - 1, 1)];
    if ([_entry length] == 0 || [_entry isEqualToString:@"-"]) [_entry setString:@"0"];
    [self updateDisplay];
}

- (void)percent {
    if (_error) return;
    [self commitEntry];
    _current = _current / 100.0;
    [self updateDisplay];
}

- (void)failWithText:(NSString *)text {
    _error = YES;
    _errorText = text;
    _entry = nil;
    [_stack removeAllObjects];
    [self updateDisplay];
}

#pragma mark - Память

- (void)memClear { _memory = 0.0; [self updateDisplay]; }

- (void)memRecall {
    if (_error) [self clearAll];
    _current = _memory;
    _entry = nil;
    [self updateDisplay];
}

- (void)memAdd {
    if (_error) return;
    [self commitEntry];
    _memory += _current;
    [self updateDisplay];
}

#pragma mark - Дисплей

// Ввод с группировкой разрядов и локальной запятой («12345.6» → «12 345,6»)
- (NSString *)formattedEntry {
    NSString *s = _entry;
    NSString *sign = @"";
    if ([s hasPrefix:@"-"]) { sign = @"-"; s = [s substringFromIndex:1]; }
    NSArray *parts = [s componentsSeparatedByString:@"."];
    NSString *intPart = [parts count] > 0 ? parts[0] : @"0";
    NSString *fracPart = [parts count] > 1 ? parts[1] : @"";

    NSNumberFormatter *f = MPCalcFormatter();
    NSString *group = f.groupingSeparator ?: @" ";
    NSString *decimal = f.decimalSeparator ?: @",";

    NSMutableString *grouped = [[NSMutableString alloc] init];
    NSInteger n = [intPart length];
    for (NSInteger i = 0; i < n; i++) {
        if (i > 0 && (n - i) % 3 == 0) [grouped appendString:group];
        [grouped appendFormat:@"%C", (unichar)[intPart characterAtIndex:i]];
    }
    NSString *res = [sign stringByAppendingString:grouped];
    if ([parts count] > 1) res = [res stringByAppendingFormat:@"%@%@", decimal, fracPart];
    return res;
}

- (NSString *)formattedDouble:(double)v {
    if (isnan(v)) return @"Ошибка";
    // за пределами 15 значащих разрядов — экспоненциальная запись (как WP)
    if (fabs(v) >= 1e15 || (v != 0.0 && fabs(v) < 1e-9)) {
        NSString *s = [NSString stringWithFormat:@"%.8g", v];
        return [s stringByReplacingOccurrencesOfString:@"." withString:MPCalcFormatter().decimalSeparator ?: @","];
    }
    return [MPCalcFormatter() stringFromNumber:[NSNumber numberWithDouble:v]] ?: @"0";
}

- (void)updateDisplay {
    if (_error) {
        _display.text = _errorText;
    } else if (_entry != nil) {
        _display.text = [self formattedEntry];
    } else {
        _display.text = [self formattedDouble:_current];
    }
    _memLabel.hidden = (_memory == 0.0);

    // ужатие: 64 → 24, чтобы любая строка влезла в дисплей.
    // Оптимизация: цикл sizeWithFont (до ~20 замеров) гоняем только при
    // смене текста или ширины — на каждый тап/кадр анимации он и лагал.
    CGFloat avail = _display.bounds.size.width - 8.0f;
    if (avail < 40.0f) return;   // кадр без раскладки — ужмём на следующем
    if (_display.text == nil ||
        ![_display.text isEqualToString:_dispFontText] ||
        fabsf(avail - _dispFontWidth) > 0.5f) {
        CGFloat size = _error ? 24.0f : 64.0f;
        while (size > 24.0f &&
               [_display.text sizeWithFont:[MPMetroStyle lightFont:size]].width > avail) {
            size -= 2.0f;
        }
        _dispFontSize = size;
        _dispFontText = [_display.text copy];
        _dispFontWidth = avail;
    }
    _display.font = [MPMetroStyle lightFont:_dispFontSize];
}

@end
