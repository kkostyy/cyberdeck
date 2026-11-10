import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.I3
import Quickshell.Io
import QtQuick.Shapes

// Top bezel of the AshenOS frame: search, workspaces, the island and status items.
// Hovering an item pours a thin "drop" strip out of the bezel; clicking turns it into a panel.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.barH + 360
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
        clock: [600, 206, 170],
        vol: [250, 132, 160],
        music: [270, 150, 200],
        net: [300, 230, 170],
        bt: [300, 230, 170],
        user: [300, 318, 140],
        wx: [270, 150, 200],
        notif: [300, 210, 260],
        bright: [0, 0, 150],
        sys: [240, 96, 200],
        clip: [300, 196, 0],
        find: [320, 214, 0]
    })
    readonly property var cur: spec[hov || last]
    readonly property bool open: hov !== ""

    // Hover pours a short strip; a click opens the panel, and it stays open
    // until the same item is clicked again (or another item is clicked).
    function enter(id, item) {
        closer.stop();
        if (exp) return;                             // a clicked panel is open — hovering doesn't touch it
        let p = item.mapToItem(barArea, item.width / 2, 0);
        ax = p.x;
        hov = id;
        last = id;
    }
    function tap(id, item) {
        closer.stop();
        if (exp && hov === id) { close(); return; }  // second click closes
        let p = item.mapToItem(barArea, item.width / 2, 0);
        ax = p.x;
        exp = true;
        hov = id;
        last = id;
    }
    function close() { hov = ""; exp = false; }
    function leave() { if (!exp) closer.restart(); }  // only hover strips drain on their own
    // for keybinds and tests: `quickshell ipc call ashen open clock true`
    function itemFor(id) {
        return ({ sys: sysItem, music: musicItem, vol: volItem, bright: volItem, net: netItem, bt: netItem, wx: clockItem, clock: clockItem, user: userItem,
                  find: searchPill, clip: searchPill, notif: island })[id];
    }
    IpcHandler {
        target: "ashen"
        enabled: bar.screen === Quickshell.screens[0]
        function open(id: string, expanded: bool): void {
            let it = bar.itemFor(id);
            if (!it || !it.visible) return;
            if (expanded) { if (!(bar.exp && bar.hov === id)) bar.tap(id, it); }
            else bar.enter(id, it);
        }
        function close(): void { bar.close(); }
        // open the panel, or close it if it's already open
        function toggle(id: string): void {
            if (bar.hov === id && bar.exp) { bar.close(); return; }
            if (id === "clip") bar.st.refreshClips();
            let it = bar.itemFor(id);
            if (!it || !it.visible) return;
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
            if (Config.data.dnd) return;                          // do not disturb: list only
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
    // tiny gauge ring
    component Ring: Item {
        id: ring
        property real value: 0
        implicitWidth: 13; implicitHeight: 13
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.18); strokeWidth: 2; fillColor: "transparent"
                PathAngleArc { centerX: 6.5; centerY: 6.5; radiusX: 5.5; radiusY: 5.5; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: Theme.accent; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 6.5; centerY: 6.5; radiusX: 5.5; radiusY: 5.5; startAngle: -90; sweepAngle: 360 * Math.max(0.02, Math.min(1, ring.value)) }
            }
        }
    }
    // status item in the bezel
    component Item_: Rectangle {
        id: it
        property string dropId: ""          // "" — plain button, emits activated()
        signal activated()
        default property alias content: row.data
        implicitWidth: row.implicitWidth + 9
        implicitHeight: 22
        radius: 7
        color: bar.hov === dropId ? Theme.hover : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        Behavior on color { ColorAnimation { duration: 200 } }
        RowLayout { id: row; anchors.centerIn: parent; spacing: 4 }
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
                id: leftRow
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

                // Claude: opens/hides the Claude app
                Rectangle {
                    visible: Config.data.barClaude
                    implicitWidth: 24; implicitHeight: 21; radius: 7
                    color: cm.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.04)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    scale: cm.pressed ? 0.85 : 1
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                    readonly property string icon: Quickshell.iconPath("claude-desk", true)
                    Image {
                        anchors.centerIn: parent
                        visible: parent.icon !== ""
                        source: parent.icon
                        sourceSize.width: 15; sourceSize.height: 15
                    }
                    Glyph { anchors.centerIn: parent; visible: parent.icon === ""; text: "✳"; color: "#d97757" }
                    MouseArea {
                        id: cm
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Quickshell.execDetached(["bash", "-lc", "claude-console"])
                    }
                }

                // window title + workspaces in one pill (design board «Рабочий стол»)
                Rectangle {
                    implicitWidth: wsRow.implicitWidth + 18
                    implicitHeight: 21
                    radius: 7
                    color: Qt.rgba(1, 1, 1, 0.04)
                    Row {
                        id: wsRow
                        anchors.centerIn: parent
                        spacing: 4
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: bar.st.windowTitle
                            width: Math.min(implicitWidth, 120)
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#c9c9cf"
                            rightPadding: 4
                        }
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
                readonly property bool live: bar.hov === "notif" || bar.st.notifs.length > 0 || bar.st.islandText !== ""
                opacity: live ? 1 : 0
                scale: live ? 1 : 0.6
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 260 } }
                Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                // as wide as the title, but never over the side groups
                readonly property real room: 2 * Math.min(parent.width / 2 - leftRow.x - leftRow.width, rightRow.x - parent.width / 2) - 16
                width: Math.max(60, Math.min(islandRow.implicitWidth + 18, parent.width * 0.3, room))
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
                        text: bar.st.islandText !== "" ? bar.st.islandText : bar.st.notifs.length > 0 ? (bar.st.notifs[0].summary || bar.st.notifs[0].appName) : "Уведомления"
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
                id: rightRow
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Item_ {
                    id: sysItem
                    dropId: "sys"
                    visible: Config.data.barSysmon
                    Ring { value: bar.st.cpu; Layout.rightMargin: -2 }
                    Ring { value: bar.st.ram; Layout.rightMargin: -2 }
                    Ring { value: bar.st.temp / 85 }
                }
                // music: cover, title, little equalizer (prototype)
                Item_ {
                    id: musicItem
                    dropId: "music"
                    visible: bar.st.player !== null
                    Rectangle {
                        implicitWidth: 14; implicitHeight: 14; radius: 7
                        color: Theme.cardSolid
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: bar.st.trackArt
                            sourceSize.width: 28
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                    }
                    Label { text: bar.st.trackTitle; font.weight: Font.DemiBold; Layout.maximumWidth: 80 }
                    Row {
                        spacing: 1.5
                        Layout.alignment: Qt.AlignVCenter
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 2; height: 10; radius: 1
                                anchors.bottom: parent.bottom
                                color: Theme.text
                                transformOrigin: Item.Bottom
                                scale: 0.35
                                SequentialAnimation on scale {
                                    running: bar.st.playing
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 1; duration: 380 + index * 140; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.35; duration: 380 + index * 140; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                }
                // on-screen keyboard; the layout letter replaces the icon when there are two layouts
                Item_ {
                    id: kbItem
                    onActivated: Quickshell.execDetached(["bash", "-c", "if command -v osk >/dev/null; then osk toggle; else ~/.local/bin/osk toggle; fi"])
                    Glyph { text: "󰌌"; font.pixelSize: 13; visible: bar.st.layout === "" || bar.st.layout === "EN" }
                    Label { text: bar.st.layout; font.pixelSize: 10; font.weight: Font.Bold; visible: bar.st.layout !== "" && bar.st.layout !== "EN" }
                }
                Item_ {
                    id: volItem
                    dropId: "vol"
                    Glyph { text: bar.st.muted ? "󰖁" : bar.st.volume > 0.5 ? "󰕾" : "󰖀"; font.pixelSize: 13 }
                    Label { text: Math.round(bar.st.volume * 100) + "%" }
                }
                // network and Bluetooth share one drop, as in the prototype
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
                // avatar → control centre
                Item_ {
                    id: userItem
                    dropId: "user"
                    Rectangle {
                        implicitWidth: 17; implicitHeight: 17; radius: 9
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#7a3a3a" }
                            GradientStop { position: 0.5; color: "#3d5c8a" }
                            GradientStop { position: 1; color: "#5b7fb0" }
                        }
                        border.color: Qt.rgba(1, 1, 1, 0.3)
                        clip: true
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            visible: bar.st.face !== "" && status === Image.Ready
                            source: bar.st.face !== "" ? "file://" + bar.st.face : ""
                            sourceSize.width: 34
                            fillMode: Image.PreserveAspectCrop
                        }
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
