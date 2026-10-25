# MetroPhone — тема Windows Phone (Metro) для iOS 6

Джейлбрейк-твик, который переделывает интерфейс iOS 6 в стиле Windows Phone:

- **Metro-лаунчер поверх рабочего стола** (основа UI — код Claude, интеграция и приватные API — свои): плитки 2 размеров с перетаскиванием, алфавитный список приложений со свайпом влево и поиском, бейджи, кнопки «M»/«iOS»;
- **Квадратные плитки** вместо скруглённых иконок с глянцем;
- **Тёмная плоская тема** — чёрные панели навигации, таб-бары, тулбары, без градиентов и теней;
- **Типографика Segoe WP** — тонкие крупные заголовки (HelveticaNeue-Thin, ближайший аналог Segoe, уже есть в iOS 6), ЗАГЛАВНЫЕ подписи;
- **Акцентный цвет** из настоящей палитры Windows Phone (синий `#1BA1E2` по умолчанию, всего 8 цветов);
- **Панель настроек** в Settings.app: можно включать/выключать части темы.

Работает на iPhone 3GS/4/4S/5, iPod touch 3–5, iPad 2/3/4 (архитектуры armv7 + armv7s, минимальная версия системы 6.0).

## Что на что влияет

| Часть темы | Что меняет | Где применяется |
|---|---|---|
| Плоские тёмные панели | `UINavigationBar`/`UIToolbar`/`UITabBar` — чёрный фон, тонкие белые заголовки, статус-бар со светлым текстом, кнопки панелей в акцентном цвете | все приложения |
| Квадратные плитки | иконки: берём исходный квадратный PNG из бандла и рисуем его на весь размер (в iOS 6 скругления и глянец накладывает сам SpringBoard — мы рисуем плитку раньше него) | SpringBoard |
| Шрифт подписей как в WP | HelveticaNeue вместо Helvetica с тенью, белый цвет | SpringBoard |
| ЗАГЛАВНЫЕ подписи | подписи иконок и заголовки панелей — прописными | SpringBoard + все приложения |
| Чёрный фон вместо обоев | обои замещаются чёрным фоном, док теряет «полку» | SpringBoard (и экран блокировки — см. ограничения) |

Настройки хранятся в `/var/mobile/Library/Preferences/ru.ash.metrophone.plist`. Твик читает их через CFPreferences на лету: панели и плитки обновляются после выхода из приложения, изменения обоев/дока требуют перезапуска SpringBoard (кнопка в настройках).

## Требования

- Мак с macOS + Xcode Command Line Tools, Homebrew, git;
- Джейлбрейкнутый девайс на iOS 6.0–6.1.x;
- На девайсе из Cydia установлены: **MobileSubstrate** (Cydia Substrate), **Preferenceloader**, **OpenSSH**;
- На Маке: `ldid`, `dpkg`, `libimobiledevice` (ставятся через Homebrew).

## Установка окружения с нуля (на новой машине)

```bash
# 1. Инструменты сборки и связи с девайсом
xcode-select --install
brew install ldid dpkg libimobiledevice

# 2. Theos — сборочная система для твиков
git clone --recursive https://github.com/theos/theos.git ~/theos
echo 'export THEOS="$HOME/theos"' >> ~/.zshrc
source ~/.zshrc

# 3. SDK — в theos/sdks нужен iPhoneOS10.3.sdk (последний с библиотеками armv7/armv7s)
git clone --filter=blob:none --no-checkout --depth 1 https://github.com/theos/sdks.git /tmp/sdkrepo
cd /tmp/sdkrepo && git sparse-checkout set iPhoneOS10.3.sdk && git checkout
cp -R iPhoneOS10.3.sdk ~/theos/sdks/
cd - && rm -rf /tmp/sdkrepo

# 4. Два патча SDK — без них новый clang не линкует старый SDK:
python3 - <<'EOF'
# _objc_msgSend_stret в tbd libobjc — нужен для возврата структур на armv7
p = __import__('os').path.expanduser('~/theos/sdks/iPhoneOS10.3.sdk/usr/lib/libobjc.A.tbd')
s = open(p).read()
s = s.replace("_objc_msgSendSuper, _objc_msgSendSuper2,",
              "_objc_msgSendSuper, _objc_msgSendSuper2, _objc_msgSend_stret,", 1)
open(p, 'w').write(s)
print("libobjc patch ok")
EOF
```

Патч `libobjc.A.tbd` добавляет `_objc_msgSend_stret` (в этом tbd он отсутствует, хотя в реальной библиотеке на устройстве есть). Второй нюанс — `libSystem` в SDK больше не переэкспортирует `libgcc_s.1.dylib` (SjLj-unwind для armv7), поэтому проект линкует его явно через `*_LDFLAGS = -lgcc_s.1` в Makefile. Проект уже собран под оба патча.

Важно: обычный clang из Xcode **умеет** armv7 — отдельный кросс-тулчейн (Procursus) не нужен, достаточно SDK 10.3 и этих патчей.

## Сборка

```bash
cd ~/Documents/Проекты/MetroPhone
make package FINALPACKAGE=1
```

