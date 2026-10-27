// MetroPhone — контроллер Metro-локскрина: собственное окно поверх нативного
// экрана блокировки, синхронизация с lock-состоянием, разблокировка свайпом.
// Все функции потокобезопасны (внутри — переход на главный поток).

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// Локскрин включён (enabled + lockscreenEnabled)
BOOL MPLockScreenIsOn(void);

// Сохранить нативные обои (вызывается из хука SBWallpaperView setImage:
// ДО подмены картинки на чёрный — поэтому обои есть даже при blackWallpaper)
void MPLockScreenNoteWallpaper(UIImage *image);

// Посадить нашу вьюху в окно нативного локскрина поверх всего его контента
// (вызывается из хука SBAwayView didMoveToWindow — окно узнаём через self.window;
// нативный локскрин живёт в ОТДЕЛЬНОМ окне выше главного, туда надо садиться самим)
void MPLockScreenAttach(UIWindow *lockWindow);

// Поднять вьюху поверх всего главного окна и сверить размер (вызывается из
// хуков SBAppWindow didAddSubview:/layoutSubviews и SBAwayView didMoveToWindow —
// iOS при пробуждении добавляет контент нативного локскрина после нас)
void MPLockScreenRaise(void);

// Синхронизация: залочено → показать своё окно, разлочено → скрыть
// (вызывается из lockstate, displayStatus, passcode-хуков)
void MPLockScreenSync(void);

// Нативный экран ввода код-пароля показался/скрылся (хук SBPasscodeViewController)
void MPLockScreenPasscodeUI(BOOL visible);

// Окно, в котором сейчас живёт наш локскрин (nil — если он скрыт или ещё не посажен).
// Нужно отладочному снимку экрана: у SpringBoard несколько окон, и главное окно
// не покажет то, что рисует локскрин.
UIWindow *MPLockScreenWindow(void);

#ifdef __cplusplus
}
#endif
