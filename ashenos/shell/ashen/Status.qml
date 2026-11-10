import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

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
    Component.onCompleted: kbProc.running = true
}
