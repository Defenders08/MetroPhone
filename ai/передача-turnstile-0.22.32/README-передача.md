# Передача: Turnstile-переходы 0.22.32 → правка по видео

Дата: 01.11.2026. Версия на телефоне: 0.22.32 (собрана из ЭТИХ исходников, все строки журнала соответствуют этому коду).

## Что реализовано (и что показало видео)

| Кусок | Реализовано | Видео |
|---|---|---|
| launch() на t=0, сторож от t=0 | да | — |
| Выезд Start «дверью» 0°→+50° целиком | да (`playStartFoldOutWithCompletion:`) | Start просто пропадает, виден РОДНОЙ экран иконок iOS + штатный зум (2–3 кадра) — Start не закрывает его |
| Поворот окна приложения из его процесса (−80°→0°) | да, код срабатывает (журнал) | визуально окно плоское, поворота нет — гипотеза: корневой слой UIWindow = корень CAContext, композитор игнорирует трансформ |
| Сплэш в окне приложения | да, снимается через 0.8 с после makeKeyAndVisible | холодный запуск Videos: 3–5 с пустой экран — снятие по появлению окна, а не по готовности контента |
| Закрытие: Darwin appclose → окно 0°→−80° | да, код срабатывает | визуально окно не складывается — полупрозрачный плоский фейд ПОВЕРХ плиток (двойная экспозиция) |
| Ранний feather-въезд под окном с +50° | да | на Settings→Start видны осколки feather-рядов (въезд играется и виден) |

Приоритеты правки (от Клода): 1) погасить штатный launch-zoom SB или держать лаунчер выше, пока приложение не frontmost; 2) найти слой, который реально композитится (host-вью приложения в SB или обёртка внутри приложения); 3) сплэш снимать по готовности приложения; 4) закрытие — поворот того же host-слоя.

## Ключевые точки в коде

- `MPHomeController.m`:
  - `playAppOpenAnimationForBundleID:pressedTile:launch:` — запуск на t=0, сторож, вызов fold-out;
  - `playStartFoldOutWithCompletion:` — «дверь» Start (0°→+50°, MPAnimStartFoldDur);
  - `mpSplashUntilAppWindow` / `mpSplashWindowPollGen:t0:` — сплэш только для холодного спавна, снятие по frontmost (ЭТО и надо менять на «по готовности»);
  - `scheduleReturnFromApp` / `mpReturnPollTickGen:t0:` / `mpReturnCommitEarlyEntry` / `mpReturnRollbackEarlyEntry` — ранний въезд + фиксация/откат;
  - `playTurnstileInFromAngle:` (+50° возврат, −50° анлок), `mpFeatherApplyIn:delay:` (угол из `_entryStartAngle`);
  - `MPHomePostDarwin` — постинг Darwin-сигналов окну приложения;
  - `mpSplashPanelWithFrame:`, `mpWindowSplash*` — сплэш-панель.
- `Tweak.xm`:
  - `%group MPWindowHooks` (%init для ВСЕХ процессов в %ctor) — хук `UIWindow makeKeyAndVisible`: `MPAppUnfoldWindowOnShow` (поза −80° ДО показа + раскрытие) и `MPAppShowLaunchSplashIfNeeded` (сплэш);
  - `MPAppWindowHinge` (anchorPoint (0,0.5) + компенсация), `MPAppDarwinOpen`/`MPAppDarwinClose` (обработчики Darwin, регистрация в %ctor);
  - `%hook SBAppWindow` (didAddSubview/layoutSubviews/setHidden:) — сигналы возврата;
  - `menuButtonDown:` — блок 3б «Home: ранний возврат».
- `MPAnimationConstants.h` — ВСЕ константы: MPAnimStartFoldDur 0.25, MPAnimAppInAngle −80, MPAnimAppInDur 0.35, MPAnimAppCloseDur 0.25, MPAnimSplashWindowPoll 0.1, MPAnimSplashAppHold 0.8, MPAnimReturnPoll* и пр.

## Факты из живого журнала (фрагмент рядом)

- frontmost возвращается через 0 мс после Home — окно пропадает из иерархии SB мгновенно, на анимацию складывания в процессе приложения времени нет;
- SBAppWindow setHidden: на закрытие не приходит вовсе;
- SB-путь приклейки сплэша (mpWindowSplashAttachToWindow) не срабатывал ни разу — окна приложения в иерархии SB нет;
- fps: fold-out 14 кадров (5 >20 мс), feather-въезд 20 кадров (1 >20 мс) — A4 тянет, но fold целого слоя тяжеловат.

## Сборка/установка

- `THEOS="$HOME/theos" make package` (корень пробрасывает в tweak/, однопоточно);
- установка: `tools/iphone-ssh.sh --push builds/ru.ash.metrophone_*_deb /tmp/metrophone.deb`, затем `tools/iphone-ssh.sh "dpkg -i /tmp/metrophone.deb && killall SpringBoard"`;
- USB стробирует: телефон пропадает с шины по 1–2 мин, пушить с повторами и проверять md5 deb на телефоне после пуша;
- журнал: `/var/mobile/Library/Preferences/metrophone.log`; версия шапки — #define MP_VERSION в Tweak.xm (сейчас 0.22.32, control тоже 0.22.32 — бампать ОБЕ перед новой сборкой).