Готовый пакет появится в `packages/ru.ash.metrophone_0.1.0_iphoneos-arm.deb`.

(Без `FINALPACKAGE=1` соберётся debug-вариант с суффиксом `-1+debug`.)

## Установка на девайс

Целевое устройство проекта — iPhone 4 (iOS 6.1.3). По Wi-Fi его SSH недоступен, связь работает только по USB (iproxy) со legacy-алгоритмами — поэтому `make install` у Theos не подойдёт (он зовёт обычный ssh), а используется обёртка [iphone-ssh.sh](iphone-ssh.sh).

Телефон подключён кабелем? Тогда:

```bash
# 1. Проверить связь
./iphone-ssh.sh "uname -a"

# 2. Передать пакет на телефон
./iphone-ssh.sh --push packages/ru.ash.metrophone_0.1.0_iphoneos-arm.deb /tmp/metrophone.deb

# 3. Установить и перезапустить SpringBoard
./iphone-ssh.sh "dpkg -i /tmp/metrophone.deb; killall SpringBoard"
```

Через несколько секунд после перезапуска SpringBoard интерфейс станет Metro. Откат: `./iphone-ssh.sh "dpkg -r ru.ash.metrophone; killall SpringBoard"`.

Ручная установка с любого другого компьютера: скопировать .deb на девайс и выполнить `dpkg -i файл.deb; killall SpringBoard`.

## Настройки

Настройки → MetroPhone:

- **Включить MetroPhone** — главный переключатель;
- **Акцентный цвет** — 8 цветов палитры WP;
- **Стиль плиток** — «Тёмные» (иконки-квадраты на чёрном) или «Акцентные» (плитки в цвет акцента);
- **Плоские тёмные панели** — панели приложений и статус-бар;
- **Квадратные плитки**, **Шрифт подписей как в WP**, **ЗАГЛАВНЫЕ подписи**;
- **Чёрный фон вместо обоев**;
- **Перезапустить SpringBoard** — применяет изменения, которые не подхватываются на лету.

## Структура проекта

```
Makefile               — цели: твик (armv7/armv7s, SDK 10.3, min iOS 6.0) + субпроект настроек
control                — метаданные deb-пакета (ru.ash.metrophone)
MetroPhone.plist       — фильтр MobileSubstrate: инъекция в процессы с UIKit и в SpringBoard
Tweak.xm               — все хуки (Logos): UIKit-группа + SpringBoard-группа
MetroPhoneCommon.h     — ключи настроек, общие для твика и бандла
metrophoneprefs/       — бандл настроек (PreferenceLoader, раздел в Settings.app)
packages/              — готовые .deb
```

Хуки (классы сверены с дампом заголовков SpringBoard iOS 6.1):

- **UIKit**: `UINavigationBar` (`drawRect:`, `layoutSubviews`, `setTitleTextAttributes:`), `UIToolbar`, `UITabBar` (`drawRect:`), `UIApplication setStatusBarStyle:`, UIAppearance для `UIBarButtonItem`/`UISearchBar`/`UITabBar`;
- **SpringBoard**: `SBApplicationIcon`/`SBFolderIcon generateIconImage:` (плитки), `SBIconView` (тени/отражения), `SBIconLabelImageParameters` (шрифт/цвет/тень/регистр подписей), `SBWallpaperView` (чёрный фон), `SBDockIconListView backgroundImageForOrientation:` (полка дока).

## Известные ограничения

- **Segoe WP проприетарный** — используется HelveticaNeue-Thin/Light/Regular (есть в iOS 6 с версии 6.0, визуально близко к Segoe).
- **Чёрный фон заменяет обои и на экране блокировки** — `SBWallpaperView` общий для обоих экранов; в стиле Metro это даже уместно, но знайте.
- **Панель многозадачности** (переключатель задач снизу) пока остаётся в родном виде; её «полка» рисуется отдельными классами — можно добавить тем же способом позже.
- **Плитки folders** (папок) — рисуются превью-картинкой на подложке, точного вида WP-плитки без иконок внутри нет.
- Проверить тему можно только на реальном девайсе: на iOS 6.1 симуляторе твик не запускается.

## Отладка

Логи твика видны в syslog девайса (если syslogd настроен — `/var/log/syslog`) или через `idevicesyslog` с Маком:

```bash
idevicesyslog | grep -i metro
```

Если SpringBoard падает в safe mode — снимите лог и посмотрите последний хук перед падением. Отключить твик без удаления можно из safe mode (уведомление открывает Settings) — переключатель MetroPhone. Полностью удалить: `./iphone-ssh.sh "dpkg -r ru.ash.metrophone; killall SpringBoard"`.

## Сборка отладочной версии и правки

```bash
make package              # debug-вариант
```

Версия пакета задаётся в `control` (`Version:`); при каждой установке того же номера добавляйте ревизию `-2`, `-3`, иначе dpkg посчитает, что пакет не изменился.

## Другие файлы

- `iphone-ssh.sh` — обёртка SSH к iPhone по USB: `./iphone-ssh.sh "команда"`, `./iphone-ssh.sh --push файл /tmp/путь`, без аргументов — интерактивная root-сессия.
