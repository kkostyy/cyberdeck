import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Bottom dock: pinned apps (~/.config/ashen/dock.json), then running unpinned apps,
// then Downloads and Trash. A dot marks running apps; tiles spring back after a tap.
PanelWindow {
    id: dock
    required property var modelData
    screen: modelData

    anchors { bottom: true }
    implicitWidth: bg.width + 40
    implicitHeight: tileSize + 16 + 28          // dock + room for the tooltip above it
    exclusiveZone: tileSize + 16 + 6
    margins.bottom: Theme.side + 4
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ashen-dock"
    mask: Region { item: bg }

    readonly property int tileSize: 36
    property var pinned: ["claude-desk", "chromium", "org.gnome.Nautilus", "kitty", "org.kde.konsole", "pavucontrol"]
    property string tip: ""
    property real tipX: 0

    FileView {
        path: Quickshell.env("HOME") + "/.config/ashen/dock.json"
        onLoaded: { try { let a = JSON.parse(text()); if (Array.isArray(a)) dock.pinned = a; } catch (e) {} }
    }

    function entryFor(id) { return DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id); }
    function windowsOf(entry) {
        if (!entry) return [];
        let id = entry.id.toLowerCase(), wm = (entry.startupClass || "").toLowerCase();
        return ToplevelManager.toplevels.values.filter(t => {
            let a = (t.appId || "").toLowerCase();
            return a !== "" && (a === id || a === wm || id.endsWith("." + a) || a.endsWith("." + id));
        });
    }
    // pinned entries, then apps that run but aren't pinned
    readonly property var apps: {
        let out = [], seen = {};
        for (let i = 0; i < pinned.length; i++) {
            let e = entryFor(pinned[i]);
            if (e && !seen[e.id]) { seen[e.id] = true; out.push(e); }
        }
        let ts = ToplevelManager.toplevels.values;
        for (let i = 0; i < ts.length; i++) {
            let e = ts[i].appId ? DesktopEntries.heuristicLookup(ts[i].appId) : null;
            if (e && !seen[e.id] && !e.noDisplay) { seen[e.id] = true; out.push(e); }
        }
        return out;
    }

    // one tile; `glyph` draws a symbol instead of an app icon
    component Tile: Item {
        id: tile
        property string name: ""
        property string icon: ""
        property string glyph: ""
        property bool running: false
        signal activated()
        implicitWidth: dock.tileSize
        implicitHeight: dock.tileSize + 6

        Rectangle {
            id: face
            width: dock.tileSize; height: dock.tileSize
            radius: 10
            gradient: Gradient {
                GradientStop { position: 0; color: "#34343a" }
                GradientStop { position: 1; color: "#1c1c1f" }
            }
            border.color: Qt.rgba(1, 1, 1, 0.1)
            scale: tm.pressed ? 0.8 : tm.containsMouse ? 1.08 : 1
            // springy release, quick press (prototype: cubic-bezier(.3,2.2,.45,1))
            Behavior on scale {
                NumberAnimation {
                    duration: tm.pressed ? 90 : 500
                    easing.type: tm.pressed ? Easing.OutQuad : Easing.BezierSpline
                    easing.bezierCurve: [0.3, 2.2, 0.45, 1, 1, 1]
                }
            }
            // app icon; apps without one get the first letter of their name
            readonly property string iconSrc: tile.icon !== "" ? Quickshell.iconPath(tile.icon, true) : ""
            Image {
                anchors.centerIn: parent
                visible: tile.glyph === "" && face.iconSrc !== ""
                source: face.iconSrc
                sourceSize.width: 26; sourceSize.height: 26
                width: 26; height: 26
                smooth: true
            }
            Text {
                anchors.centerIn: parent
                visible: tile.glyph === "" && face.iconSrc === ""
                text: tile.name.charAt(0).toUpperCase()
                font.family: Theme.font
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Theme.text
            }
            Text {
                anchors.centerIn: parent
                visible: tile.glyph !== ""
                text: tile.glyph
                font.family: Theme.icons
                font.pixelSize: 17
                color: Theme.text
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 4; height: 4; radius: 2
            color: Theme.sub
            opacity: tile.running ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        MouseArea {
            id: tm
            anchors.fill: face
            hoverEnabled: true
            onContainsMouseChanged: {
                if (containsMouse) { dock.tip = tile.name; dock.tipX = tile.mapToItem(bg, tile.width / 2, 0).x + bg.x; }
                else if (dock.tip === tile.name) dock.tip = "";
            }
            onClicked: tile.activated()
        }
    }

    // tooltip above the dock
    Rectangle {
        visible: opacity > 0
        opacity: dock.tip !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        x: Math.max(0, Math.min(dock.width - width, dock.tipX - width / 2))
        y: 0
        width: tipText.implicitWidth + 16
        height: 20
        radius: 7
        color: Theme.cardSolid
        border.color: Theme.line
        Text {
            id: tipText
            anchors.centerIn: parent
            text: dock.tip
            font.family: Theme.font
            font.pixelSize: 10
            color: Theme.text
        }
    }

    Rectangle {
        id: bg
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: row.implicitWidth + 20
        height: dock.tileSize + 16
        radius: 16
        color: Theme.card
        border.color: Qt.rgba(1, 1, 1, 0.11)
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 2
            spacing: 6

            Repeater {
                model: dock.apps
                Tile {
                    required property var modelData
                    readonly property var wins: dock.windowsOf(modelData)
                    name: modelData.name
                    icon: modelData.icon
                    running: wins.length > 0
                    onActivated: {
                        if (wins.length > 0) {
                            // cycle through this app's windows
                            let act = ToplevelManager.activeToplevel;
                            let i = wins.indexOf(act);
                            wins[(i + 1) % wins.length].activate();
                        } else modelData.execute();
                    }
                }
            }
            Rectangle { implicitWidth: 1; implicitHeight: dock.tileSize - 10; color: Qt.rgba(1, 1, 1, 0.12); Layout.alignment: Qt.AlignTop; Layout.topMargin: 5 }
            Tile {
                name: "Загрузки"
                glyph: "󰇚"
                onActivated: Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/Downloads"])
            }
            Tile {
                name: "Корзина"
                glyph: "󰩹"
                onActivated: Quickshell.execDetached(["nautilus", "trash:///"])
            }
        }
    }
}
