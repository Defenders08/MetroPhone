# -*- coding: utf-8 -*-
# ТЕСТ 2: скрыть страницы 1–3, оставить только «Мировые часы».
# База: состояние T1 (растеризация уже выключена).
# Юзер смотрит ТОЛЬКО на строки списка (шапку игнорировать).
# Применить:  python3 T2-патч.py
# Откат:      python3 T2-патч.py --revert   (ровно обратно в T1)
import io, os, sys

REVERT = '--revert' in sys.argv
P = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'tweak', 'AppDesigns', 'Clock', 'MPClockPivotView.m'))
s = io.open(P, encoding='utf-8').read()

def apply(old, new, tag):
    global s
    a, b = (new, old) if REVERT else (old, new)
    if b in s:
        print(tag, ': уже в целевом состоянии'); return
    assert a in s, tag + ': ЯКОРЬ НЕ НАЙДЕН — код уехал, править вручную'
    s = s.replace(a, b, 1)
    print(tag, ': ок' + (' (откат)' if REVERT else ''))

apply('static NSString * const MPClockBuildTag = @"T1-БЕЗ-РАСТЕРИЗАЦИИ";',
      'static NSString * const MPClockBuildTag = @"T2-ОДНА-СТРАНИЦА";',
      'маркер T2')

apply('''            [_pagesLayer addSubview:pg];
            _pageHome[i] = pg.center;
        }''',
'''            [_pagesLayer addSubview:pg];
            _pageHome[i] = pg.center;
        }
        // ТЕСТ 2: видна ТОЛЬКО страница 0 — двойник в СТРОКАХ СПИСКА остался,
        // значит он внутри одной страницы; исчез — его даёт кольцо.
        // (шапку/заголовки при тесте игнорировать)
        for (NSInteger i = 1; i < MPPageCount; i++) {
            [[_pages objectAtIndex:i] setHidden:YES];
        }''',
      'скрытие 1–3')

io.open(P, 'w', encoding='utf-8').write(s)
print('T2 %s. Далее: make package && dev.sh install && killall MobileTimer' % ('откачен' if REVERT else 'применён'))
