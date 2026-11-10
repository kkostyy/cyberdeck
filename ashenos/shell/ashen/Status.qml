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

    // Wi-Fi via nmcli: "yes:SSID:SIGNAL"
    property string ssid: ""
    property int signal: 0
    property bool wifiOn: true
    readonly property string wifiIcon: !wifiOn ? "󰤮" : ssid === "" ? "󰤯"
        : signal > 75 ? "󰤨" : signal > 50 ? "󰤥" : signal > 25 ? "󰤢" : "󰤟"
    Process {
        id: wifiProc
        command: ["bash", "-c", "export LC_ALL=C; nmcli -t -f WIFI radio; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes:' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                st.wifiOn = lines[0] === "enabled";
                let a = (lines[1] || "").split(":");
                st.ssid = a.length >= 3 ? a.slice(1, a.length - 1).join(":") : "";
                st.signal = a.length >= 3 ? parseInt(a[a.length - 1]) || 0 : 0;
            }
        }
    }
    Timer { interval: 8000; running: true; repeat: true; triggeredOnStart: true; onTriggered: wifiProc.running = true }
    function setWifi(on) {
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        st.wifiOn = on;
        wifiRefresh.restart();
    }
    Timer { id: wifiRefresh; interval: 2500; onTriggered: wifiProc.running = true }

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
