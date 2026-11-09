import QtQuick
import Quickshell
import Quickshell.Io

// Drives a long-lived `claude -p --input-format stream-json` process and
// turns its event stream into rows of `messages`.
Item {
    id: session

    property string workDir: Quickshell.env("HOME") + "/claude"
    property string permissionMode: "default"
    property string sessionId: ""
    property string model: ""
    property bool busy: false
    property bool thinking: false
    property real lastCost: 0
    property real totalCost: 0
    // total_cost_usd in results is cumulative per CLI process; keep the last value to get per-turn cost
    property real _procCost: 0
    property int lastDurationMs: 0

    // From the initialize response: slash commands/skills and selectable models
    property var commands: []
    property var models: []
    property string modelChoice: ""   // alias passed to --model / set_model; "" = CLI default
    property string effort: ""        // "" = CLI default

    // Pending can_use_tool requests: [{requestId, toolName, input, summary, suggestions}]
    property var permissionQueue: []
    readonly property var currentPermission: permissionQueue.length > 0 ? permissionQueue[0] : null

    property ListModel messages: ListModel {}

    // The previous run stopped mid-answer (power loss, crash): offer a "continue" button
    property bool interrupted: false
    // Messages typed while Claude is busy: [{text, images}], sent one by one after each answer
    property var queue: []
    // Context window fill of the last API call, 0..1 (-1 = unknown yet)
    property real contextUsed: -1
    property int contextWindow: 200000
    // What the user sent, oldest first; ↑ in an empty composer walks back through it
    property var sentHistory: []

    // key "msgId:index" -> row, toolUseId -> row
    property var _blockRows: ({})
    // msgId -> [{row, done}] text rows in stream order; assistant events
    // carry one block each with its own indexing, so match by order
    property var _msgTextRows: ({})
    property var _toolRows: ({})
    property string _streamMsgId: ""
    property var _outbox: []
    property bool _ready: false
    property bool _restarting: false
    property bool _restored: false

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/claude-desk"

    signal scrollRequested()
    signal modelMenuRequested()

    function toolSummary(name, input) {
        if (!input) return "";
        let pick = function(k) { return input[k] !== undefined ? String(input[k]) : ""; };
        let base = function(p) { let i = p.lastIndexOf("/"); return i >= 0 ? p.substring(i + 1) : p; };
        switch (name) {
        case "Bash": return pick("command");
        case "Read": case "Write": case "Edit": case "NotebookEdit": return base(pick("file_path") || pick("notebook_path"));
        case "Grep": return pick("pattern") + (input.path ? "  в " + base(pick("path")) : "");
        case "Glob": return pick("pattern");
        case "WebFetch": return pick("url");
        case "WebSearch": return pick("query");
        case "Task": case "Agent": return pick("description");
        case "TodoWrite": return "список задач";
        }
        for (let k in input) if (typeof input[k] === "string") return input[k];
        return "";
    }

    // Full form for the permission card: whole command or absolute path
    function toolDetail(name, input) {
        if (!input) return "";
        if (input.command !== undefined) return String(input.command);
        if (input.file_path !== undefined) return String(input.file_path);
        if (input.notebook_path !== undefined) return String(input.notebook_path);
        if (input.url !== undefined) return String(input.url);
        return toolSummary(name, input);
    }

    // Tool input kept on the row for richer cards; only for tools that need it
    function _toolInput(name, input) {
        if (!input) return "";
        if (name === "Edit" || name === "MultiEdit" || name === "Write" || name === "TodoWrite") {
            let j = JSON.stringify(input);
            return j.length > 20000 ? "" : j;
        }
        return "";
    }

    function _append(row) {
        let defaults = { kind: "", text: "", toolName: "", summary: "", detail: "", status: "", toolId: "", streaming: false, input: "" };
        for (let k in row) defaults[k] = row[k];
        messages.append(defaults);
        scrollRequested();
        return messages.count - 1;
    }

    function _start() {
        let args = ["claude", "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose", "--include-partial-messages",
            "--permission-prompt-tool", "stdio",
            "--permission-mode", session.permissionMode,
            // only makes "Без вопросов" selectable later; it is not turned on by this
            "--allow-dangerously-skip-permissions"];
        if (session.modelChoice !== "") args.push("--model", session.modelChoice);
        if (session.effort !== "") args.push("--effort", session.effort);
        if (Prefs.appendPrompt.trim() !== "") args.push("--append-system-prompt", Prefs.appendPrompt.trim());
        if (session.sessionId !== "") args.push("--resume", session.sessionId);
        proc.command = ["bash", "-lc", "mkdir -p \"$1\" \"$2\" && cd \"$1\" && shift 2 && exec \"$@\"", "claude-desk", session.workDir, session.stateDir].concat(args);
        session._ready = false;
        session._procCost = 0;
        proc.running = true;
    }

    function _write(obj) {
        if (!proc.running || !session._ready) {
            session._outbox.push(obj);
            if (!proc.running) _start();
            return;
        }
        proc.write(JSON.stringify(obj) + "\n");
    }

    // images: [{media: "image/png", data: <base64>}] sent as content blocks
    function send(text, images) {
        let t = text.trim();
        let imgs = images || [];
        if (t === "" && imgs.length === 0) return;
        // Commands the app handles itself instead of the CLI
        if (t === "/clear" || t === "/new") { newChat(); return; }
        if (t === "/model") { modelMenuRequested(); return; }
        session.interrupted = false;
        let shown = imgs.length > 0 ? (t + (t !== "" ? "\n" : "") + "󰋩 изображений: " + imgs.length) : t;
        _append({ kind: "user", text: shown });
        if (t !== "") session.sentHistory = session.sentHistory.filter(x => x !== t).concat([t]).slice(-50);
        session.busy = true;
        session.thinking = true;
        let content = t;
        if (imgs.length > 0) {
            content = imgs.map(i => ({ type: "image", source: { type: "base64", media_type: i.media, data: i.data } }));
            content.push({ type: "text", text: t !== "" ? t : "Посмотри на изображение." });
        }
        _write({ type: "user", message: { role: "user", content: content } });
    }

    function enqueue(text, images) {
        if (text.trim() === "" && (!images || images.length === 0)) return;
        session.queue = session.queue.concat([{ text: text, images: images || [] }]);
    }
    function dequeue(i) {
        let q = session.queue.slice();
        q.splice(i, 1);
        session.queue = q;
    }
    function _flushQueue() {
        if (session.busy || session.queue.length === 0) return;
        let next = session.queue[0];
        session.queue = session.queue.slice(1);
        send(next.text, next.images);
    }

    // ── live.json for the web mirror: text being typed right now + pending permission ──
    property string liveText: ""
    onLiveTextChanged: _live()
    onPermissionQueueChanged: _live()
    onQueueChanged: _live()
    onContextUsedChanged: _live()
    function _live() { if (!liveTimer.running) liveTimer.start(); }
    Timer {
        id: liveTimer
        interval: 350
        onTriggered: {
            let p = session.currentPermission;
            liveFile.setText(JSON.stringify({
                busy: session.busy,
                streaming: session.liveText,
                permission: p ? { tool: p.toolName, summary: p.summary || "", detail: p.detail || "",
                                  canAlways: !!(p.suggestions && p.suggestions.length > 0) } : null,
                queue: session.queue.map(q => q.text),
                context: session.contextUsed
            }));
        }
    }
    FileView { id: liveFile; path: session.stateDir + "/live.json"; printErrors: false }

    // The visible conversation as Markdown (for export / gist)
    function toMarkdown() {
        let out = ["# Чат с Claude", "", "_" + Qt.formatDateTime(new Date(), "d MMMM yyyy, HH:mm") + " · " + session.workDir + "_", ""];
        for (let i = 0; i < messages.count; i++) {
            let r = messages.get(i);
            if (r.kind === "user") out.push("### 🧑 Ты", "", r.text, "");
            else if (r.kind === "assistant") out.push("### ✻ Claude", "", r.text, "");
            else if (r.kind === "tool") out.push("> `" + r.toolName + "` " + (r.summary || "").replace(/\n/g, " ").substring(0, 200)
                                               + (r.status === "error" ? " ✕" : ""), "");
            else if (r.kind === "error") out.push("> ⚠ " + r.text, "");
        }
        return out.join("\n");
    }

    // Text of the last thing the user sent (without the image note)
    function lastUserText() {
        for (let i = messages.count - 1; i >= 0; i--) {
            let r = messages.get(i);
            if (r.kind === "user") return r.text.replace(/\n?󰋩 изображений: \d+$/, "");
        }
        return "";
    }
    function retryLast() {
        let t = lastUserText();
        if (t !== "" && !session.busy) send(t);
    }

    // After a power cut / crash: ask Claude to pick up where it stopped
    function continueWork() {
        session.interrupted = false;
        send("Продолжи с того места, где остановился: работа прервалась (отключилось питание или упал процесс). Сначала проверь, что из начатого уже сделано.");
    }

    // Open an earlier conversation: replay its transcript, then --resume it
    function resume(id) {
        if (id === "" || id === session.sessionId) return;
        newChat();
        session.sessionId = id;
        historyFile.path = "";
        historyFile.path = Quickshell.env("HOME") + "/.claude/projects/"
            + session.workDir.replace(/[^a-zA-Z0-9]/g, "-") + "/" + id + ".jsonl";
    }

    // ── spending per day: ~/.local/state/claude-desk/costs.json {"YYYY-MM-DD": usd} ──
    property var costs: ({})
    function _addCost(usd) {
        if (!(usd > 0)) return;
        let day = Qt.formatDate(new Date(), "yyyy-MM-dd");
        let c = Object.assign({}, session.costs);
        c[day] = (c[day] || 0) + usd;
        session.costs = c;
        costsFile.setText(JSON.stringify(c, null, 1) + "\n");
    }
    function costSince(days) {
        let from = Qt.formatDate(new Date(Date.now() - (days - 1) * 86400000), "yyyy-MM-dd");
        let sum = 0;
        for (let d in session.costs) if (days <= 0 || d >= from) sum += session.costs[d];
        return sum;
    }
    FileView {
        id: costsFile
        path: session.stateDir + "/costs.json"
        printErrors: false
        onLoaded: { try { session.costs = JSON.parse(text()) || {}; } catch (e) {} }
    }

    function interrupt() {
        if (!session.busy) return;
        _write({ type: "control_request", request_id: "int-" + Date.now(), request: { subtype: "interrupt" } });
    }

    function setMode(mode) {
        session.permissionMode = mode;
        if (proc.running && session._ready)
            _write({ type: "control_request", request_id: "mode-" + Date.now(), request: { subtype: "set_permission_mode", mode: mode } });
    }

    function answerPermission(decision) {
        let p = session.currentPermission;
        if (!p) return;
        let response;
        // "auto": allow this one and stop asking about safe actions from now on
        if (decision === "auto") setMode("auto");
        if (decision === "deny") {
            response = { behavior: "deny", message: "Пользователь отклонил это действие." };
        } else {
            response = { behavior: "allow", updatedInput: p.input };
            if (decision === "always" && p.suggestions && p.suggestions.length > 0)
                response.updatedPermissions = p.suggestions;
        }
        _write({ type: "control_response", response: { subtype: "success", request_id: p.requestId, response: response } });
        let row = session._toolRows[p.toolUseId];
        if (row !== undefined && decision === "deny") messages.setProperty(row, "status", "denied");
        let q = session.permissionQueue.slice(1);
        session.permissionQueue = q;
    }

    // Model switches live via set_model; effort only exists as a CLI flag,
    // so it restarts the process and resumes the same conversation.
    function setModel(alias) {
        if (alias === session.modelChoice) return;
        session.modelChoice = alias;
        if (proc.running && session._ready)
            _write({ type: "control_request", request_id: "model-" + Date.now(), request: { subtype: "set_model", model: alias === "" ? "default" : alias } });
    }

    function setEffort(level) {
        if (level === session.effort || session.busy) return;
        session.effort = level;
        restart();
    }

    // Restart the CLI (picks up new flags) and resume the same conversation
    function restart() {
        if (session.busy) return;
        session._restarting = proc.running;
        proc.running = false;
        restartTimer.restart();
    }

    // Desktop notification, only while the window is in the background
    function _notify(title, body) {
        let b = body.replace(/\s+/g, " ").trim();
        if (b.length > 140) b = b.substring(0, 140) + "…";
        // phone push (ntfy.sh): sent even while the window is focused — you may be away from the deck
        if (Prefs.ntfyTopic.trim() !== "")
            Quickshell.execDetached(["curl", "-s", "-m", "10", "-H", "Title: " + title, "-H", "Tags: robot",
                                     "-d", b, "https://ntfy.sh/" + Prefs.ntfyTopic.trim()]);
        if (!Prefs.notify || Qt.application.state === Qt.ApplicationActive) return;
        Quickshell.execDetached(["notify-send", "-a", "Claude", "-i", "dialog-information", title, b]);
        if (Prefs.sound)
            Quickshell.execDetached(["canberra-gtk-play", "-i", "message-new-instant"]);
    }

    readonly property var currentModelInfo: {
        let v = session.modelChoice === "" ? "default" : session.modelChoice;
        for (let i = 0; i < session.models.length; i++) if (session.models[i].value === v) return session.models[i];
        return null;
    }

    // Commands whose name (or alias) starts with `prefix`, best matches first
    function matchCommands(prefix) {
        let p = prefix.toLowerCase(), head = [], rest = [];
        for (let i = 0; i < session.commands.length; i++) {
            let c = session.commands[i];
            if (c.name.startsWith("__")) continue;
            let names = [c.name].concat(c.aliases || []);
            if (names.some(n => n.toLowerCase().startsWith(p))) head.push(c);
            else if (p.length > 1 && c.name.toLowerCase().indexOf(p) >= 0) rest.push(c);
        }
        // app-side command: opens the skills manager (handled in shell.qml)
        if (p !== "" && "skills".startsWith(p))
            head.unshift({ name: "skills", description: "Мои скиллы: создать, изменить, удалить", argumentHint: "", local: true });
        return head.concat(rest);
    }

    function newChat(dir) {
        session._restarting = true;
        proc.running = false;
        if (!dir && Prefs.defaultDir.trim() !== "") dir = Prefs.defaultDir.trim().replace(/^~/, Quickshell.env("HOME"));
        if (dir) session.workDir = dir;
        session.sessionId = "";
        session.busy = false;
        session.thinking = false;
        session.permissionQueue = [];
        session._blockRows = {};
        session._msgTextRows = {};
        session._toolRows = {};
        session._outbox = [];
        session.totalCost = 0;
        session.interrupted = false;
        session.queue = [];
        session.contextUsed = -1;
        messages.clear();
        restartTimer.restart();
    }

    Timer { id: restartTimer; interval: 200; onTriggered: session._start() }
    // give the user a few seconds to see what happened before continuing by itself
    Timer { id: autoContinueTimer; interval: 4000; onTriggered: if (session.interrupted && !session.busy) session.continueWork() }

    function _handle(e) {
        // Subagent traffic is summarised by its Task row, not shown inline
        if (e.parent_tool_use_id && (e.type === "assistant" || e.type === "user" || e.type === "stream_event")) return;
        switch (e.type) {
        case "control_response":
            if (e.response && e.response.request_id === "init") {
                let info = e.response.response || {};
                if (Array.isArray(info.commands)) session.commands = info.commands;
                if (Array.isArray(info.models)) session.models = info.models;
                session._ready = true;
                let box = session._outbox;
                session._outbox = [];
                for (let i = 0; i < box.length; i++) proc.write(JSON.stringify(box[i]) + "\n");
            } else if (e.response && e.response.subtype === "error" && String(e.response.request_id).startsWith("mode-")) {
                _append({ kind: "error", text: "Не удалось сменить режим: " + (e.response.error || "ошибка") });
            }
            break;

        case "control_request":
            if (e.request && e.request.subtype === "can_use_tool") {
                let r = e.request;
                let q = session.permissionQueue.slice();
                q.push({
                    requestId: e.request_id,
                    toolName: r.display_name || r.tool_name,
                    toolUseId: r.tool_use_id || "",
                    input: r.input || {},
                    summary: r.description || toolSummary(r.tool_name, r.input),
                    detail: toolDetail(r.tool_name, r.input),
                    suggestions: r.permission_suggestions || []
                });
                session.permissionQueue = q;
                _notify("Claude ждёт разрешения", (r.display_name || r.tool_name) + ": " + q[q.length - 1].summary);
            } else {
                // Unknown host request: acknowledge so the CLI doesn't wait forever
                proc.write(JSON.stringify({ type: "control_response", response: { subtype: "error", request_id: e.request_id, error: "unsupported" } }) + "\n");
            }
            break;

        case "system":
            if (e.subtype === "init") {
                session.sessionId = e.session_id || session.sessionId;
                session.model = e.model || session.model;
            } else if (e.subtype === "status" && e.status === "requesting") {
                session.thinking = true;
            }
            break;

        case "stream_event": {
            let ev = e.event || {};
            if (ev.type === "message_start" && ev.message) {
                session._streamMsgId = ev.message.id;
            } else if (ev.type === "content_block_start" && ev.content_block) {
                if (ev.content_block.type === "text") {
                    session.thinking = false;
                    let row = _append({ kind: "assistant", text: "", streaming: true });
                    session._blockRows[session._streamMsgId + ":" + ev.index] = row;
                    let id = session._streamMsgId;
                    if (!session._msgTextRows[id]) session._msgTextRows[id] = [];
                    session._msgTextRows[id].push({ row: row, done: false });
                } else if (ev.content_block.type === "thinking") {
                    session.thinking = true;
                }
            } else if (ev.type === "content_block_delta" && ev.delta && ev.delta.type === "text_delta") {
                let row = session._blockRows[session._streamMsgId + ":" + ev.index];
                if (row !== undefined) {
                    messages.setProperty(row, "text", messages.get(row).text + ev.delta.text);
                    session.liveText = messages.get(row).text;
                    scrollRequested();
                }
            } else if (ev.type === "content_block_stop") {
                let row = session._blockRows[session._streamMsgId + ":" + ev.index];
                if (row !== undefined) messages.setProperty(row, "streaming", false);
                session.liveText = "";
            }
            break;
        }

        case "assistant": {
            let m = e.message || {};
            if (m.usage) {
                let u = m.usage;
                let used = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
                if (used > 0) session.contextUsed = Math.min(1, used / session.contextWindow);
            }
            let content = m.content || [];
            for (let i = 0; i < content.length; i++) {
                let b = content[i];
                if (b.type === "text") {
                    if (!session._msgTextRows[m.id]) session._msgTextRows[m.id] = [];
                    let list = session._msgTextRows[m.id];
                    let slot = null;
                    for (let j = 0; j < list.length; j++) {
                        if (!list[j].done) { slot = list[j]; break; }
                    }
                    if (slot) {
                        messages.setProperty(slot.row, "text", b.text);
                        messages.setProperty(slot.row, "streaming", false);
                        slot.done = true;
                    } else {
                        list.push({ row: _append({ kind: "assistant", text: b.text }), done: true });
                    }
                    session.thinking = false;
                } else if (b.type === "tool_use" && session._toolRows[b.id] === undefined) {
                    session._toolRows[b.id] = _append({
                        kind: "tool", toolName: b.name, toolId: b.id,
                        summary: toolSummary(b.name, b.input), status: "running",
                        input: _toolInput(b.name, b.input)
                    });
                    session.thinking = true;
                }
            }
            break;
        }

        case "user": {
            let content = (e.message && Array.isArray(e.message.content)) ? e.message.content : [];
            for (let i = 0; i < content.length; i++) {
                let b = content[i];
                if (b.type !== "tool_result") continue;
                let row = session._toolRows[b.tool_use_id];
                if (row === undefined) continue;
                let txt = typeof b.content === "string" ? b.content
                    : (Array.isArray(b.content) ? b.content.filter(c => c.type === "text").map(c => c.text).join("\n") : "");
                if (txt.length > 4000) txt = txt.substring(0, 4000) + "\n…";
                messages.setProperty(row, "detail", txt);
                if (messages.get(row).status !== "denied")
                    messages.setProperty(row, "status", b.is_error ? "error" : "ok");
            }
            session.thinking = true;
            break;
        }

        case "result":
            session.busy = false;
            session.liveText = "";
            if (e.modelUsage) {
                for (let k in e.modelUsage) {
                    let cw = e.modelUsage[k].contextWindow;
                    if (cw > 0) { session.contextWindow = cw; break; }
                }
            }
            Qt.callLater(session._flushQueue);
            session.thinking = false;
            session.permissionQueue = [];
            let cum = e.total_cost_usd || 0;
            session.lastCost = cum >= session._procCost ? cum - session._procCost : cum;
            session._procCost = cum;
            session.lastDurationMs = e.duration_ms || 0;
            session.totalCost += session.lastCost;
            _addCost(session.lastCost);
            if (e.session_id) session.sessionId = e.session_id;
            for (let id in session._toolRows) {
                let r = session._toolRows[id];
                if (messages.get(r).status === "running") messages.setProperty(r, "status", "error");
            }
            if (e.is_error && e.subtype !== "success")
                _append({ kind: "error", text: (e.errors && e.errors.join ? e.errors.join("\n") : "") || "Запрос прерван." });
            else
                _notify("Claude ответил", typeof e.result === "string" ? e.result : "");
            break;
        }
    }

    // ── persistence: the chat survives restarts and reloads ──
    function _save() {
        if (!session._restored) return;
        saveTimer.restart();
    }
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: stateFile.setText(JSON.stringify({
            sessionId: session.sessionId, workDir: session.workDir,
            permissionMode: session.permissionMode,
            modelChoice: session.modelChoice, effort: session.effort,
            busy: session.busy
        }, null, 2) + "\n")
    }
    onSessionIdChanged: _save()
    onWorkDirChanged: _save()
    onPermissionModeChanged: _save()
    onModelChoiceChanged: _save()
    onEffortChanged: _save()
    onBusyChanged: { _save(); _live(); }

    function _restore() {
        let s = {};
        try { s = JSON.parse(stateFile.text()) || {}; } catch (err) { s = {}; }
        if (s.workDir) session.workDir = s.workDir;
        if (s.permissionMode) session.permissionMode = s.permissionMode;
        if (s.modelChoice !== undefined) session.modelChoice = s.modelChoice;
        if (s.effort !== undefined) session.effort = s.effort;
        // was mid-answer when the app (or the whole Pi) went down
        if (s.busy === true && s.sessionId) {
            session.interrupted = true;
            if (Prefs.autoContinue) autoContinueTimer.start();
        }
        if (s.sessionId) {
            session.sessionId = s.sessionId;
            historyFile.path = Quickshell.env("HOME") + "/.claude/projects/"
                + session.workDir.replace(/[^a-zA-Z0-9]/g, "-") + "/" + s.sessionId + ".jsonl";
        }
        session._restored = true;
        if (!proc.running) _start();
    }

    // Rebuild the visible feed from the CLI's own transcript
    function _replay(text) {
        let lines = text.split("\n");
        for (let n = 0; n < lines.length; n++) {
            if (lines[n].length === 0 || lines[n][0] !== "{") continue;
            let d;
            try { d = JSON.parse(lines[n]); } catch (err) { continue; }
            if (d.isSidechain || d.isMeta || d.isCompactSummary || !d.message) continue;
            let c = d.message.content;
            if (d.type === "user") {
                if (typeof c === "string") {
                    if (c.trim() !== "" && c[0] !== "<") _append({ kind: "user", text: c.trim() });
                    continue;
                }
                if (!Array.isArray(c)) continue;
                for (let i = 0; i < c.length; i++) {
                    let b = c[i];
                    if (b.type === "text" && b.text.trim() !== "" && b.text[0] !== "<") {
                        _append({ kind: "user", text: b.text.trim() });
                    } else if (b.type === "tool_result") {
                        let row = session._toolRows[b.tool_use_id];
                        if (row === undefined) continue;
                        let txt = typeof b.content === "string" ? b.content
                            : (Array.isArray(b.content) ? b.content.filter(x => x.type === "text").map(x => x.text).join("\n") : "");
                        if (txt.length > 4000) txt = txt.substring(0, 4000) + "\n…";
                        messages.setProperty(row, "detail", txt);
                        messages.setProperty(row, "status", b.is_error ? "error" : "ok");
                    }
                }
            } else if (d.type === "assistant" && Array.isArray(c)) {
                for (let i = 0; i < c.length; i++) {
                    let b = c[i];
                    if (b.type === "text" && b.text.trim() !== "")
                        _append({ kind: "assistant", text: b.text });
                    else if (b.type === "tool_use" && session._toolRows[b.id] === undefined)
                        session._toolRows[b.id] = _append({ kind: "tool", toolName: b.name, toolId: b.id, summary: toolSummary(b.name, b.input), status: "running", input: _toolInput(b.name, b.input) });
                }
            }
        }
        // Calls cut off by a restart never got a result
        for (let id in session._toolRows) {
            let r = session._toolRows[id];
            if (messages.get(r).status === "running") messages.setProperty(r, "status", "error");
        }
        let sent = [];
        for (let i = 0; i < messages.count; i++)
            if (messages.get(i).kind === "user") sent.push(messages.get(i).text);
        session.sentHistory = sent.slice(-50);
        scrollRequested();
    }

    FileView {
        id: stateFile
        path: session.stateDir + "/state.json"
        printErrors: false
        onLoaded: session._restore()
        onLoadFailed: session._restore()
    }

    FileView {
        id: historyFile
        printErrors: false
        onLoaded: session._replay(historyFile.text())
    }

    Process {
        id: proc
        stdinEnabled: true

        onStarted: {
            proc.write(JSON.stringify({ type: "control_request", request_id: "init", request: { subtype: "initialize", hooks: null } }) + "\n");
        }

        stdout: SplitParser {
            onRead: function(line) {
                if (line.length === 0 || line[0] !== "{") return;
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                session._handle(e);
            }
        }

        stderr: SplitParser {
            onRead: function(line) { if (line.trim() !== "") console.log("claude:", line); }
        }

        onExited: function(code) {
            let wasReady = session._ready;
            session._ready = false;
            if (session._restarting) { session._restarting = false; return; }
            // A stale --resume id makes the CLI exit before initialize; start fresh once
            if (!wasReady && session.sessionId !== "") {
                session.sessionId = "";
                restartTimer.restart();
                return;
            }
            if (session.busy) {
                session.busy = false;
                session.thinking = false;
                session.permissionQueue = [];
                session._append({ kind: "error", text: "Claude Code завершился (код " + code + "). Следующее сообщение продолжит этот же разговор." });
                session.interrupted = true;
            }
        }
    }

}
