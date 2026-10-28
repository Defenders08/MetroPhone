#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
crawl_settings.py — обход «Настроек» iOS 6 с твиком MetroPhone (v2, BFS).

Каждый экран открывается заново по цепочке `tap idx` от корня. Это медленнее
DFS, но надёжно: сбой на одном экране (модальная страница, асинхронный pop)
не сбивает остальные.

На экране: dump (дерево вьюх) + shot (PNG) + specs2 (строки спецификаторов).
Дети ставятся в очередь по строкам-переходам (PSLinkCell/PSLinkListCell),
опасные пункты (сброс/стереть/выход) и модальные «Другая сеть…» пропускаются.

Артефакты: <out>/NNN_путь.png, .txt, mapping.json, crawl.log.
"""
import json
import os
import re
import subprocess
import sys
import time

CWD = "/Users/ash/Documents/Проекты/MetroPhone"
REQ = "/var/mobile/Library/Caches/metrophone/shot.request"
DUMP_R = "/var/mobile/Library/Caches/metrophone/dump-prefs.txt"
SHOT_R = "/var/mobile/Library/Caches/metrophone/shot-prefs.png"
SPECS_R = "/var/mobile/Library/Caches/metrophone/dump-specs2.txt"

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(CWD, "screenshots/audit3/crawl")
MAX_DEPTH = 3
MAX_SCREENS = 60
TIME_LIMIT = 25 * 60

DANGEROUS = re.compile(
    r"стереть|сбросить|сброс всех|удалить|выйти|выход|восстанов|erase|reset all|"
    r"delete|sign out|закрыть сеанс|перезапуск|restart|обновлен|заблокировать|format", re.I)
# Модальные страницы без шапки: ввод пароля/имени сети и т.п. Их не открываем.
MODAL = re.compile(r"другая|other|добавить сеть|нов[а-я]+ сеть|add network", re.I)
# «Язык» на этом девайсе падает в самом Preferences (см. SETTINGS-AUDIT) — пропускаем
SKIP_TITLES = re.compile(r"^язык$", re.I)

os.makedirs(OUT, exist_ok=True)
mapping = {}
visited = {}
counter = [0]
t0 = time.time()


def log(msg):
    print(msg, flush=True)


def ssh(cmd, timeout=90):
    try:
        r = subprocess.run(["./iphone-ssh.sh", cmd], capture_output=True,
                           text=True, timeout=timeout, cwd=CWD)
        return r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        log(f"  !! ssh timeout: {cmd[:60]}")
        return ""


def send(cmd, settle=1.8):
    ssh(f"echo '{cmd}' > {REQ}; sleep {settle}")


def send_many(cmds, gap=1.0):
    body = "; ".join(f"echo '{c}' > {REQ}; sleep {gap}" for c in cmds)
    ssh(body)


def pull(remote, local):
    subprocess.run(["./iphone-ssh.sh", "--pull", remote, local],
                   capture_output=True, text=True, timeout=120, cwd=CWD)


def dump_now(settle=1.8):
    send("dump", settle)
    tmp = os.path.join(OUT, "tmp-dump.txt")
    pull(DUMP_R, tmp)
    try:
        with open(tmp, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def specs_now():
    for attempt in (1, 2):
        send("specs2", 1.8)
        tmp = os.path.join(OUT, "tmp-specs.txt")
        pull(SPECS_R, tmp)
        rows = []
        try:
            with open(tmp, encoding="utf-8", errors="replace") as f:
                for ln in f:
                    p = ln.rstrip("\n").split("|")
                    if len(p) >= 5 and p[0].isdigit():
                        rows.append({"idx": int(p[0]), "cell": p[1], "label": p[2],
                                     "detail": p[3], "bundle": p[4]})
        except OSError:
            pass
        if rows:
            return rows
        if attempt == 1:
            log("  specs2 пуст — повтор")
            time.sleep(2)
    return []


def page_title(dump):
    m = re.findall(r"UILabel \((?:40|16),24 [\dx.]+\) «([^»]+)»", dump)
    return m[-1].strip() if m else "?"


def slug(s):
    return re.sub(r"[^A-Za-z0-9_\-]", "_", s)[:60]


def capture(path_key, title, dump_text):
    counter[0] += 1
    name = f"{counter[0]:03d}_{slug(path_key)}"
    send("shot", 1.8)
    pull(SHOT_R, os.path.join(OUT, name + ".png"))
    with open(os.path.join(OUT, name + ".txt"), "w", encoding="utf-8") as f:
        f.write(dump_text)
    mapping[name] = {"path": path_key, "title": title}
    with open(os.path.join(OUT, "mapping.json"), "w", encoding="utf-8") as f:
        json.dump(mapping, f, ensure_ascii=False, indent=1)
    log(f"  снят: {name} ← {path_key} [{title}]")


def dump_ready(waits=(2.4, 4.0, 6.0)):
    """Дамп страницы с повторами: тяжёлые страницы (Заметки, iCloud)
    на iPhone 4 отрисовываются заметно дольше одной паузы."""
    d = dump_now(waits[0])
    if page_title(d) != "?":
        return d
    for w in waits[1:]:
        log(f"  шапки нет — ждём ещё {w:g} с")
        d = dump_now(w)
        if page_title(d) != "?":
            return d
    return d


def go_root():
    send("root", 1.6)
    d = dump_now(2.0)
    if page_title(d) in ("настройки", "Настройки"):
        return page_title(d)
    # после холодного старта iOS восстанавливает последнюю страницу —
    # перезапускаем и повторяем pop to root
    log("  корень не достигнут — перезапуск Настроек")
    # флаг force-root: твик при следующей активации сбросит стек в корень
    ssh("touch /var/mobile/Library/Caches/metrophone/force-root; "
        "killall Preferences; sleep 2; uiopen prefs:; sleep 8")
    send("root", 1.8)
    return page_title(dump_now(2.2))


def navigate(actions):
    """Открыть страницу: корень + цепочка tap idx.

    После каждого шага проверяем, что заголовок сменился — иначе тап ушёл
    в чужую таблицу (был случай: «Статистика» снималась как Bluetooth-устройство).
    Возвращает (дамп, дошли ли до страницы)."""
    go_root()
    cur = "настройки"
    d = ""
    for idx in actions:
        send(f"tap idx {idx}", 2.6)
        send("dismiss", 1.0)
        d = dump_ready()
        t = page_title(d)
        if t == "?" or t == cur:
            return d, False
        cur = t
    if not d:
        d = dump_ready()
    return d, True


def main():
    log(f"обход → {OUT}")
    root_title = go_root()
    log(f"корень: [{root_title}]")
    if root_title not in ("настройки", "Настройки"):
        time.sleep(2)
        root_title = go_root()

    tasks = [("root", [], 0)]
    while tasks:
        if counter[0] >= MAX_SCREENS or time.time() - t0 > TIME_LIMIT:
            log("стоп по лимиту")
            break
        path_key, actions, depth = tasks.pop(0)
        d, ok = navigate(actions)
        if not ok:
            log(f"  пропуск (переход не сработал): {path_key}")
            continue
        title = page_title(d)
        if title == "?":
            log(f"  пропуск (нет шапки): {path_key}")
            continue
        if title in ("настройки", "Настройки") and actions:
            log(f"  пропуск (остались в корне): {path_key}")
            continue
        if title in visited:
            log(f"  уже снимали: {path_key} [{title}]")
            continue
        visited[title] = path_key
        capture(path_key, title, d)

        if depth >= MAX_DEPTH:
            continue
        rows = specs_now()
        log(f"  строк: {len(rows)}")
        for r in rows:
            if r["cell"] not in ("PSLinkCell", "PSLinkListCell"):
                continue
            label = (r["label"] or "").strip()
            if not label:
                continue
            if DANGEROUS.search(label):
                log(f"  skip (опасно): «{label}»")
                continue
            if MODAL.search(label):
                log(f"  skip (модальная): «{label}»")
                continue
            if not r["detail"] and not r["bundle"]:
                log(f"  skip (нет detail/bundle): «{label}»")
                continue
            tasks.append((f"{path_key}/{r['idx']}_{label[:28]}", actions + [r["idx"]], depth + 1))
    go_root()
    log(f"готово: {counter[0]} экранов за {int(time.time() - t0)} с")


if __name__ == "__main__":
    main()
