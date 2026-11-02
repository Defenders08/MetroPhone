// MPAnimationConstants.h — все длительности, кривые, перспективы и таймауты
// анимаций MetroPhone в одном месте (см. ai/WP-ANIMATIONS.md §3).
// Подстройка движения всего твика — правкой этого файла.
#import <QuartzCore/QuartzCore.h>

#pragma mark - Turnstile (запуск/закрытие приложений, лок/анлок)

static const NSTimeInterval MPAnimTurnstileOutDur = 0.25;   // выезд лаунчера 0°→+50°
// Въезд −50°→0°: 0.32 с на элемент + стаггер рядов 22 мс и внутри ряда 5 мс —
// общий въезд ≈ 0.5 с от старта
static const NSTimeInterval MPAnimTurnstileInDur  = 0.32;
static const CGFloat MPAnimTurnstileOutAngle = 50.0f;
// −50°: старт-поза въезда. Видна сразу (alpha 0.3), но читается как наклон
static const CGFloat MPAnimTurnstileInAngle  = -50.0f;
static const CGFloat MPAnimPerspective = -1.0f / 500.0f;    // m34 для 3D-поворотов

// Фирменная кривая ExponentialEase exp6 — кубические аппроксимации (WP-ANIMATIONS.md §3.2)
static inline CAMediaTimingFunction *MPAnimEaseIn(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.69f:0.0f:0.83f:0.38f];
}
static inline CAMediaTimingFunction *MPAnimEaseOut(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.17f:0.62f:0.31f:1.0f];
}
// Мягкий WP-ease-out для въезда плиток: резче разгон, длинный хвост без overshoot
static inline CAMediaTimingFunction *MPAnimEaseOutWP(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.1f:0.9f:0.2f:1.0f];
}
// Поворот вокруг вертикальной оси с перспективой; шарнир задаёт anchorPoint слоя
static inline CATransform3D MPAnimTurnstileTransform(CGFloat degrees) {
    CATransform3D t = CATransform3DIdentity;
    t.m34 = MPAnimPerspective;
    return CATransform3DRotate(t, degrees * (CGFloat)M_PI / 180.0f, 0.0f, 1.0f, 0.0f);
}

#pragma mark - Таймауты переходов

static const NSTimeInterval MPAnimLaunchWatchdog = 3.0;     // сторож неудачного запуска (1.8 с мало: холодный старт Настроек дольше)
static const NSTimeInterval MPAnimWidgetInsurance = 3.0;    // страховка виджета с URL-целью
static const NSTimeInterval MPAnimLockscreenWaitCap = 1.0;  // предел ожидания скрытия локскрина при анлоке

// Свайп-анлок: Turnstile стартует В МОМЕНТ отпускания пальца (t=0), вместе со
// слайдом — без таймеров, прогресса и опроса. Опрос подтверждает анлок только
// для закрытия окна локскрина в конце слайда. Плитки при этом стартуют ПОЗЖЕ
// самого слайда: задержка через beginTime их CA-анимаций (≈1/3 слайда), без
// dispatch_after; до beginTime модель плитки в стартовой позе (alpha 0).
static const NSTimeInterval MPAnimUnlockEntryDelay = 0.12;  // пауза перед turnstile (dispatch_after на main)

#pragma mark - Возврат из приложения (ранний feather-въезд + поворот окна)

// Окно приложения складывается в −80° параллельно въезду плиток (паузы нет —
// один непрерывный поворот). Feather-въезд стартует СРАЗУ по Home, пока окно
// ещё на экране: лаунчер остаётся ПОД окном, двойная экспозиция невозможна
// физически. Плитки стартуют с противоположной стороны (+50°), въезд чуть дольше
// и мягче выезда. Опрос frontmost только ФИКСИРУЕТ факт ухода (setHidden: на
// iOS 6 молчит): ушло → поднять лаунчер на фронт; не ушло за MPAnimReturnPollCap
// → тихий откат в позу ожидания (под окном невидим).
static const NSTimeInterval MPAnimReturnPollInterval = 0.02; // шаг опроса frontmost
static const NSTimeInterval MPAnimReturnPollCap = 0.8;       // предел опроса → откат раннего въезда
static const NSTimeInterval MPAnimReturnGrace = 0.06;        // пауза после ухода окна перед фиксацией

