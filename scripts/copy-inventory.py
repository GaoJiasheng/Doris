#!/usr/bin/env python3
"""Regenerate the string table in docs/copy.md from every L("en", "zh") in the
Swift sources. Run from the repo root: ./scripts/copy-inventory.py

Everything above the marker line in docs/copy.md (the glossary and rules) is
kept as written; the tables below it are rebuilt."""
import re, subprocess, collections

DOC = "docs/copy.md"
MARK = "<!-- generated below: ./scripts/copy-inventory.py -->"
S = r'"((?:[^"\\]|\\.|\\\((?:[^()]|\([^()]*\))*\))*)"'
PAIR = re.compile(r'(?<![A-Za-z0-9_])L\(\s*' + S + r'\s*,\s*' + S + r'\s*\)', re.S)

def area(path):
    if "/doris-ios/" in path: return "iOS"
    if "/doris-mac/" in path: return "macOS"
    return "Shared (iOS + macOS)"

files = [f for f in subprocess.check_output(["git", "ls-files", "*.swift"], text=True).split()
         if "/Tests/" not in f and not f.startswith("build/")]
by_area = collections.OrderedDict((a, collections.OrderedDict()) for a in ("iOS", "macOS", "Shared (iOS + macOS)"))
total = 0
for f in files:
    rows = []
    for m in PAIR.finditer(open(f).read()):
        en, zh = (s.replace("\\\"", "\"").replace("|", "\\|") for s in m.groups())
        if (en, zh) not in rows: rows.append((en, zh))
    if rows:
        by_area[area(f)][f] = rows
        total += len(rows)

out = [MARK, "", f"{total} strings. Duplicates within a file are listed once.", ""]
for a, groups in by_area.items():
    out += [f"## {a}", ""]
    for f, rows in groups.items():
        out += [f"### `{f.split('/')[-1]}`", "", "| English | 中文 |", "|---|---|"]
        out += [f"| {en} | {zh} |" for en, zh in rows] + [""]

head = open(DOC).read().split(MARK)[0]
open(DOC, "w").write(head + "\n".join(out))
print(f"{DOC}: {total} strings")
