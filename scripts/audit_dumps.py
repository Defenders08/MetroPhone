#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
audit_dumps.py — автопроверки по дампам дерева вьюх (/tmp/crawl/*.txt).

Ищет: выход leaf-вьюх за экран, пересечения лейблов внутри одной ячейки,
нулевые кадры у видимых с текстом, хвостовые «…» (обрезанный текст),
полностью скрытые слайдеры. Результат: /tmp/crawl/audit-report.txt
"""
import os, re, sys, json

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/crawl"
SCREEN_W, SCREEN_H = 320.0, 480.0
TOL = 2.0

NODE = re.compile(r"^(\s*)(\S+) \(([-\d.]+),([-\d.]+) ([\d.]+)x([\d.]+)\)(.*?)(«(.*?)»)?$")

def parse_dump(text):
    """→ дерево: node = dict(depth, cls, x, y, w, h, hidden, text, kids)"""
    root = {"depth": -1, "cls": "ROOT", "kids": [], "hidden": False, "text": "", "x": 0, "y": 0, "w": 0, "h": 0}
    stack = [root]
    for ln in text.splitlines():
        m = NODE.match(ln)
        if not m:
            continue
        depth = len(m.group(1)) // 2
        node = {
            "depth": depth, "cls": m.group(2),
            "x": float(m.group(3)), "y": float(m.group(4)),
            "w": float(m.group(5)), "h": float(m.group(6)),
            "hidden": "скрыто" in (m.group(7) or ""),
            "text": m.group(9) or "",
            "kids": [],
        }
        while stack and stack[-1]["depth"] >= depth:
            stack.pop()
        if stack:
            stack[-1]["kids"].append(node)
        stack.append(node)
    return root

def walk(node, path=""):
    yield node
    for k in node["kids"]:
        yield from walk(k)

def leaf_visible(n):
    return not n["hidden"] and not n["kids"] and (n["w"] > 0 or n["h"] > 0)

def label_nodes(node):
    for n in walk(node):
        if n["cls"].startswith("UILabel") and not n["hidden"]:
            yield n

def check(name, text):
    issues = []
    root = parse_dump(text)
    nodes = list(walk(root))
    # 1) выход leaf-вьюх за экран (в оконных координатах y до 480; таблица с 20)
    for n in nodes:
        if not leaf_visible(n):
            continue
        # кадры в координатах родителя — грубая оценка только для x (гориз. не вкладывается)
        if n["x"] < -TOL:
            continue                      # декоративные вьюхи, ушедшие влево, клипаются
        if n["x"] + n["w"] > SCREEN_W + TOL:
            issues.append(f"вылет по X: {n['cls']} ({n['x']:g},{n['y']:g} {n['w']:g}x{n['h']:g}) «{n['text'][:30]}»")
    # 2) пересечения видимых лейблов с текстом внутри одной ячейки
    #    ячейка = предок с классом *TableCell/*Cell или DNDSwitchCell и т.п.
    def find_cells(node):
        for n in walk(node):
            if re.search(r"(TableCell|SwitchCell|SliderCell)", n["cls"]):
                yield n
    for cell in find_cells(root):
        labs = [l for l in label_nodes(cell) if l["text"]]
        for i in range(len(labs)):
            for j in range(i + 1, len(labs)):
                a, b = labs[i], labs[j]
                ox = min(a["x"] + a["w"], b["x"] + b["w"]) - max(a["x"], b["x"])
                oy = min(a["y"] + a["h"], b["y"] + b["h"]) - max(a["y"], b["y"])
                if ox > 6 and oy > 6:
                    issues.append(
                        f"пересечение лейблов «{a['text'][:24]}» и «{b['text'][:24]}» "
                        f"({ox:g}x{oy:g} pt) в {cell['cls']}")
    # 3) нулевые кадры у видимых с текстом
    for n in nodes:
        if n["hidden"]:
            continue
        if n["text"] and (n["w"] == 0 or n["h"] == 0):
            issues.append(f"нулевой кадр: {n['cls']} «{n['text'][:30]}»")
    # 4) обрезанный текст (хвостовое «…»)
    KNOWN_ELLIPSIS = ("Другая…", "Выбрать сеть…", "Другая сеть…")
    for n in label_nodes(root):
        if n["text"].endswith("…") and len(n["text"]) > 2 and n["text"] not in KNOWN_ELLIPSIS:
            issues.append(f"обрезанный текст: «{n['text']}» ({n['cls']} {n['w']:g}x{n['h']:g})")
    # 5) слайдер, у которого скрыты ВСЕ дети-вьюхи (невидимый ползунок)
    for n in walk(root):
        if n["cls"] == "UISlider" and not n["hidden"]:
            kids = list(walk(n))
            kids.remove(n)
            vis = [k for k in kids if not k["hidden"]]
            if kids and not vis:
                issues.append("слайдер полностью невидим (все дети скрыты)")
    return issues

def main():
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".txt") and f != "tmp-dump.txt")
    report = []
    total = 0
    for f in files:
        with open(os.path.join(OUT, f), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if not text.startswith("окно"):
            continue
        issues = check(f, text)
        total += len(issues)
        if issues:
            title = "?"
            m = re.findall(r"UILabel \((?:40|16),24 [\dx.]+\) «([^»]+)»", text)
            if m:
                title = m[-1]
            report.append(f"== {f} [{title}] ==")
            report += ["  " + i for i in issues]
    with open(os.path.join(OUT, "audit-report.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(report) or "срабатываний нет")
    print(f"срабатываний: {total} → {OUT}/audit-report.txt")

if __name__ == "__main__":
    main()
