# MetroPhone — тема Windows Phone (Metro) для iOS 6

Джейлбрейк-твик, который переделывает интерфейс iOS 6 в стиле Windows Phone:

- **Metro-лаунчер поверх рабочего стола**: плитки Small/Medium/Wide (WP8-сетка) с перетаскиванием и редактированием, алфавитный список приложений со свайпом влево и поиском, бейджи;
- **«Настройки» в WP 8.1-стиле**: огромный заголовок страницы, чёрный плоский список, WP-тумблеры и ползунки, возврат по тапу на шапку «‹ название» (страницы твиков остаются штатными iOS — совместимость);
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
- **Акцентный цвет** — страница «Цвета»: 20 цветов палитры WP 8.1 плюс свой цвет тремя ползунками (перекрашивает всё сразу, без respring);
- **Плоские тёмные панели** — панели приложений и статус-бар;
- **Квадратные плитки**, **Шрифт подписей как в WP**, **ЗАГЛАВНЫЕ подписи**;
- **Чёрный фон вместо обоев**;
- **Свой свитчер (двойное Home)** — свитчер многозадачности в стиле WP 8.1 вместо родной панели;
- **Подробный журнал в syslog** — дублировать журнал твика в syslog (по умолчанию выключено: на iOS 6 это заметно замедляет хуки иконок);
- **Перезапустить SpringBoard** — применяет изменения, которые не подхватываются на лету.

Metro — единственный рабочий стол: отдельного выхода на родной стол нет, вернуться к системе можно только выключив твик в настройках.

### Иконки строк «Настроек»

Иконки в списке «Настроек» заменяются на глифы Windows Phone. В пакете лежит шрифт **Metro UI Icons** (MIT, 963 глифа): `/Library/Application Support/MetroPhone/metro-ui-core.ttf` рядом с текстом лицензии. Глиф выбирается по названию строки: замок — VPN/SSL, птица — Twitter, палитра — темы, колокольчик — статус/уведомления, окно — MetroPhone, стрелка — restore, Bluetooth — свой значок, «Не беспокоить» — луна; остальным — шестерёнка. Строки без своей иконки остаются текстовыми (новые не добавляются).

## Структура проекта

```
Makefile               — цели: твик (armv7/armv7s, SDK 10.3, min iOS 6.0) + субпроект настроек
control                — метаданные deb-пакета (ru.ash.metrophone)
MetroPhone.plist       — фильтр MobileSubstrate: инъекция в процессы с UIKit и в SpringBoard
Tweak.xm               — ядро: настройки, журнал, хуки темы (UIKit + SpringBoard), кнопка Home
MetroPhoneCommon.h     — ключи настроек, общие для твика и бандла настроек
MetroLauncher/         — Metro-лаунчер: плитки, редактор, список приложений, свитчер, стиль
MetroSettings/         — переоформление приложения «Настройки» в стиле WP 8.1
metrophoneprefs/       — бандл настроек (PreferenceLoader, раздел в Settings.app)
layout/                — запись PreferenceLoader для панели твика
packages/              — готовые .deb
wp81_build/            — разовая выгрузка иконок WP 8.1 (к сборке твика не относится)
```

Хуки (классы сверены с дампом заголовков SpringBoard iOS 6.1):

- **Тема, UIKit**: `UINavigationBar` (`drawRect:`, `layoutSubviews`, `setTitleTextAttributes:`), `UIToolbar`, `UITabBar` (`drawRect:`), `UIApplication setStatusBarStyle:`, UIAppearance для `UIBarButtonItem`/`UISearchBar`/`UITabBar`;
- **Тема, SpringBoard**: `SBApplicationIcon`/`SBFolderIcon generateIconImage:` (плитки), `SBIconView` (тени/отражения), `SBIconLabelImageParameters` (шрифт/цвет/тень/регистр подписей), `SBWallpaperView` (чёрный фон), `SBDockIconListView backgroundImageForOrientation:` (полка дока);
- **Лаунчер**: `SpringBoard menuButtonDown:/Up:` (двойное Home — свитчер, одиночное — выход из правки плиток), `SBIcon noteBadgeDidChange` (обновление бейджей).

