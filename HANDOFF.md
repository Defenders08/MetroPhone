# MetroPhone — контекст работы за 26–27 октября 2026

## Проект
Джейлбрейк-твик: тема Windows Phone (Metro) для **iOS 6.1.3 на iPhone 4**.
Путь: `/Users/ash/Documents/Проекты/MetroPhone`. Theos, Logos, ARC, armv7+armv7s, min iOS 6.0.
Хуки только в SpringBoard и Preferences; остальные процессы не трогаются.

Сборка: `export PATH="/opt/homebrew/bin:$PATH"; export THEOS="$HOME/theos"; make package FINALPACKAGE=1`
(без `/opt/homebrew/bin` в PATH падает на `ldid`). Пакет — `packages/ru.ash.metrophone_<ver>_iphoneos-arm.deb`.

## Телефон
iPhone 4, root по USB: `iproxy 2222:22` + `./iphone-ssh.sh "..."` (expect, пароль alpine), `--push`/`--pull`.
Установка: `./iphone-ssh.sh --push <deb> /tmp/mp.deb; ./iphone-ssh.sh "dpkg -i /tmp/mp.deb; killall SpringBoard"`.
Сейчас стоит **0.19.3**. Журнал твика: `/var/mobile/Library/Preferences/metrophone.log` (0 ошибок).

## Что сделано за день

**Отладочный канал (в README).** `echo shot > /var/mobile/Library/Caches/metrophone/shot.request`
заставляет SpringBoard/«Настройки» снять PNG (`shot.png`, `shot-prefs.png`). Команды: `metro`, `ios`,
`page0/page1`, `url prefs:root=…`, `dump` (дерево вьюх с кадрами и текстами), `specs`, `scroll 0..1`,
`prefscheck`, `prefspage`. Пассивен без записи в файл.

**Найден и исправлен корневой баг:** `Root.plist` в бандле имел права `0600`, «Настройки» работают
под `mobile` → страница MetroPhone была пустой. Лечится `chmod 644 metrophoneprefs/Resources/*`
(в README предупреждение).

**Дизайн «Настроек» (единый слой):** шапка 52 pt Thin строчными и показывает имя страницы
(«metrophone», а не «настройки»); строки 24 pt Light, подзаголовки 13 pt серые, высота 56 pt;
заголовки групп 17 pt серые; футеры 12 pt по тексту; WP-тумблеры 46×22; тонкие ползунки;
тёмные поля ввода; **иконок в строках нет вообще** (решение 27.10), всё по одному левому краю
16 pt; аксессуары — белый шеврон (глиф 0xe69b); жирные подписи приводятся к Light;
строки-действия — акцентом (0.19.3, снимком не подтверждено).

**Шрифт:** Metro UI Icons (MIT, 963 глифа) — `/Library/Application Support/MetroPhone/metro-ui-core.ttf`
+ лицензия. Таблица «слово → глиф» сохранена в `DESIGN-NOTES.md`.

**Лаунчер:** кнопка выхода «iOS» удалена (Metro — единственный стол), поле поиска на всю ширину;
плитки — подписи в две строки, длинные слова без пробелов ужимаются до 9 pt, бейдж — белый квадрат
с тёмной цифрой, заглушка иконки — белая буква на акценте (без серого квадрата).

**Общий хук:** любая кастомная ячейка «Настроек» (APTableCell, BTTableCell, VPN, Twitter, App Store…)
после своего layout прогоняется через стиллер — поэтому стиль одинаков на всех страницах.

## Открытые пункты
1. «Изменить» под заголовком страницы (сейчас кнопка в шапке).
2. Подтвердить акцентный цвет строк-действий (нужна прокрутка панели).
3. Twitter: строка аккаунта с аватаром с отступом 77 pt — выравнивать или оставить.
4. Локскрин: шторм показов (109 показов / 6 скрытий) и старые крэши SpringBoard на прежних сборках.
5. Гигиена репозитория: история 6.9 ГБ (образ WP8.1 и XAP в HEAD), `.theos/` и `packages/` в git.

## Файлы-память
`DESIGN-NOTES.md` — замеры, решения, история иконок, таблица глифов.
`SETTINGS-AUDIT.md` — аудит экранов «Настроек». `AUDIT-QUESTIONS.md` — блиц и ответы.
`screenshots/` — снимки (в .gitignore).