#pragma mark - Turnstile запуска/закрытия приложения (петля у левого края, 0.22.32)

// Выезд Start при запуске: целый слой 0°→+50° как дверь (петля — левый край,
// anchorPoint корня выставлен при установке). Без feather-рядов: «плитки
// хаотично схлопываются» → одна цельная дверь.
static const NSTimeInterval MPAnimStartFoldDur = 0.25;

// Окно приложения живёт в СВОЁМ процессе — поворачивается твиком изнутри
// приложения (хук UIWindow makeKeyAndVisible + Darwin-сигналы из SB).
// Открытие: старт почти ребром (−80°), раскрытие 0.35 с — быстрый старт,
// мягкий докат. Закрытие: окно складывается 0°→−80° за 0.25 с, резко.
static const CGFloat MPAnimAppInAngle = -80.0f;
static const NSTimeInterval MPAnimAppInDur = 0.35;
static const NSTimeInterval MPAnimAppCloseDur = 0.25;

// Сплэш в позе ожидания показывается только если окно приложения не появилось
// к концу выезда Start (холодный спавн): опрос frontmost с этим шагом.
static const NSTimeInterval MPAnimSplashWindowPoll = 0.1;

#pragma mark - WP-сплэш запуска (панель в хост-окне и в окне приложения)

// Одна и та же панель: фон = цвет плитки, по центру иконка + название приложения
// (как настоящие WP-приложения). В хост-окне закрывает паузу спавна, копия в окне
// приложения — системный zoom и белый Default.png с первого кадра.
static const CGFloat MPAnimSplashIconSize = 72.0f;        // сторона иконки
static const CGFloat MPAnimSplashNameSize = 26.0f;        // кегль названия
static const CGFloat MPAnimSplashNameGap = 16.0f;         // воздух между иконкой и названием

// Снятие копии из окна приложения: каждое добавление полноразмерного контента
// окна переносит снятие на MPAnimSplashHold вперёд (Default.png добавился раньше
// настоящего контента — ждём его), фейд MPAnimSplashFadeOut; MPAnimSplashCap —
// жёсткий предел от приклейки, чтобы не накрыть работающее приложение навсегда.
static const NSTimeInterval MPAnimSplashHold = 0.40;
static const NSTimeInterval MPAnimSplashFadeOut = 0.15;
static const NSTimeInterval MPAnimSplashCap = 2.0;

// Сплэш в ПРОЦЕССЕ приложения (окно приложения живёт в чужом процессе — из
// SpringBoard его не накрыть). Ставится на makeKeyAndVisible, снимается по
// фиксированной паузе: первый рендер приложения остаётся под панелью.
static const NSTimeInterval MPAnimSplashAppHold = 0.80;

#pragma mark - Feather-стаггер (по строкам, WP8.1 TurnstileFeather)

static const NSTimeInterval MPAnimFeatherStagger = 0.022;   // сдвиг на ряд (22 мс)
static const NSTimeInterval MPAnimFeatherIntraStagger = 0.005; // сдвиг внутри ряда (5 мс/плитку)
static const CGFloat MPAnimFeatherHinge = -0.2f;            // шарнир строки: anchorPoint.x (левее левого края)

#pragma mark - Флип живых плиток

static const NSTimeInterval MPAnimFlipHalfDur = 0.2;        // половина флипа (к ребру / от ребра)
static const NSInteger MPAnimFlipMaxConcurrent = 3;         // одновременных флипов на весь экран (бюджет A4)
static const NSTimeInterval MPAnimFlipRetryMin = 0.3;       // откладывание лишнего флипа
static const NSTimeInterval MPAnimFlipRetryMax = 1.0;

#pragma mark - Tilt-нажатие плиток

static const CGFloat MPAnimTiltMaxDegrees = 6.0f;           // максимум наклона к пальцу (WP8.1 Start)
static const CGFloat MPAnimTiltScale = 0.97f;               // лёгкое сжатие при нажатии
static const NSTimeInterval MPAnimTiltPressDur = 0.08;      // доворот в наклон (живой, без цикла кадров)
static const NSTimeInterval MPAnimTiltReleaseDur = 0.2;     // возврат из наклона