Твик ставит хуки только в `com.apple.springboard` и `com.apple.Preferences` — в остальных приложениях остаётся штатный дизайн iOS.

Настройки читаются через CFPreferences на лету. Раскладка плиток лежит отдельно — `/var/mobile/Library/Preferences/metrophone-layout.plist` (порядок, размеры, откреплённые плитки).

## Известные ограничения

- **Segoe WP проприетарный** — используется HelveticaNeue-Thin/Light/Regular (есть в iOS 6 с версии 6.0, визуально близко к Segoe).
- **Чёрный фон заменяет обои и на экране блокировки** — `SBWallpaperView` общий для обоих экранов; в стиле Metro это даже уместно, но знайте.
- **Панель многозадачности** заменена своим свитчером в стиле WP 8.1 (двойное Home). Родная панель при этом недоступна — это отключается в настройках («Свой свитчер»).
- **Плитки folders** (папок) — рисуются превью-картинкой на подложке, точного вида WP-плитки без иконок внутри нет.
- Проверить тему можно только на реальном девайсе: на iOS 6.1 симуляторе твик не запускается.

## Отладка

Логи твика всегда пишутся в файл `/var/mobile/Library/Preferences/metrophone.log` (он переживает respring; при разрастании больше 512 КБ пересоздаётся). Смотреть с Мака:

```bash
./iphone-ssh.sh "tail -50 /var/mobile/Library/Preferences/metrophone.log"
```

Дублирование в syslog по умолчанию выключено: на iOS 6 каждый `NSLog` идёт через ASL и заметно замедляет хуки иконок. Включается в настройках — «Подробный журнал в syslog». После включения:

```bash
idevicesyslog | grep -i metro
```

### Снимок экрана и дамп вида (инструмент разработки)

`idevicescreenshot` на iOS 6 не работает (нет сервиса screenshotr), поэтому в твик встроен отладочный канал: он слушает файл `/var/mobile/Library/Caches/metrophone/shot.request` и по записи в него делает действие и сохраняет PNG.

```bash
# снять текущий экран (локскрин или рабочий стол — что на переднем плане)
./iphone-ssh.sh "echo shot > /var/mobile/Library/Caches/metrophone/shot.request"
./iphone-ssh.sh --pull /var/mobile/Library/Caches/metrophone/shot.png shot.png

# экран «Настроек» (отдельный процесс — свой файл)
./iphone-ssh.sh --pull /var/mobile/Library/Caches/metrophone/shot-prefs.png prefs.png
```

Команды в том же файле: `metro` / `ios` (показать/спрятать лаунчер), `page0` / `page1` (страница плиток/списка), `url <ссылка>` (открыть URL, например `url prefs:root=MetroPhone`), `dump` (дерево вьюх с кадрами и текстами в `dump.txt` / `dump-prefs.txt`), `prefscheck` и `prefspage` (проверить/открыть панель настроек).

Канал пассивен: без записи в файл он не делает ничего, кроме одного открытого fd. Перед релизом его можно вырезать — весь код в одном блоке `#pragma mark - Отладочный снимок экрана` в `Tweak.xm`.

**Важно про права файлов бандла:** ресурсы в `metrophoneprefs/Resources/` должны быть `644`. Файл с правами `600` собирается в .deb такими же и становится нечитаемым для «Настроек» (работают под `mobile`) — страница твика открывается пустой. Если сохранили файл редактором с `600`, выполните `chmod 644 metrophoneprefs/Resources/*`.

Если SpringBoard падает в safe mode — снимите лог и посмотрите последний хук перед падением. Отключить твик без удаления можно из safe mode (уведомление открывает Settings) — переключатель MetroPhone. Полностью удалить: `./iphone-ssh.sh "dpkg -r ru.ash.metrophone; killall SpringBoard"`.

## Сборка отладочной версии и правки

```bash
make package              # debug-вариант
```

Версия пакета задаётся в `control` (`Version:`); при каждой установке того же номера добавляйте ревизию `-2`, `-3`, иначе dpkg посчитает, что пакет не изменился.

## Другие файлы

- `iphone-ssh.sh` — обёртка SSH к iPhone по USB: `./iphone-ssh.sh "команда"`, `./iphone-ssh.sh --push файл /tmp/путь`, без аргументов — интерактивная root-сессия.
