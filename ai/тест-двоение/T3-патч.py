# -*- coding: utf-8 -*-
# ТЕСТ 3: параллакс 0 вместо 0.4 (остальное как в T1: без растеризации).
# Коэффициент параллакса в проекте ОДИН: MPClockPivotView.m, applyBody
# (строка «x * 0.4f»); докат и cslow идут через тот же applyBody.
# «0.4f» в MPClockTheme.m — это альфа цвета disabledColor, НЕ трогать.
# Применить:  python3 T3-патч.py
# Откат:      python3 T3-патч.py --revert
import io, os, sys

REVERT = '--revert' in sys.argv
P = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'tweak', 'AppDesigns', 'Clock', 'MPClockPivotView.m'))
s = io.open(P, encoding='utf-8').read()

# страховка: точка параллакса ровно одна (иная — код уехал)
N = s.count('CATransform3DMakeTranslation(x * 0.4f')
assert N == 1, 'ожидалась 1 точка параллакса, найдено %d — править вручную' % N

def apply(old, new, tag):
    global s
    a, b = (new, old) if REVERT else (old, new)
    if b in s:
        print(tag, ': уже в целевом состоянии'); return
    assert a in s, tag + ': ЯКОРЬ НЕ НАЙДЕН'
    s = s.replace(a, b, 1)
    print(tag, ': ок' + (' (откат)' if REVERT else ''))

apply('static NSString * const MPClockBuildTag = @"T1-БЕЗ-РАСТЕРИЗАЦИИ";',
      'static NSString * const MPClockBuildTag = @"T3-ПАРАЛЛАКС-0";',
      'маркер T3')

apply('''        pg.layer.transform = CATransform3DMakeTranslation(x * 0.4f, 0.0f, 0.0f);''',
'''        pg.layer.transform = CATransform3DMakeTranslation(x * 0.0f, 0.0f, 0.0f);   // ТЕСТ 3: параллакс 0''',
      'параллакс 0')

io.open(P, 'w', encoding='utf-8').write(s)
print('T3 %s. Далее: make package && dev.sh install && killall MobileTimer' % ('откачен' if REVERT else 'применён'))
