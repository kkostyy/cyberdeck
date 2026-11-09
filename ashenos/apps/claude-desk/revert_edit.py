#!/usr/bin/env python3
"""Undo one Edit made by Claude: put old_string back in place of new_string.

stdin: {"file_path": ..., "old_string": ..., "new_string": ...}  (an Edit tool input)
Only acts when new_string occurs exactly once, so nothing else is touched.
Prints OK / a reason in Russian.
"""
import json
import os
import sys

try:
    inp = json.load(sys.stdin)
    path, old, new = inp["file_path"], inp.get("old_string", ""), inp.get("new_string", "")
except (ValueError, KeyError):
    print("Нет данных о правке")
    sys.exit(1)

try:
    with open(path, encoding="utf-8") as f:
        text = f.read()
except OSError:
    print("Файл не найден: " + path)
    sys.exit(1)

n = text.count(new) if new else 0
if n == 0:
    print("Правка уже откачена или файл с тех пор изменился")
    sys.exit(1)
if n > 1:
    print("Этот фрагмент встречается в файле несколько раз — откатывать вслепую опасно")
    sys.exit(1)

tmp = path + ".revert-tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(text.replace(new, old, 1))
os.replace(tmp, path)
print("OK")
