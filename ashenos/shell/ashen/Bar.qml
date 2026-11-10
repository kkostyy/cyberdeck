import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.I3
import Quickshell.Io

// Top bezel of the AshenOS frame: search, workspaces, the island and status items.
// Hovering an item pours a thin "drop" strip out of the bezel; clicking turns it into a panel.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barH + 300
    exclusiveZone: Theme.barH
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ashen-bar"
    WlrLayershell.keyboardFocus: hov === "find" && exp ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: barArea; Region { item: dropBox } }

    // ── drop state ──
    property string hov: ""          // item whose drop is shown ("" = closed)
    property string last: "clock"    // keeps content while the drop drains away
    property bool exp: false         // strip (false) or panel (true)
    property real ax: width / 2      // x of the hovered item's centre

    // [panel width, panel height, strip width]
    readonly property var spec: ({
        clock: [440, 182, 170],
        vol: [250, 132, 160],
        music: [270, 150, 200],
        net: [250, 118, 170],
        bt: [250, 70 + 34 * Math.min(3, Math.max(1, st.btDevices.length)), 170],
        wx: [270, 150, 200],
        notif: [300, 210, 260],
        bright: [0, 0, 150],
        clip: [300, 196, 0],
        find: [320, 214, 0]
    })
    readonly property var cur: spec[hov || last]
    readonly property bool open: hov !== ""

    function enter(id, item) {
        closer.stop();
        let p = item.mapToItem(barArea, item.width / 2, 0);
        if (hov === "find" && exp) return;           // typing — don't steal the drop
        if (hov !== id) exp = false;
        ax = p.x;
        hov = id;
        last = id;
    }
    function tap(id, item) {
        closer.stop();
        let p = item.mapToItem(barArea, item.width / 2, 0);
        ax = p.x;
        exp = !(exp && hov === id);
        hov = id;
        last = id;
    }
    function close() { hov = ""; exp = false; }
    function leave() { if (!(hov === "find" && exp)) closer.restart(); }
    // for keybinds and tests: `quickshell ipc call ashen open clock true`
    function itemFor(id) {
        return ({ music: musicItem, vol: volItem, bright: volItem, net: netItem, bt: btItem, wx: wxItem, clock: clockItem,
                  find: searchPill, clip: searchPill, notif: island })[id];
    }
    IpcHandler {
        target: "ashen"
        enabled: bar.screen === Quickshell.screens[0]
        function open(id: string, expanded: bool): void {
            let it = bar.itemFor(id);
            if (!it || !it.visible) return;
            bar.enter(id, it);
            if (expanded) bar.tap(id, it);
        }
        function close(): void { bar.close(); }
        // open the panel, or close it if it's already open
        function toggle(id: string): void {
            if (bar.hov === id && bar.exp) { bar.close(); return; }
            if (id === "clip") bar.st.refreshClips();
            let it = bar.itemFor(id);
            if (!it || !it.visible) return;
            bar.enter(id, it);
            bar.tap(id, it);
        }
        function volume(cmd: string): void {
            if (cmd === "raise") bar.st.stepVolume(0.05);
            else if (cmd === "lower") bar.st.stepVolume(-0.05);
            else if (cmd === "mute") bar.st.toggleMute();
            bar.osd("vol");             // also at 0 % / 100 %, when nothing changes
        }
        function brightness(cmd: string): void {
            bar.st.stepBrightness(cmd === "lower" ? -0.05 : 0.05);
            bar.osd("bright");
        }
    }

    // short "OSD" strip after volume/brightness keys (not while that panel is open)
    property bool osdReady: false
    Timer { interval: 2500; running: true; onTriggered: bar.osdReady = true }
    function osd(id) {
        if (!osdReady || (exp && hov !== "")) return;
        if (hov !== "" && hov !== id && hov !== "vol" && hov !== "bright") return;
        enter(id, itemFor(id));
        osdHide.restart();
    }
    Timer { id: osdHide; interval: 1600; onTriggered: if ((bar.hov === "vol" || bar.hov === "bright") && !bar.exp && !hoverAll.hovered) bar.close() }
    Connections {
        target: bar.st
        function onVolumeChanged() { bar.osd("vol"); }
        function onMutedChanged() { bar.osd("vol"); }
    }
    // a new notification pours out of the island for a few seconds
    Connections {
        target: bar.st
        function onNotified(n) {
            if (bar.hov !== "" && bar.hov !== "notif") return;   // don't hijack an open drop
            bar.enter("notif", island);
            notifHide.restart();
        }
    }
    Timer { id: notifHide; interval: 5000; onTriggered: if (bar.hov === "notif" && !bar.exp && !hoverAll.hovered) bar.close() }
    Timer { id: closer; interval: bar.exp ? 650 : 320; onTriggered: bar.close() }

    // ── shared widgets ──
    component Glyph: Text {
        font.family: Theme.icons
        font.pixelSize: 14
        color: Theme.text
    }
    component Label: Text {
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.text
        elide: Text.ElideRight
    }
    // status item in the bezel
    component Item_: Rectangle {
        id: it
        property string dropId: ""          // "" — plain button, emits activated()
        signal activated()
        default property alias content: row.data
        implicitWidth: row.implicitWidth + 12
        implicitHeight: 22
        radius: 7
        color: bar.hov === dropId ? Theme.hover : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 200 } }
        RowLayout { id: row; anchors.centerIn: parent; spacing: 5 }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onEntered: if (it.dropId !== "") bar.enter(it.dropId, it)
            onClicked: it.dropId !== "" ? bar.tap(it.dropId, it) : it.activated()
        }
    }

    required property var st

    // whole interactive area: leaving it drains the drop
    Item {
        anchors.fill: parent
        HoverHandler { id: hoverAll; onHoveredChanged: if (!hovered) bar.leave(); else closer.stop() }

        // ── bezel ──
        Rectangle {
            id: barArea
            width: parent.width
            height: Theme.barH
            color: Theme.bezel

            // left: search + workspaces
            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Rectangle {
                    id: searchPill
                    implicitWidth: 150
                    implicitHeight: 21
                    radius: 7
                    color: Qt.rgba(1, 1, 1, bar.hov === "find" ? 0.1 : 0.05)
                    border.color: Theme.line
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        spacing: 6
                        Glyph { text: ""; font.pixelSize: 11; color: Theme.sub }
                        Label { text: "Поиск приложений"; color: Theme.dim; Layout.fillWidth: true }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: bar.tap("find", searchPill)
                    }
                }

                // workspaces: a wide pill for the active one
                Rectangle {
                    implicitWidth: wsRow.implicitWidth + 14
                    implicitHeight: 21
                    radius: 7
                    color: Qt.rgba(1, 1, 1, 0.04)
                    Row {
                        id: wsRow
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: I3.workspaces
                            Rectangle {
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                width: modelData.focused ? 16 : 5
                                height: 5
                                radius: 3
                                color: modelData.focused ? Theme.accent : Theme.dim
                                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    onClicked: I3.dispatch("workspace " + parent.modelData.name)
                                }
                            }
                        }
                    }
                }
            }

            // centre: the island — active window
            Rectangle {
                id: island
                anchors.centerIn: parent
                height: 22
                width: Math.min(islandRow.implicitWidth + 18, parent.width * 0.3)
                radius: 11
                color: "#000000"
                border.color: Qt.rgba(1, 1, 1, 0.08)
                Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                MouseArea { anchors.fill: parent; onClicked: bar.tap("notif", island) }
                RowLayout {
                    id: islandRow
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, island.width - 18)
                    spacing: 7
                    Rectangle {
                        implicitWidth: 13; implicitHeight: 13; radius: 4
                        color: Qt.rgba(1, 1, 1, 0.12)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 4; height: 4; radius: 2
                            color: bar.st.playing ? Theme.accent : Theme.sub
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: bar.st.windowTitle
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: "#c9c9cf"
                    }
                    // unread notifications
                    Rectangle {
                        visible: bar.st.notifs.length > 0
                        implicitWidth: Math.max(14, cnt.implicitWidth + 8)
                        implicitHeight: 14
                        radius: 7
                        color: Theme.accent
                        Text {
                            id: cnt
                            anchors.centerIn: parent
                            text: bar.st.notifs.length
                            font.family: Theme.font
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: Theme.accentInk
                        }
                    }
                }
            }

            // right: status items
            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Item_ {
                    id: musicItem
                    dropId: "music"
                    visible: bar.st.player !== null
                    Glyph { text: bar.st.playing ? "󰎈" : "󰏤"; font.pixelSize: 12 }
                    Label { text: bar.st.trackTitle; Layout.maximumWidth: 90 }
                }
                Item_ {
                    id: volItem
                    dropId: "vol"
                    Glyph { text: bar.st.muted ? "󰖁" : bar.st.volume > 0.5 ? "󰕾" : "󰖀"; font.pixelSize: 13 }
                    Label { text: Math.round(bar.st.volume * 100) + "%" }
                }
                // keyboard: layout (click — next layout) and the on-screen keyboard
                Item_ {
                    id: kbItem
                    visible: bar.st.layout !== ""
                    onActivated: Quickshell.execDetached(["swaymsg", "input type:keyboard xkb_switch_layout next"])
                    Label { text: bar.st.layout; font.pixelSize: 10; font.weight: Font.Bold }
                }
                Item_ {
                    id: oskItem
                    onActivated: Quickshell.execDetached(["bash", "-c", "if command -v osk >/dev/null; then osk toggle; else ~/.local/bin/osk toggle; fi"])
                    Glyph { text: "󰌌"; font.pixelSize: 14 }
                }
                Item_ {
                    id: wxItem
                    dropId: "wx"
                    visible: bar.st.weather !== null
                    Glyph { text: bar.st.weather ? bar.st.wmoGlyph(bar.st.weather.code, bar.st.weather.day) : ""; font.pixelSize: 13 }
                    Label { text: bar.st.weather ? Math.round(bar.st.weather.temp) + "°" : "" }
                }
                Item_ {
                    id: btItem
                    dropId: "bt"
                    visible: bar.st.bt !== null
                    Glyph { text: bar.st.btIcon; font.pixelSize: 13 }
                }
                Item_ {
                    id: netItem
                    dropId: "net"
                    Glyph { text: bar.st.wifiIcon; font.pixelSize: 13 }
                }
                Item_ {
                    id: clockItem
                    dropId: "clock"
                    Label {
                        text: Qt.formatTime(bar.st.clock.date, "HH:mm")
                        font.family: Theme.mono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        // ── the drop ──
        Item {
            id: dropBox
            readonly property real lw: bar.cur[2]
            readonly property real tw: bar.exp ? bar.cur[0] + Theme.panelSide * 2 : lw + Theme.stripSide * 2
            readonly property real th: bar.open ? (bar.exp ? bar.cur[1] : Theme.stripH) : 0
            readonly property real tx: {
                let x = bar.exp && (bar.hov || bar.last) === "clock" ? (bar.width - tw) / 2 : bar.ax - tw / 2;
                return Math.max(0, Math.min(bar.width - tw, x));
            }
            x: tx
            y: Theme.barH - 1
            width: tw
            height: th
            visible: height > 0.5
            Behavior on x { NumberAnimation { duration: bar.exp ? 750 : 700; easing.type: Easing.BezierSpline; easing.bezierCurve: bar.open ? (bar.exp ? Theme.easeSlide : Theme.easeOut) : Theme.easeIn } }
            Behavior on width { NumberAnimation { duration: bar.exp ? 750 : 700; easing.type: Easing.BezierSpline; easing.bezierCurve: bar.open ? (bar.exp ? Theme.easeSlide : Theme.easeOut) : Theme.easeIn } }
            Behavior on height { NumberAnimation { duration: !bar.open ? 480 : bar.exp ? 850 : 620; easing.type: Easing.BezierSpline; easing.bezierCurve: bar.open ? (bar.exp ? Theme.easeSlide : Theme.easeOut) : Theme.easeIn } }

            Liquid {
                anchors.fill: parent
                t: bar.exp ? 1 : 0
                Behavior on t { NumberAnimation { duration: 800; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSlide } }
            }

            // one-line strip
            Item {
                id: strip
                readonly property bool shown: bar.open && !bar.exp
                x: Theme.stripSide
                width: dropBox.lw
                height: Theme.stripH
                clip: true
                opacity: shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: strip.shown ? 400 : 180 } }
                Strips { anchors.fill: parent; which: bar.last; st: bar.st }
            }

            // expanded panel
            Item {
                id: pane
                readonly property bool shown: bar.open && bar.exp
                x: Theme.panelSide
                width: bar.cur[0]
                height: bar.cur[1]
                clip: true
                opacity: shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: pane.shown ? 450 : 160 } }
                transform: Translate {
                    y: pane.shown ? 0 : -20
                    Behavior on y { NumberAnimation { duration: 900; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSlide } }
                }
                Panels {
                    anchors.fill: parent
                    which: bar.last
                    st: bar.st
                    active: pane.shown
                    onCloseRequested: bar.close()
                }
            }
        }
    }
}
