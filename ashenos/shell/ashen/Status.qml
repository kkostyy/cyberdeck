import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import Quickshell.Bluetooth

// Everything the bar shows: time, window, sound, music, Wi-Fi, keyboard layout.
Scope {
    id: st

    // time
    property SystemClock clock: SystemClock { precision: SystemClock.Seconds }

    // active window → island
    readonly property var activeWindow: ToplevelManager.activeToplevel
    readonly property string windowTitle: activeWindow && activeWindow.title ? activeWindow.title : "Рабочий стол"

    // sound
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: st.sink ? [st.sink] : [] }
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    function setVolume(v) { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)); } }
    function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted; }

    // music: the playing player, else the first one
    readonly property var player: {
        let ps = Mpris.players.values;
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i];
        return ps.length > 0 ? ps[0] : null;
    }
    readonly property bool playing: player !== null && player.isPlaying
    readonly property string trackTitle: player ? (player.trackTitle || player.identity || "") : ""
    readonly property string trackArtist: player ? (player.trackArtist || "") : ""
    readonly property string trackArt: player ? (player.trackArtUrl || "") : ""
    // position only updates on demand for MPRIS
    Timer {
        running: st.playing
        interval: 1000
        repeat: true
        onTriggered: if (st.player) st.player.positionChanged()
    }

    // ── Wi-Fi via nmcli -t (fields split on unescaped ':') ──
    property string ssid: ""
    property int signal: 0
    property bool wifiOn: true
    property string freq: ""
    property string security: ""
    property string ip: ""
    property var networks: []          // [{ssid, signal, secure, active}] strongest first
    property bool scanning: false
    readonly property string wifiIcon: !wifiOn ? "󰤮" : ssid === "" ? "󰤯"
        : signal > 75 ? "󰤨" : signal > 50 ? "󰤥" : signal > 25 ? "󰤢" : "󰤟"
    function _nmSplit(line) {
        let out = [], cur = "";
        for (let i = 0; i < line.length; i++) {
            let ch = line[i];
            if (ch === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (ch === ":") { out.push(cur); cur = ""; continue; }
            cur += ch;
        }
        out.push(cur);
        return out;
    }
    Process {
        id: wifiProc
        command: ["bash", "-c", "export LC_ALL=C; nmcli -t -f WIFI radio; nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ,SECURITY dev wifi 2>/dev/null; echo ---; nmcli -g IP4.ADDRESS dev show $(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2==\"wifi\"{print $1; exit}') 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.split("---");
                let lines = parts[0].trim().split("\n");
                st.wifiOn = lines[0] === "enabled";
                let seen = {}, nets = [], act = null;
                for (let i = 1; i < lines.length; i++) {
                    let f = st._nmSplit(lines[i]);
                    if (f.length < 5) continue;
                    let n = { active: f[0] === "yes", ssid: f[1], signal: parseInt(f[2]) || 0, freq: f[3], secure: f[4] !== "" && f[4] !== "--", security: f[4] };
                    if (n.active) act = n;
                    if (n.ssid === "" || seen[n.ssid]) continue;
                    seen[n.ssid] = true;
                    nets.push(n);
                }
                nets.sort((a, b) => (b.active - a.active) || (b.signal - a.signal));
                st.networks = nets;
                st.ssid = act ? act.ssid : "";
                st.signal = act ? act.signal : 0;
                st.freq = act ? act.freq : "";
                st.security = act ? act.security : "";
                st.ip = (parts[1] || "").trim().replace(/\/\d+$/, "");
                st.scanning = false;
            }
        }
    }
    Timer { interval: 8000; running: true; repeat: true; triggeredOnStart: true; onTriggered: wifiProc.running = true }
    function setWifi(on) {
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        st.wifiOn = on;
        wifiRefresh.restart();
    }
    function scanWifi() {
        st.scanning = true;
        Quickshell.execDetached(["nmcli", "dev", "wifi", "rescan"]);
        wifiRefresh.interval = 4000;
        wifiRefresh.restart();
    }
    // known network: just connect; new secured one needs the password
    function connectWifi(ssid, password) {
        let cmd = ["nmcli", "dev", "wifi", "connect", ssid];
        if (password) cmd.push("password", password);
        Quickshell.execDetached(cmd);
        wifiRefresh.interval = 6000;
        wifiRefresh.restart();
    }
    Timer { id: wifiRefresh; interval: 2500; onTriggered: { interval = 2500; wifiProc.running = true; } }

    // ── who and how long ──
    readonly property string user: Quickshell.env("USER") || "user"
    property string host: "ashenos"
    property int uptime: 0                         // seconds
    property string face: ""                       // ~/.face if present
    Process {
        id: whoProc
        command: ["bash", "-c", "cat /etc/hostname; cut -d. -f1 /proc/uptime; for f in \"$HOME/.face\" \"$HOME/.face.icon\"; do [ -s \"$f\" ] && { echo \"$f\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.trim().split("\n");
                if (l[0]) st.host = l[0].trim();
                st.uptime = parseInt(l[1]) || 0;
                st.face = l[2] || "";
            }
        }
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: whoProc.running = true }
    readonly property string uptimeText: {
        let h = Math.floor(uptime / 3600), m = Math.floor(uptime % 3600 / 60);
        return "работает " + (h > 0 ? h + " ч " : "") + m + " мин";
    }

    // short status shown in the island by events (timer, recording, layout…)
    property string islandText: ""

    // ── notifications: we are the notification server ──
    signal notified(var n)
    readonly property var notifs: server.trackedNotifications.values.slice().reverse()
    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => { n.tracked = true; st.notified(n); }
    }
    function clearNotifs() {
        let all = server.trackedNotifications.values.slice();
        for (let i = 0; i < all.length; i++) all[i].dismiss();
    }
    function activate(n) {
        let acts = n.actions || [];
        let def = acts.find(a => a.identifier === "default") || (acts.length === 1 ? acts[0] : null);
        if (def) def.invoke();
        else n.dismiss();
    }

    // ── bluetooth ──
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property bool btOn: bt !== null && bt.enabled
    readonly property var btDevices: bt ? bt.devices.values.filter(d => d.paired || d.connected) : []
    readonly property var btConnected: btDevices.filter(d => d.connected)
    readonly property string btIcon: !btOn ? "󰂲" : btConnected.length > 0 ? "󰂱" : "󰂯"

    // ── weather (weather.py, every 15 min) ──
    property var weather: null
    readonly property string weatherText: weather ? st.wmoText(weather.code) : ""
    function wmoText(c) {
        if (c === 0) return "ясно";
        if (c <= 2) return "переменная облачность";
        if (c === 3) return "облачно";
        if (c <= 48) return "туман";
        if (c <= 57) return "морось";
        if (c <= 67) return "дождь";
        if (c <= 77) return "снег";
        if (c <= 82) return "ливень";
        if (c <= 86) return "снегопад";
        return "гроза";
    }
    function wmoGlyph(c, day) {
        if (c === 0) return day === false ? "󰖔" : "󰖙";
        if (c <= 2) return day === false ? "󰼱" : "󰖕";
        if (c === 3) return "󰖐";
        if (c <= 48) return "󰖑";
        if (c <= 67) return "󰖗";
        if (c <= 77) return "󰖘";
        if (c <= 82) return "󰖖";
        if (c <= 86) return "󰼶";
        return "󰖓";
    }
    Process {
        id: wxProc
        command: ["python3", "-I", Qt.resolvedUrl("weather.py").toString().replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { let w = JSON.parse(this.text); if (!w.error) st.weather = w; } catch (e) {}
            }
        }
    }
    Timer { interval: 15 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: wxProc.running = true }
    // after a city change: give the config a moment to be written, then fetch
    function refreshWeather() { wxRefresh.restart(); }
    Timer { id: wxRefresh; interval: 1200; onTriggered: { wxProc.running = false; wxProc.running = true; } }

    // ── system stats: cpu %, ram %, temperature °C ──
    property real cpu: 0
    property real ram: 0
    property real temp: 0
    property var _prev: null
    Process {
        id: sys
        command: ["bash", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                let l = this.text.trim().split("\n");
                let c = l[0].trim().split(/\s+/).slice(1).map(Number);
                let idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0);
                if (st._prev) {
                    let dt = total - st._prev[1], di = idle - st._prev[0];
                    if (dt > 0) st.cpu = Math.max(0, Math.min(1, 1 - di / dt));
                }
                st._prev = [idle, total];
                let mt = parseInt(l[1].split(/\s+/)[1]), ma = parseInt(l[2].split(/\s+/)[1]);
                if (mt > 0) st.ram = 1 - ma / mt;
                st.temp = (parseInt(l[3]) || 0) / 1000;
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: sys.running = true }

    // ── screen time: seconds per app per day, ~/.local/state/ashen/usage.json (14 days) ──
    property var usage: ({})
    property bool away: false            // idle for 2 min or locked — not counted
    property bool locked: false
    readonly property string today: Qt.formatDate(clock.date, "yyyy-MM-dd")
    IdleMonitor { timeout: 120; respectInhibitors: false; onIsIdleChanged: st.away = isIdle }
    FileView {
        id: usageFile
        path: Quickshell.env("HOME") + "/.local/state/ashen/usage.json"
        onLoaded: { try { st.usage = JSON.parse(text()); } catch (e) { st.usage = {}; } }
    }
    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ashen"] }
    property int _sinceSave: 0
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            let w = ToplevelManager.activeToplevel;
            if (st.away || st.locked || !w || !w.appId) return;
            let u = Object.assign({}, st.usage);
            let day = Object.assign({}, u[st.today] || {});
            day[w.appId] = (day[w.appId] || 0) + 10;
            u[st.today] = day;
            let days = Object.keys(u).sort();
            while (days.length > 14) delete u[days.shift()];
            st.usage = u;
            if (++st._sinceSave >= 6) { st._sinceSave = 0; usageFile.setText(JSON.stringify(u)); }
        }
    }
    function usageFor(day) {
        let d = usage[day] || {};
        return Object.keys(d).map(k => ({ app: k, secs: d[k] })).sort((a, b) => b.secs - a.secs);
    }

    // ── volume / brightness steps (keys) ──
    function stepVolume(d) { setVolume(Math.round((volume + d) * 20) / 20); }
    property real brightness: 0
    Process {
        id: brProc
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                let f = this.text.trim().split("\n")[0].split(",");
                if (f.length >= 5) st.brightness = parseInt(f[2]) / parseInt(f[4]);
            }
        }
    }
    function stepBrightness(d) {
        let v = Math.max(0.01, Math.min(1, Math.round((brightness + d) * 20) / 20));
        brightness = v;
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", Math.round(v * 100) + "%"]);
    }
    function setBrightness(v) {
        brightness = Math.max(0.01, Math.min(1, v));
        Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", Math.round(brightness * 100) + "%"]);
    }

    // ── clipboard history (cliphist) ──
    property var clips: []
    Process {
        id: clipProc
        command: ["bash", "-c", "cliphist list 2>/dev/null | head -n 8"]
        stdout: StdioCollector {
            onStreamFinished: {
                st.clips = this.text.split("\n").filter(l => l !== "").map(l => {
                    let i = l.indexOf("\t");
                    let t = l.substring(i + 1);
                    return { id: l.substring(0, i), text: /^\[\[ binary data/.test(t) ? "󰋩  изображение" : t };
                });
            }
        }
    }
    function refreshClips() { clipProc.running = true; }
    function pasteClip(id) {
        Quickshell.execDetached(["bash", "-c", "cliphist decode \"$1\" | wl-copy", "ashen", id]);
    }

    // keyboard layout from sway
    property string layout: ""
    Process {
        id: kbProc
        command: ["swaymsg", "-t", "get_inputs", "-r"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let ins = JSON.parse(this.text).filter(i => i.type === "keyboard" && i.xkb_active_layout_name);
                    let n = ins.length > 0 ? ins[0].xkb_active_layout_name : "";
                    st.layout = /russ/i.test(n) ? "RU" : /eston/i.test(n) ? "ET" : n === "" ? "" : "EN";
                } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: ["swaymsg", "-t", "subscribe", "-m", "[\"input\"]"]
        stdout: SplitParser { onRead: kbProc.running = true }
    }
    Component.onCompleted: { kbProc.running = true; brProc.running = true; }
}
