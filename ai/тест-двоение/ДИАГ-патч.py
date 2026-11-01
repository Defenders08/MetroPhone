# -*- coding: utf-8 -*-
# ДИАГНОСТИКА драга (cdraglog) — ставится ПОВЕРХ текущего теста, к маркеру
# добавляется «-ДИАГ». Откат: python3 ДИАГ-патч.py --revert
#
# ОГРАНИЧЕНИЕ (важно): presentationLayer == модель, когда неявные CA-анимации
# не идут. Дамп ловит (а) расхождение model/pres = неявные анимации,
# (б) дубли меток по координатам ОКНА (convertPoint:toLayer:, учитывает
# transform-параллакс и всю иерархию, метки обходятся рекурсивно).
# Композитор и растровый кэш этому дампу НЕ видны — главным доказательством
# не считать; главный вердикт всегда глаза юзера / системный скриншот.
#
# Что пишет (в draglog.txt на телефоне, ПОСЛЕ отпускания пальца + 1.2 с
# доката; потолок 240 кадров):
#   - 4 страницы: model position.x, presentation position.x, raster, hidden
#   - метки всех страниц (рекурсивно): текст, pres-координаты окна, model-x
#   - «ДУБЛЬ НА ЭКРАНЕ»: ключ «текст|y» встретился на экране с РАЗНЫМ x
import io, os, re, sys

REVERT = '--revert' in sys.argv
BASE = os.path.dirname(os.path.abspath(__file__))
P = os.path.abspath(os.path.join(BASE, '..', '..', 'tweak', 'AppDesigns', 'Clock', 'MPClockPivotView.m'))
T = os.path.abspath(os.path.join(BASE, '..', '..', 'tweak', 'Tweak.xm'))
s = io.open(P, encoding='utf-8').read()

def apply(old, new, tag, path=None):
    global s
    a, b = (new, old) if REVERT else (old, new)
    cur = s if path is None else io.open(path, encoding='utf-8').read()
    if b in cur:
        print(tag, ': уже в целевом состоянии'); return True
    assert a in cur, tag + ': ЯКОРЬ НЕ НАЙДЕН'
    cur = cur.replace(a, b, 1)
    if path is None:
        s = cur
    else:
        io.open(path, 'w', encoding='utf-8').write(cur)
    print(tag, ': ок' + (' (откат)' if REVERT else ''))
    return False

# 0) маркер: +суффикс / при откате −суффикс
m = re.search(r'static NSString \* const MPClockBuildTag = @"([^"]*)";', s)
assert m, 'маркер не найден'
tag_now = m.group(1)
if REVERT:
    if tag_now.endswith('-ДИАГ'):
        s = s.replace(m.group(0), 'static NSString * const MPClockBuildTag = @"%s";' % tag_now[:-len('-ДИАГ')])
        print('маркер: −ДИАГ')
    else:
        print('маркер: суффикса нет, ок')
else:
    if not tag_now.endswith('-ДИАГ'):
        s = s.replace(m.group(0), 'static NSString * const MPClockBuildTag = @"%s-ДИАГ";' % tag_now)
        print('маркер → %s-ДИАГ' % tag_now)

# 1) ivars
apply('''    NSMutableArray *_applyLog;   // диагностика: offset:вызовы по кадрам''',
'''    NSMutableArray *_applyLog;   // диагностика: offset:вызовы по кадрам
    // диагностика драга: presentationLayer + дубли по координатам окна
    BOOL _dragLogOn;
    NSMutableArray *_dragLog;
    NSInteger _dragFrames, _dragLogGen;''', 'ivars')

