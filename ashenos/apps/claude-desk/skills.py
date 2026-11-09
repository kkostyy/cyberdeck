#!/usr/bin/env python3
"""Skills, subagents and memory files for the skills page.

  skills.py [--agents] list                        -> JSON [{name, description, body, model, extra, editable}]
  skills.py [--agents] save <name> <oldname> <desc> [body] [model]
                                                   body from argv or stdin; renames if oldname differs
  skills.py [--agents] delete <name>
  skills.py memory-read <path>                     -> file text ("" if missing)
  skills.py memory-write <path> <text>             only files named CLAUDE.md

Skills live in ~/.claude/skills/<name>/SKILL.md, agents in ~/.claude/agents/<name>.md.
"""
import json
import os
import re
import shutil
import sys

SKILLS = os.path.expanduser("~/.claude/skills")
AGENTS = os.path.expanduser("~/.claude/agents")
AGENT_MODE = False
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
RESERVED = {"synced"}  # managed by claude.ai sync, not ours to touch


def valid(name):
    return bool(NAME_RE.match(name)) and name not in RESERVED


def split(text):
    """-> (frontmatter lines, body)"""
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end >= 0:
            fm = text[3:end].strip("\n").splitlines()
            body = text[end + 4:].lstrip("\n")
            return fm, body
    return [], text


def field(fm, key):
    for i, line in enumerate(fm):
        if line.startswith(key + ":"):
            v = line[len(key) + 1:].strip()
            if v in (">", "|", ">-", "|-"):
                cont = []
                for nxt in fm[i + 1:]:
                    if nxt.startswith((" ", "\t")):
                        cont.append(nxt.strip())
                    else:
                        break
                return " ".join(cont)
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                try:
                    return json.loads(v) if v[0] == '"' else v[1:-1]
                except ValueError:
                    return v[1:-1]
            return v
    return ""


def other_fields(fm, keys=("name", "description")):
    """Frontmatter lines except `keys` (and their continuations)."""
    out, skip = [], False
    prefixes = tuple(k + ":" for k in keys)
    for line in fm:
        if skip and line.startswith((" ", "\t")):
            continue
        skip = line.startswith(prefixes)
        if not skip:
            out.append(line)
    return out


def root():
    return AGENTS if AGENT_MODE else SKILLS


def entry(name):
    """-> (path that gets created/removed, the markdown file inside it)"""
    if AGENT_MODE:
        p = os.path.join(AGENTS, name + ".md")
        return p, p
    d = os.path.join(SKILLS, name)
    return d, os.path.join(d, "SKILL.md")


def cmd_list():
    items = []
    r = root()
    if os.path.isdir(r):
        for fn in sorted(os.listdir(r)):
            if AGENT_MODE:
                if not fn.endswith(".md"):
                    continue
                name = fn[:-3]
            else:
                name = fn
                if name in RESERVED:
                    continue
            top, path = entry(name)
            if not os.path.isfile(path):
                continue
            try:
                with open(path, encoding="utf-8") as f:
                    fm, body = split(f.read())
            except OSError:
                continue
            extra = 0 if AGENT_MODE else len([x for x in os.listdir(top) if x != "SKILL.md"])
            items.append({
                "name": name,
                "description": field(fm, "description"),
                "body": body,
                "model": field(fm, "model"),
                "extra": extra,
                "editable": valid(name),
            })
    print(json.dumps(items, ensure_ascii=False))


def cmd_save(name, oldname, desc, body=None, model=""):
    if not valid(name):
        sys.exit("bad name")
    if body is None:
        body = sys.stdin.read()
    top, path = entry(name)
    if oldname and oldname != name:
        if not valid(oldname):
            sys.exit("bad old name")
        if os.path.exists(top):
            sys.exit("exists")
        src = entry(oldname)[0]
        if os.path.exists(src):
            os.rename(src, top)
    elif not oldname and os.path.exists(top):
        sys.exit("exists")
    keys = ("name", "description", "model") if AGENT_MODE else ("name", "description")
    keep = []
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            keep = other_fields(split(f.read())[0], keys)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    desc = " ".join(desc.split())
    fm = ["name: " + name, "description: " + json.dumps(desc, ensure_ascii=False)]
    if AGENT_MODE and model.strip():
        fm.append("model: " + model.strip())
    fm += keep
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("---\n" + "\n".join(fm) + "\n---\n\n" + body.strip() + "\n")
    os.replace(tmp, path)


def cmd_delete(name):
    if not valid(name):
        sys.exit("bad name")
    top = entry(name)[0]
    if os.path.islink(top):
        return
    if os.path.isdir(top):
        shutil.rmtree(top)
    elif os.path.isfile(top):
        os.remove(top)


def memory_path(p):
    p = os.path.abspath(os.path.expanduser(p))
    if os.path.basename(p) != "CLAUDE.md":
        sys.exit("only CLAUDE.md")
    return p


def cmd_memory_read(p):
    p = memory_path(p)
    try:
        with open(p, encoding="utf-8") as f:
            sys.stdout.write(f.read())
    except FileNotFoundError:
        pass


def cmd_memory_write(p, text):
    p = memory_path(p)
    if text.strip() == "" and not os.path.exists(p):
        return
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text.rstrip() + "\n" if text.strip() else "")
    os.replace(tmp, p)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["--agents"]:
        AGENT_MODE = True
        a = a[1:]
    if a[:1] == ["list"]:
        cmd_list()
    elif a[:1] == ["save"] and 4 <= len(a) <= 6:
        cmd_save(*a[1:])
    elif a[:1] == ["delete"] and len(a) == 2:
        cmd_delete(a[1])
    elif a[:1] == ["memory-read"] and len(a) == 2:
        cmd_memory_read(a[1])
    elif a[:1] == ["memory-write"] and len(a) == 3:
        cmd_memory_write(a[1], a[2])
    else:
        sys.exit(__doc__)
