#!/usr/bin/env python3
"""claude-desk web mirror: the current Claude chat in a browser.

Listens on 127.0.0.1 only. From another computer open it through an SSH tunnel:
    ssh -L 8765:localhost:8765 alarm@<pi-address>   then browse http://localhost:8765

- GET  /            chat page
- GET  /api/chat    rows of the current conversation (from Claude Code's transcript)
- POST /api/send    {"text": ...} -> claude-desk IPC (queued if Claude is busy)
- POST /api/stop    interrupt the current answer
"""
import http.server
import json
import os
import re
import socketserver
import subprocess

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".local/state/claude-desk/state.json")
LIVE = os.path.join(HOME, ".local/state/claude-desk/live.json")
SHELL = os.path.join(HOME, ".local/share/claude-desk/shell.qml")
PAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")
PORT = 8765


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def read_state():
    return read_json(STATE)


def transcript_path(st):
    sid, work = st.get("sessionId"), st.get("workDir")
    if not sid or not work:
        return None
    return os.path.join(HOME, ".claude/projects", re.sub(r"[^a-zA-Z0-9]", "-", work), sid + ".jsonl")


def tool_summary(name, inp):
    if not isinstance(inp, dict):
        return ""
    base = lambda p: str(p).rsplit("/", 1)[-1]
    if name == "Bash":
        return str(inp.get("command", ""))
    if name in ("Read", "Write", "Edit", "NotebookEdit", "MultiEdit"):
        return base(inp.get("file_path") or inp.get("notebook_path") or "")
    if name in ("Grep", "Glob"):
        return str(inp.get("pattern", ""))
    if name == "WebFetch":
        return str(inp.get("url", ""))
    if name == "WebSearch":
        return str(inp.get("query", ""))
    if name in ("Task", "Agent"):
        return str(inp.get("description", ""))
    if name == "TodoWrite":
        todos = inp.get("todos") or []
        done = sum(1 for t in todos if t.get("status") == "completed")
        return f"список задач {done}/{len(todos)}"
    for v in inp.values():
        if isinstance(v, str):
            return v
    return ""


def chat_rows(path, limit=400):
    """Turn the Claude Code JSONL transcript into display rows."""
    rows, tools = [], {}
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except (OSError, TypeError):
        return rows
    with f:
        for line in f:
            if not line.startswith("{"):
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("isSidechain") or d.get("isMeta") or d.get("isCompactSummary"):
                continue
            c = (d.get("message") or {}).get("content")
            if d.get("type") == "user":
                if isinstance(c, str):
                    t = c.strip()
                    if t and not t.startswith("<"):
                        rows.append({"kind": "user", "text": t})
                    continue
                for b in c or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text":
                        t = b.get("text", "").strip()
                        if t and not t.startswith("<") and not t.startswith("[Request interrupted"):
                            rows.append({"kind": "user", "text": t})
                    elif b.get("type") == "image":
                        rows.append({"kind": "user", "text": "🖼 изображение"})
                    elif b.get("type") == "tool_result" and b.get("tool_use_id") in tools:
                        rows[tools[b["tool_use_id"]]]["status"] = "error" if b.get("is_error") else "ok"
            elif d.get("type") == "assistant" and isinstance(c, list):
                for b in c:
                    if b.get("type") == "text" and b.get("text", "").strip():
                        rows.append({"kind": "assistant", "text": b["text"]})
                    elif b.get("type") == "tool_use":
                        tools[b.get("id")] = len(rows)
                        rows.append({"kind": "tool", "tool": b.get("name", ""),
                                     "summary": tool_summary(b.get("name"), b.get("input"))[:300],
                                     "status": "running"})
    return rows[-limit:]


def ipc(*args):
    return subprocess.run(["quickshell", "ipc", "-p", SHELL, "call", "claude-desk", *args],
                          capture_output=True, text=True, timeout=10).returncode == 0


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "claude-desk-web"

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _same_origin(self):
        # block cross-site POSTs from other pages open in the same browser
        origin = self.headers.get("Origin")
        return origin is None or origin in (f"http://localhost:{PORT}", f"http://127.0.0.1:{PORT}")

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/":
            try:
                with open(PAGE, "rb") as f:
                    return self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError:
                return self._send(500, "index.html missing", "text/plain")
        if path == "/api/chat":
            st, live = read_state(), read_json(LIVE)
            return self._json({"busy": bool(live.get("busy", st.get("busy"))), "mode": st.get("permissionMode", ""),
                               "dir": st.get("workDir", ""), "rows": chat_rows(transcript_path(st)),
                               "streaming": live.get("streaming") or "", "permission": live.get("permission"),
                               "queue": live.get("queue") or [], "context": live.get("context", -1)})
        self._send(404, "not found", "text/plain")

    def do_POST(self):
        if not self._same_origin():
            return self._json({"ok": False}, 403)
        path = self.path.split("?", 1)[0]
        if path == "/api/send":
            n = min(int(self.headers.get("Content-Length") or 0), 64 * 1024)
            try:
                text = str(json.loads(self.rfile.read(n) or b"{}").get("text", "")).strip()
            except ValueError:
                text = ""
            if not text:
                return self._json({"ok": False, "error": "пусто"}, 400)
            return self._json({"ok": ipc("send", text[:20000])})
        if path == "/api/stop":
            return self._json({"ok": ipc("stop")})
        if path == "/api/retry":
            return self._json({"ok": ipc("retry")})
        if path == "/api/continue":
            return self._json({"ok": ipc("continueWork")})
        if path == "/api/answer":
            n = min(int(self.headers.get("Content-Length") or 0), 4096)
            try:
                decision = json.loads(self.rfile.read(n) or b"{}").get("decision", "")
            except ValueError:
                decision = ""
            if decision not in ("allow", "always", "auto", "deny"):
                return self._json({"ok": False}, 400)
            return self._json({"ok": ipc("answer", decision)})
        self._send(404, "not found", "text/plain")


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    srv = Server(("127.0.0.1", PORT), Handler)
    print(f"claude-desk web on 127.0.0.1:{PORT}", flush=True)
    srv.serve_forever()
