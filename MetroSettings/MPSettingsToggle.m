#import "MPSettingsToggle.h"
#import "../MetroLauncher/MPMetroStyle.h"
#import <objc/runtime.h>

@implementation MPSettingsToggle {
    UISwitch *_switch;
    UIView   *_fill;         // акцентная заливка (включён)
    UIView   *_knob;         // белый квадратный бегунок
}

+ (MPSettingsToggle *)attachedToggleForSwitch:(UISwitch *)sw {
    static char kToggleKey;
    MPSettingsToggle *t = objc_getAssociatedObject(sw, &kToggleKey);
    if (t == nil) {
        t = [[MPSettingsToggle alloc] initWithFrame:sw.frame];
        t->_switch = sw;
        [sw.superview addSubview:t];
        sw.hidden = YES;                        // оригинал жив, но не виден
        objc_setAssociatedObject(sw, &kToggleKey, t, OBJC_ASSOCIATION_RETAIN);
    }
    return t;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // WP8: маленький серый прямоугольник, без рамки и заливки
        self.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.38f];

        _knob = [[UIView alloc] initWithFrame:CGRectZero];
        _knob.backgroundColor = [UIColor whiteColor];
        [self addSubview:_knob];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(toggleTapped)];
        [self addGestureRecognizer:tap];

        [self syncFromSwitch];
    }
    return self;
}

- (void)toggleTapped {
    if (_switch == nil) return;
    BOOL newOn = !_switch.on;
    [_switch setOn:newOn animated:NO];
    // PS-логика слушает ValueChanged оригинального свитча — пересылаем
    [_switch sendActionsForControlEvents:UIControlEventValueChanged];
    [self syncFromSwitch];
}

- (void)syncFromSwitch {
    if (_switch == nil) return;
    BOOL on = _switch.on;
    // WP 8.1: включённый тумблер — акцентный, выключенный — серый.
    // Цвет меняем ВНЕ анимации, чтобы не мигал при каждом проходе layout
    UIColor *bg = on ? [MPMetroStyle accentColor]
                     : [UIColor colorWithWhite:1.0f alpha:0.38f];
    if (![self.backgroundColor isEqual:bg]) self.backgroundColor = bg;
    CGFloat side = self.bounds.size.height - 4.0f;   // белый квадрат почти во всю высоту
    CGFloat knobX = on ? (self.bounds.size.width - side - 2.0f) : 2.0f;
    [UIView animateWithDuration:0.15 animations:^{
        _knob.frame = CGRectMake(knobX, 2.0f, side, side);
    }];
}

- (void)syncFrameFromSwitch {
    if (_switch == nil) return;
    CGRect f = _switch.frame;
    // Тумблер живёт в contentView, а ширина у него бывает разной (211 у свитч-ячеек,
    // 300 у обычных, 320 у кастомных). Считаем от ширины ЯЧЕЙКИ и вычитаем сдвиг
    // контейнера — иначе на узком contentView тумблер уезжал на текст.
    UIView *host = self.superview ?: _switch.superview;
    UIView *cellView = host.superview ?: host;
    CGFloat cellW = cellView.bounds.size.width;
    CGFloat hostX = host.frame.origin.x;
    CGFloat x = cellW - 46.0f - 16.0f - hostX;
    if (x < 0.0f) x = f.origin.x - 2.0f;
    self.frame = CGRectMake(x, CGRectGetMidY(f) - 11.0f, 46.0f, 22.0f);
    [self syncFromSwitch];   // пересчитать бегунок под новые границы
}

@end