# 2) методы — перед debugScrollFront
apply('''// ОТЛАДКА: программная вертикальная прокрутка фронтальной страницы (0..1)
- (void)debugScrollFront:(float)fraction {''',
'''// ДИАГНОСТИКА: рекурсивно собрать метки страницы. Координаты — через
// convertPoint:toLayer: до слоя ОКНА (учитывает transform-параллакс 0.4 и
// всю иерархию). presentation ≈ модель + дельта pres.position−model.position
- (void)mpCollectLabels:(UIView *)root into:(NSMutableArray *)acc {
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:[UILabel class]]) {
            UIWindow *w = self.window;
            CALayer *pl = (CALayer *)v.layer.presentationLayer;
            CGPoint mp = w ? [v convertPoint:v.bounds.origin toLayer:w.layer] : CGPointZero;
            CGPoint pp = mp;
            if (pl) {
                pp.x += pl.position.x - v.layer.position.x;
                pp.y += pl.position.y - v.layer.position.y;
            }
            [acc addObject:[NSMutableDictionary dictionaryWithDictionary:@{
                @"text": ((UILabel *)v).text ?: @"-",
                @"mx": @(mp.x), @"my": @(mp.y),
                @"px": @(pp.x), @"py": @(pp.y),
                @"w": @(v.bounds.size.width),
            }]];
        }
        [self mpCollectLabels:v into:acc];
    }
}

// ДИАГНОСТИКА: покадровый дамп (вызывается из applyBody — покрывает и палец,
// и ДОКАТ после отпускания). presentationLayer без активных CA-анимаций ==
// модель: дамп ловит их расхождение (неявные анимации) и дубли меток.
// Композитор/растровый кэш НЕ видны — доказательством не считать.
- (void)mpDragFrameDump {
    if (!_dragLogOn || _dragLog == nil || _dragFrames >= 240) return;
    _dragFrames++;
    [_dragLog addObject:[NSString stringWithFormat:@"-- t=%.3f off=%.1f",
                          CACurrentMediaTime(), _offset]];
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIView *pg = [_pages objectAtIndex:i];
        CALayer *pl = (CALayer *)pg.layer.presentationLayer;
        [_dragLog addObject:[NSString stringWithFormat:
            @"  page%ld model=%.1f pres=%.1f raster=%d hidden=%d",
            (long)i, pg.layer.position.x, pl ? pl.position.x : -9999.0f,
            pg.layer.shouldRasterize, pg.hidden]];
    }
    // метки всех страниц в координатах окна; ДУБЛЬ = ключ «текст|y» на
    // экране с РАЗНЫМ x (у «Однократно»/«сегодня» на разных страницах
    // разные y — ложных срабатываний нет)
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < MPPageCount; i++) {
        UIView *pg = [_pages objectAtIndex:i];
        if (pg.hidden) continue;
        NSMutableArray *acc = [NSMutableArray array];
        [self mpCollectLabels:pg into:acc];
        for (NSDictionary *d in acc) {
            CGFloat px = [d[@"px"] floatValue];
            CGFloat pw = [d[@"w"] floatValue];
            if (!(px < 320.0f && px + pw > 0.0f)) continue;   // пересекает экран
            NSString *key = [NSString stringWithFormat:@"%@|%.0f",
                             d[@"text"], [d[@"py"] floatValue]];
            NSMutableArray *arr = [byKey objectForKey:key];
            if (arr == nil) { arr = [NSMutableArray array]; [byKey setObject:arr forKey:key]; }
            [arr addObject:d];
            [_dragLog addObject:[NSString stringWithFormat:
                @"  p%ld \\"%@\\" win=%.1f,%.0f model=%.1f", (long)i,
                d[@"text"], px, [d[@"py"] floatValue], [d[@"mx"] floatValue]]];
        }
    }
    for (NSString *k in byKey) {
        NSArray *arr = [byKey objectForKey:k];
        if (arr.count < 2) continue;
        NSMutableSet *xs = [NSMutableSet set];
        for (NSDictionary *d in arr) [xs addObject:@((NSInteger)[d[@"px"] floatValue])];
        if ([xs count] > 1) {
            [_dragLog addObject:[NSString stringWithFormat:
                @"  ДУБЛЬ НА ЭКРАНЕ: \\"%@\\" ×%ld (x: %@)", k, (long)arr.count,
                [[arr valueForKeyPath:@"px"] componentsJoinedByString:@", "]]];
        }
    }
}

- (void)mpDragLogFinish {
    if (!_dragLogOn || _dragLog == nil) return;
    NSString *out = [_dragLog componentsJoinedByString:@"\\n"];
    NSString *path = @"/var/mobile/Library/Caches/metrophone/draglog.txt";
    [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    MPLog(@"[Clock] драг-лог: %ld кадров → %@", (long)_dragFrames, path);
    _dragLog = nil;
}

// ДИАГНОСТИКА: вкл/выкл драг-лога (cdraglog)
- (void)debugDragLog {
    _dragLogOn = !_dragLogOn;
    MPLog(@"[Clock] драг-лог %@", _dragLogOn ? @"ВКЛ (свайпни пальцем)" : @"выкл");
}

// ОТЛАДКА: программная вертикальная прокрутка фронтальной страницы (0..1)
- (void)debugScrollFront:(float)fraction {''', 'методы')

