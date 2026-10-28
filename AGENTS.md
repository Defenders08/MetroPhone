# AGENTS.md — инструкции для ИИ

Всегда отвечай на русском. Комментарии в коде, сообщения коммитов и пояснения — тоже на русском.

## Структура проекта

- `tweak/` — исходник твика (theos-проект): `Makefile`, `control`, `Tweak.xm`, `MetroLauncher/`, `MetroLockScreen/`, `MetroSettings/`, бандл настроек `metrophoneprefs/`, `layout/` (файлы, попадающие в deb). Артефакты сборки — `tweak/.theos/`.
- `builds/` — готовые deb-пакеты (theos кладёт их сюда благодаря THEOS_PACKAGE_DIR в tweak/Makefile).
- `ai/` — промпты, планы, контекст, HTML-прототипы и PNG-референсы для ИИ (см. ai/README.md).
- `archive/` — архив: коллекция иконок WP8.1 (`wp81_build/`), скриншоты (`screens/`, `screenshots/`), крэшлоги (`crashlogs/`).
- `tools/` — рабочие скрипты; питон-краулеры в `tools/scripts/`.

## Команды

- Сборка: `make` в корне — корневой Makefile лишь пробрасывает в `tweak/`. ТОЛЬКО однопоточно: `make -j4` виснет.
- Пакет: `make package` → deb появится в `builds/`. Отладочная сборка: `make package FINALPACKAGE=0`.
- Установка на iPhone: `tools/install_thin.sh` (сам возьмёт новейший деб из builds/) или `tools/install_or_wait.sh`.
- Скрины с телефона: `tools/pull_screens.sh` → `archive/screens/`; крэшлоги: `tools/pull_crash.sh` → `archive/crashlogs/`.

## Грабли

- Theos в `~/theos`, SDK 10.3, arch armv7+armv7s, минимум iOS 6.0. `FINALPACKAGE = 1` прописан в tweak/Makefile — обычная сборка сразу релизная.
- Версию в `tweak/control` бампает юзер параллельно — перед сборкой перечитать.
- `metrophoneprefs` — сабпроект (SUBPROJECTS в tweak/Makefile), собирается агрегатом.
- Установка на телефон — только scp-push/thin-чанки; `killall SpringBoard` проверять по pid; в выводе expect строка «spawn …» ломает grep.
