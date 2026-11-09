#!/usr/bin/env python3
"""List Claude Code conversations for a working directory, newest first.

Usage: chats.py <workDir>
Prints JSON: [{"id", "mtime", "size", "title", "count"}]
"""
import json
import os
import re
import sys

work = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/claude")
proj = os.path.expanduser("~/.claude/projects/" + re.sub(r"[^a-zA-Z0-9]", "-", work))
out = []
try:
    names = [n for n in os.listdir(proj) if n.endswith(".jsonl")]
except OSError:
    names = []

for name in names:
    path = os.path.join(proj, name)
    title, summary, last, count = "", "", "", 0
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"type":"user"' not in line and '"type":"summary"' not in line and '"custom-title"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") == "summary" and d.get("summary"):
                    summary = d["summary"]
                elif d.get("type") == "custom-title" and d.get("customTitle"):
                    summary = d["customTitle"]
                elif d.get("type") == "user" and not d.get("isMeta") and not d.get("isSidechain"):
                    c = d.get("message", {}).get("content")
                    text = c if isinstance(c, str) else " ".join(
                        b.get("text", "") for b in (c or []) if isinstance(b, dict) and b.get("type") == "text")
                    text = text.strip()
                    if text and not text.startswith("<") and not text.startswith("[Request interrupted"):
                        count += 1
                        last = text
                        # short "continue"-style prompts make poor titles
                        if not title or (len(title) < 15 and len(text) >= 15):
                            title = text
    except OSError:
        continue
    if count == 0:
        continue
    st = os.stat(path)
    t = (summary or title).replace("\n", " ")
    out.append({"id": name[:-6], "mtime": int(st.st_mtime), "size": st.st_size,
                "title": t[:120], "last": last.replace("\n", " ")[:120], "count": count})

out.sort(key=lambda x: -x["mtime"])
print(json.dumps(out, ensure_ascii=False))
