#!/usr/bin/env python3
"""Scheduled Claude prompts for claude-desk.

  tasks.py sync        rebuild systemd --user timers from prefs.json "tasks"
  tasks.py run <id>    run one task now: claude -p <prompt>, save the answer, notify

A task: {"id": "a1b2", "name": "Утренняя проверка", "prompt": "...", "time": "08:00", "enabled": true}
Claude runs in the default permission mode without anyone to ask, so actions that
need approval are refused (only always-allowed rules apply).
"""
import datetime
import glob
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
PREFS = os.path.join(HOME, ".local/state/claude-desk/prefs.json")
STATE = os.path.join(HOME, ".local/state/claude-desk/state.json")
UNITS = os.path.join(HOME, ".config/systemd/user")
OUT = os.path.join(HOME, "Documents/Claude/tasks")
SELF = os.path.join(HOME, ".local/share/claude-desk/tasks.py")


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def tasks():
    return [t for t in load(PREFS).get("tasks", []) if isinstance(t, dict) and re.fullmatch(r"[a-z0-9]{1,16}", str(t.get("id", "")))]


def sync():
    os.makedirs(UNITS, exist_ok=True)
    wanted = set()
    for t in tasks():
        if not t.get("enabled") or not re.fullmatch(r"\d{2}:\d{2}", str(t.get("time", ""))):
            continue
        unit = f"claude-task-{t['id']}"
        wanted.add(unit)
        with open(os.path.join(UNITS, unit + ".service"), "w") as f:
            f.write(f"[Unit]\nDescription=Claude task: {t.get('name', '')}\n\n[Service]\nType=oneshot\n"
                    f"ExecStart=/usr/bin/python3 -I {SELF} run {t['id']}\n")
        with open(os.path.join(UNITS, unit + ".timer"), "w") as f:
            f.write(f"[Unit]\nDescription=Claude task timer: {t.get('name', '')}\n\n[Timer]\n"
                    f"OnCalendar=*-*-* {t['time']}:00\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n")
    # drop timers of removed / disabled tasks
    for path in glob.glob(os.path.join(UNITS, "claude-task-*.timer")):
        unit = os.path.basename(path)[:-6]
        if unit not in wanted:
            subprocess.run(["systemctl", "--user", "disable", "--now", unit + ".timer"], capture_output=True)
            for ext in (".timer", ".service"):
                try:
                    os.remove(os.path.join(UNITS, unit + ext))
                except OSError:
                    pass
    subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
    for unit in wanted:
        subprocess.run(["systemctl", "--user", "enable", "--now", unit + ".timer"], capture_output=True)
    print(f"OK {len(wanted)}")


def run(task_id):
    t = next((x for x in tasks() if x["id"] == task_id), None)
    if not t:
        print("нет такого задания")
        return 1
    work = load(STATE).get("workDir") or os.path.join(HOME, "claude")
    try:
        r = subprocess.run(["claude", "-p", t["prompt"], "--output-format", "text"],
                           cwd=work, capture_output=True, text=True, timeout=900)
        answer = (r.stdout or r.stderr or "").strip() or "(пустой ответ)"
    except subprocess.TimeoutExpired:
        answer = "Задание не уложилось в 15 минут и было остановлено."
    os.makedirs(OUT, exist_ok=True)
    stamp = datetime.datetime.now()
    name = re.sub(r"[^\w-]+", "-", t.get("name", "task")).strip("-") or "task"
    path = os.path.join(OUT, f"{stamp:%Y-%m-%d_%H-%M}-{name}.md")
    with open(path, "w") as f:
        f.write(f"# {t.get('name', '')}\n\n_{stamp:%d.%m.%Y %H:%M}_\n\n**Задание:** {t['prompt']}\n\n---\n\n{answer}\n")
    short = re.sub(r"\s+", " ", answer)[:160]
    subprocess.run(["notify-send", "-a", "Claude", f"Задание: {t.get('name', '')}", short], capture_output=True)
    topic = str(load(PREFS).get("ntfyTopic", "")).strip()
    if topic:
        subprocess.run(["curl", "-s", "-m", "10", "-H", f"Title: Задание: {t.get('name', '')}", "-H", "Tags: robot",
                        "-d", short, f"https://ntfy.sh/{topic}"], capture_output=True)
    print(path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "sync":
        sync()
    elif len(sys.argv) >= 3 and sys.argv[1] == "run":
        sys.exit(run(sys.argv[2]))
    else:
        print(__doc__)