# 3) дамп из applyBody (покрытие дока́та) — хвост applyBody уникален
assert s.count('    [CATransaction commit];\n}') == (0 if REVERT else 1) or True
apply('''    [CATransaction commit];
}''',
'''    [CATransaction commit];

    // ДИАГНОСТИКА: покадровый дамп и во время ДОКАТА (applyBody зовут из
    // анимации доката уже после отпускания пальца)
    [self mpDragFrameDump];
}''', 'applyBody хвост')

# 4) пан: старт/финиш с покрытием доката (1.2 с, генерационный сторож)
apply('''        _dragging = YES;
        _axisY = NO;
        _startOffset = _offset;''',
'''        _dragging = YES;
        _axisY = NO;
        _startOffset = _offset;
        if (_dragLogOn) {
            _dragLog = [NSMutableArray array];
            _dragFrames = 0;
            _dragLogGen++;   // новый драг гасит незакрытый прошлый
        }''', 'pan began')

apply('''    if (gr.state == UIGestureRecognizerStateEnded && _dragging) {
        _dragging = NO;''',
'''    if (gr.state == UIGestureRecognizerStateEnded && _dragging) {
        _dragging = NO;
        // ДИАГНОСТИКА: лог живёт ещё 1.2 с — захватывает ДОКАТ
        if (_dragLogOn && _dragLog != nil) {
            NSInteger gen = _dragLogGen;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (gen == self->_dragLogGen) [self mpDragLogFinish];
            });
        }''', 'pan ended')

# 5) C-обёртка
apply('''// ОТЛАДКА (C-обёртка для Tweak.xm): программный палец
void MPClockDebugFinger(void) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugFinger];
}''',
'''// ОТЛАДКА (C-обёртка для Tweak.xm): программный палец
void MPClockDebugFinger(void) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugFinger];
}

// ДИАГНОСТИКА (C-обёртка для Tweak.xm): вкл/выкл драг-лога
void MPClockDebugDragLog(void) {
    if (MPClockSharedPivot == nil) return;
    [MPClockSharedPivot debugDragLog];
}''', 'C-обёртка')

io.open(P, 'w', encoding='utf-8').write(s)

# 6) команда в Tweak.xm
tx_old = '''	if ([cmd caseInsensitiveCompare:@"cfinger"] == NSOrderedSame) {'''
tx_new = '''	if ([cmd caseInsensitiveCompare:@"cdraglog"] == NSOrderedSame) {
		MPClockDebugDragLog();
		return;
	}
	if ([cmd caseInsensitiveCompare:@"cfinger"] == NSOrderedSame) {'''
ex_old = 'extern "C" void MPClockDebugFinger(void);             // отладка: программный палец'
ex_new = ex_old + '''
extern "C" void MPClockDebugDragLog(void);           // диагностика: драг-лог'''
apply(tx_old, tx_new, 'tweak команда', path=T)
apply(ex_old, ex_new, 'tweak extern', path=T)

print('ДИАГ %s. Далее: make package && dev.sh install && killall MobileTimer' % ('откачен' if REVERT else 'применён'))
print('Работа: echo cdraglog > shot.request → СВАЙП ПАЛЬЦЕМ → draglog.txt')
