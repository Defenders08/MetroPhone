// MPAnimationConstants.h — все длительности, кривые, перспективы и таймауты
// анимаций MetroPhone в одном месте (см. ai/WP-ANIMATIONS.md §3).
// Подстройка движения всего твика — правкой этого файла.
#import <QuartzCore/QuartzCore.h>

#pragma mark - Turnstile (запуск/закрытие приложений, лок/анлок)

static const NSTimeInterval MPAnimTurnstileOutDur = 0.25;   // выезд лаунчера 0°→+50°
static const NSTimeInterval MPAnimTurnstileInDur  = 0.35;   // въезд лаунчера −80°→0°
static const CGFloat MPAnimTurnstileOutAngle = 50.0f;
static const CGFloat MPAnimTurnstileInAngle  = -80.0f;
static const CGFloat MPAnimPerspective = -1.0f / 500.0f;    // m34 для 3D-поворотов

// Фирменная кривая ExponentialEase exp6 — кубические аппроксимации (WP-ANIMATIONS.md §3.2)
static inline CAMediaTimingFunction *MPAnimEaseIn(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.69f:0.0f:0.83f:0.38f];
}
static inline CAMediaTimingFunction *MPAnimEaseOut(void) {
    return [CAMediaTimingFunction functionWithControlPoints:0.17f:0.62f:0.31f:1.0f];
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

#pragma mark - Возврат из приложения (въезд по факту ухода окна, не по константе)

// Окно приложения на iOS 6 при закрытии setHidden: молчит, единственный честный
// сигнал «окно РЕАЛЬНО ушло» — окно SpringBoard снова frontmost. Опрашиваем с шагом
// MPAnimReturnPollInterval; окно ушло раньше старой константы — въезд раньше,
// окно ещё видно — въезд ждёт (иначе двойная экспозиция: Start поверх гаснущего
// приложения). MPAnimReturnGrace гасит возможную гонку смены порядка окон.
static const NSTimeInterval MPAnimReturnPollInterval = 0.02; // шаг опроса frontmost
static const NSTimeInterval MPAnimReturnPollCap = 0.8;       // предел опроса → въезд по пределу
static const NSTimeInterval MPAnimReturnGrace = 0.06;        // пауза после ухода окна перед въездом

#pragma mark - Загрузочный экран в позе ожидания («чёрная яма» перед окном приложения)

// Между выездом лаунчера и появлением окна приложения ~0.9 с системного спавна —
// экран чёрный. В позе ожидания показываем иконку приложения по центру с лёгким
// scale/fade; убирается при начале въезда. MPAnimLaunchSplashEnabled — рубильник.
static const BOOL MPAnimLaunchSplashEnabled = YES;
static const CGFloat MPAnimLaunchSplashSize = 72.0f;         // сторона иконки
static const NSTimeInterval MPAnimLaunchSplashFadeIn = 0.25; // появление
static const CGFloat MPAnimLaunchSplashScaleFrom = 1.10f;    // стартовый scale (сжатие к 1.0)

#pragma mark - Feather-стаггер (по строкам, WP8.1 TurnstileFeather)

static const NSTimeInterval MPAnimFeatherStagger = 0.02;    // сдвиг на строку сверху вниз (ТЗ п.1б/2б)
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
