#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
sweep_page.py — адресный обход страниц «Настроек»: открыть родительскую страницу,
затем по очереди каждую её строку-переход, снять dump + PNG.

Зачем: полный краулер (crawl_settings.py) тонет в страницах сторонних твиков,
а нам нужны системные подстраницы. Здесь путь задаётся явно.

Использование:
  python3 scripts/sweep_page.py 9_General [ещё-idx ...]
Артефакты: screenshots/audit4/sweep/<NNN>_<id>.png|.txt, mapping.json
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

OUT = os.path.join(CWD, "screenshots/audit4/sweep")
os.makedirs(OUT, exist_ok=True)
mapping = {}
counter = [0]

DANGEROUS = re.compile(r"стереть|сбросить|сброс|удалить|выйти|восстанов|erase|reset|delete|sign out", re.I)
SKIP_TITLES = re.compile(r"^язык$", re.I)


def ssh(cmd, timeout=90):
    try:
        r = subprocess.run(["./iphone-ssh.sh", cmd], capture_output=True,
                           text=True, timeout=timeout, cwd=CWD)
        return r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return ""


def send(cmd, settle=2.0):
    ssh(f"echo '{cmd}' > {REQ}; sleep {settle}")


def pull(remote, local):
    subprocess.run(["./iphone-ssh.sh", "--pull", remote, local],
                   capture_output=True, text=True, timeout=120, cwd=CWD)


def dump_now(settle=2.2):
    ssh(f"rm -f {DUMP_R}")
    send("dump", settle)
    tmp = os.path.join(OUT, "tmp-dump.txt")
    pull(DUMP_R, tmp)
    try:
        with open(tmp, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def specs_now():
    ssh(f"rm -f {SPECS_R}")
    send("specs2", 2.0)
    tmp = os.path.join(OUT, "tmp-specs.txt")
    pull(SPECS_R, tmp)
    rows = []
    try:
        with open(tmp, encoding="utf-8", errors="replace") as f:
            for ln in f:
                p = ln.rstrip("\n").split("|")
                if len(p) >= 5 and p[0].strip().isdigit():
                    rows.append({"idx": int(p[0]), "cell": p[1].strip(),
                                 "label": p[2].strip(), "detail": p[3].strip()})
    except OSError:
        pass
    return rows


def page_title(dump):
    m = re.findall(r"UILabel \((?:40|16),24 [\dx.]+\) «([^»]+)»", dump)
    return m[-1].strip() if m else "?"


def capture(path_key, dump_text):
    counter[0] += 1
    name = f"{counter[0]:03d}_{path_key}"
    send("shot", 2.0)
    pull(SHOT_R, os.path.join(OUT, name + ".png"))
    with open(os.path.join(OUT, name + ".txt"), "w", encoding="utf-8") as f:
        f.write(dump_text)
    mapping[name] = {"path": parent_path + "/" + path_key, "title": page_title(dump_text)}
    with open(os.path.join(OUT, "mapping.json"), "w", encoding="utf-8") as f:
        json.dump(mapping, f, ensure_ascii=False, indent=1)
    print(f"  снят {name} [{page_title(dump_text)}]", flush=True)


def go_root():
    send("root", 1.8)
    return page_title(dump_now(2.2))


def open_parent(idx):
    go_root()
    send(f"tap idx {idx}", 2.8)
    return dump_now(2.4)


parent_path = ""
parent_idx = sys.argv[1] if len(sys.argv) > 1 else "9_General"

print(f"обход {parent_idx} → {OUT}", flush=True)
d = open_parent(parent_idx)
print(f"родитель: [{page_title(d)}]", flush=True)
if page_title(d) == "?":
    print("родитель не открылся — стоп", flush=True)
    sys.exit(1)
rows = specs_now()
if not rows:
    print("спецификаторы не получены — стоп", flush=True)
    sys.exit(1)

for row in rows:
    label = row["label"] or row["cell"]
    if row["cell"] not in ("PSLinkCell", "PSLinkListCell", "PSChildPaneSpecifier"):
        continue
    if not row["detail"] and not row["label"]:
        continue
    if DANGEROUS.search(label) or SKIP_TITLES.match(label):
        print(f"  пропуск: {label}", flush=True)
        continue
    d = open_parent(parent_idx)
    if page_title(d) == "?":
        print(f"  родитель не открылся для {label}", flush=True)
        continue
    send(f"tap idx {row['idx']}", 2.8)
    page = dump_now(2.4)
    if page_title(page) in ("?", page_title(d)):
        print(f"  не открылось: {label}", flush=True)
        continue
    capture(re.sub(r"[^A-Za-z0-9_\-]", "_", label)[:40], page)
print("готово", flush=True)
