import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// «Проводник» — file manager from the AshenOS design package (Проводник для AshenOS.html):
// places and devices on the left, breadcrumbs + search on top, folder tiles with
// per-folder «Оформление» (material, tint), files with type badges, status bar.
//   quickshell ipc call ashen-files open <path>
Scope {
    id: root
    property bool shown: false
    property string startPath: Quickshell.env("HOME")

    IpcHandler {
        target: "ashen-files"
        function open(path: string): void {
            root.startPath = path !== "" ? path.replace(/^file:\/\//, "") : Quickshell.env("HOME");
            if (root.shown && win.item) win.item.go(root.startPath);
            root.shown = true;
        }
    }

    // per-folder looks + window background, ~/.config/ashen/explorer.json
    FileView {
        id: looksFile
        path: Quickshell.env("HOME") + "/.config/ashen/explorer.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: writeAdapter()
        JsonAdapter {
            id: looks
            property var folders: ({})       // path → {material, tint}
            property string background: "dark"
            property string view: "icons"    // icons | list
        }
    }

    LazyLoader {
        id: win
        active: root.shown
        FloatingWindow {
            id: w
            title: "Проводник"
            implicitWidth: 680
            implicitHeight: 400
            color: Theme.bezel
            onClosed: root.shown = false

            readonly property string home: Quickshell.env("HOME")
            property string path: root.startPath
            property var back: []
            property var fwd: []
            property string selected: ""          // file path
            property string query: ""
            property bool showLooks: false
            property string creating: ""          // "folder" while naming a new folder
            property string renaming: ""
            property string toast: ""

            function go(p, keepHistory) {
                p = p.replace(/\/+$/, "") || "/";
                if (p === path) return;
                if (!keepHistory) { back = back.concat([path]); fwd = []; }
                path = p;
                selected = "";
                query = "";
                search.text = "";
                showLooks = false;
            }
            function goBack() { if (back.length === 0) return; fwd = [path].concat(fwd); let p = back[back.length - 1]; back = back.slice(0, -1); go(p, true); }
            function goFwd() { if (fwd.length === 0) return; back = back.concat([path]); let p = fwd[0]; fwd = fwd.slice(1); go(p, true); }
            function up() { if (path !== "/") go(path.substring(0, path.lastIndexOf("/")) || "/"); }
            function pretty(p) { return p.startsWith(home) ? "~" + p.substring(home.length) : p; }
            function base(p) { return p === "/" ? "/" : p.substring(p.lastIndexOf("/") + 1); }
            function human(b) {
                if (b < 1024) return b + " Б";
                let u = ["КБ", "МБ", "ГБ", "ТБ"], i = -1;
                do { b /= 1024; i++; } while (b >= 1024 && i < u.length - 1);
                return (b < 10 ? b.toFixed(1) : Math.round(b)).toString().replace(".", ",") + " " + u[i];
            }
            function ext(n) { let i = n.lastIndexOf("."); return i > 0 ? n.substring(i + 1).toUpperCase().substring(0, 4) : ""; }
            function isImage(n) { return /\.(png|jpe?g|webp|gif|bmp|svg)$/i.test(n); }
            function say(t) { toast = t; toastT.restart(); }
            Timer { id: toastT; interval: 2500; onTriggered: w.toast = "" }
            function lookOf(p) { return looks.folders[p] || { material: "glass", tint: "graphite" }; }
            function setLook(p, k, v) {
                let all = Object.assign({}, looks.folders);
                let l = Object.assign({}, lookOf(p));
                l[k] = v;
                all[p] = l;
                looks.folders = all;
            }
            function openFile(p) { Quickshell.execDetached(["xdg-open", p]); }
            function run(cmd, done) { act.command = cmd; act.done = done || ""; act.running = true; }

            Process {
                id: act
                property string done: ""
                stderr: StdioCollector { id: actErr }
                onExited: code => {
                    if (code !== 0) w.say("Не вышло: " + actErr.text.trim().split("\n")[0]);
                    else if (act.done !== "") w.say(act.done);
                    dirs.refresh();
                }
            }

            // sidebar places
            readonly property var places: [
                { n: "Домашняя папка", g: "󰋜", p: home },
                { n: "Рабочий стол", g: "󰇄", p: home + "/Desktop" },
                { n: "Документы", g: "󰈙", p: home + "/Documents" },
                { n: "Загрузки", g: "󰇚", p: home + "/Downloads" },
                { n: "Музыка", g: "󰝚", p: home + "/Music" },
                { n: "Изображения", g: "󰋩", p: home + "/Pictures" },
                { n: "Проекты", g: "󰉋", p: home + "/claude" },
                { n: "Корзина", g: "󰩹", p: home + "/.local/share/Trash/files" }
            ]

            // devices from lsblk: mounted filesystems + removable ones
            property var devices: []
            Process {
                id: devProc
                running: true
                command: ["lsblk", "-J", "-b", "-o", "NAME,RM,HOTPLUG,MOUNTPOINT,LABEL,FSTYPE,FSSIZE,FSUSED,FSAVAIL,PATH"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let out = [];
                        function walk(list) {
                            for (let d of list || []) {
                                if (d.mountpoint && d.fstype && d.fstype !== "swap" && d.fssize)
                                    out.push({ path: d.path, mount: d.mountpoint, label: d.label || "", fs: d.fstype,
                                               size: Number(d.fssize), used: Number(d.fsused), avail: Number(d.fsavail),
                                               usb: d.rm === true || d.hotplug === true || d.rm === "1" });
                                walk(d.children);
                            }
                        }
                        try { walk(JSON.parse(this.text).blockdevices); } catch (e) {}
                        w.devices = out;
                    }
                }
            }
            Timer { interval: 10000; running: true; repeat: true; onTriggered: devProc.running = true }
            readonly property var here: {
                let best = null;
                for (let d of devices) if ((path + "/").startsWith(d.mount === "/" ? "/" : d.mount + "/") && (!best || d.mount.length > best.mount.length)) best = d;
                return best;
            }

            // folder contents: folders and files as two models
            FolderListModel {
                id: dirs
                folder: "file://" + w.path
                showFiles: false
                showDotAndDotDot: false
                showHidden: false
                sortCaseSensitive: false
                function refresh() { let f = folder; folder = ""; folder = f; }
            }
            FolderListModel {
                id: files
                folder: "file://" + w.path
                showDirs: false
                showHidden: false
                sortCaseSensitive: false
                sortField: FolderListModel.Name
            }
            readonly property var dirList: {
                let ready = dirs.status === FolderListModel.Ready && dirs.folder;   // recompute on every load
                let q = query.toLowerCase(), out = [];
                for (let i = 0; i < dirs.count; i++) {
                    let n = dirs.get(i, "fileName");
                    if (q === "" || n.toLowerCase().indexOf(q) >= 0) out.push({ name: n, path: dirs.get(i, "filePath") });
                }
                return out;
            }
            readonly property var fileList: {
                let ready = files.status === FolderListModel.Ready && files.folder;
                let q = query.toLowerCase(), out = [];
                for (let i = 0; i < files.count; i++) {
                    let n = files.get(i, "fileName");
                    if (q === "" || n.toLowerCase().indexOf(q) >= 0)
                        out.push({ name: n, path: files.get(i, "filePath"), size: files.get(i, "fileSize"), mod: files.get(i, "fileModified") });
                }
                return out;
            }
            readonly property real totalSize: fileList.reduce((a, f) => a + f.size, 0)

            // window backgrounds from the «Фон окна» row
            readonly property var backgrounds: ({
                dark: ["#1a1a1d", "#09090a"], black: ["#111113", "#050506"],
                ember: ["#3a0d0d", "#0a0606"], silver: ["#9a9aa0", "#2a2a2e"]
            })

            // ── pieces ──
            component T: Text {
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.text
                elide: Text.ElideRight
            }
            component G: Text {
                font.family: Theme.icons
                font.pixelSize: 14
                color: Theme.text
            }
            component IconBtn: Rectangle {
                id: ib
                property string glyph: ""
                property bool on: false
                property bool enabledBtn: true
                signal clicked()
                implicitWidth: 26; implicitHeight: 26; radius: 8
                color: on ? Qt.rgba(1, 1, 1, 0.16) : im.containsMouse && enabledBtn ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                opacity: enabledBtn ? 1 : 0.35
                G { anchors.centerIn: parent; text: ib.glyph; font.pixelSize: 13 }
                MouseArea { id: im; anchors.fill: parent; hoverEnabled: true; onClicked: if (ib.enabledBtn) ib.clicked() }
            }
            component Chip: Rectangle {
                id: ch
                property string label: ""
                property string glyph: ""
                property bool primary: false
                signal clicked()
                implicitWidth: chRow.implicitWidth + 16; implicitHeight: 24; radius: 8
                color: primary ? (cm.containsMouse ? "#ffffff" : Theme.accent) : cm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                border.color: primary ? "transparent" : Qt.rgba(1, 1, 1, 0.1)
                scale: cm.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                Row {
                    id: chRow
                    anchors.centerIn: parent
                    spacing: 5
                    G { visible: ch.glyph !== ""; text: ch.glyph; font.pixelSize: 11; color: ch.primary ? Theme.accentInk : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                    T { text: ch.label; font.weight: Font.DemiBold; color: ch.primary ? Theme.accentInk : Theme.text; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: ch.clicked() }
            }
            // the design's folder: dark back, papers, frosted front in a material and tint
            component FolderArt: Item {
                id: fa
                property string material: "glass"
                property string tint: "graphite"
                readonly property color tintColor: ({ graphite: "#3a3a40", gray: "#8b8b93", white: "#f2f2f4", blue: "#6f8fc0", green: "#6fb08a", sand: "#d9c2a0" })[tint] || "#3a3a40"
                // back panel
                Rectangle {
                    x: fa.width * 0.06; y: fa.height * 0.12
                    width: fa.width * 0.88; height: fa.height * 0.7
                    radius: fa.width * 0.06
                    color: fa.material === "lava" ? "#1a0b0b" : "#1c1c1f"
                }
                // papers
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        x: fa.width * (0.16 + index * 0.2); y: fa.height * (0.05 + index * 0.05)
                        width: fa.width * 0.34; height: fa.height * 0.55
                        radius: 3
                        rotation: index === 0 ? -4 : 0
                        color: index === 0 ? "#ffffff" : "#ececef"
                        visible: fa.material !== "lava" || index === 0
                    }
                }
                // front
                Rectangle {
                    x: 0; y: fa.height * 0.38
                    width: fa.width; height: fa.height * 0.62
                    radius: fa.width * 0.07
                    opacity: fa.material === "glass" ? 0.92 : 1
                    gradient: Gradient {
                        orientation: fa.material === "silk" ? Gradient.Horizontal : Gradient.Vertical
                        GradientStop { position: 0; color: fa.material === "silk" ? "#b8433f" : fa.material === "archive" ? "#ffffff" : fa.material === "lava" ? "#5a1410" : Qt.lighter(fa.tintColor, 1.9) }
                        GradientStop { position: 0.5; color: fa.material === "silk" ? "#e8e8f0" : fa.material === "archive" ? "#e7e7ea" : fa.material === "lava" ? "#2a0e0c" : Qt.lighter(fa.tintColor, 1.3) }
                        GradientStop { position: 1; color: fa.material === "silk" ? "#4f6fa8" : fa.material === "archive" ? "#cfcfd4" : fa.material === "lava" ? "#100606" : fa.tintColor }
                    }
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    // soft highlight on glass
                    Rectangle {
                        visible: fa.material === "glass"
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.35) }
                            GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0) }
                        }
                    }
                    // tint wash over every material
                    Rectangle { anchors.fill: parent; radius: parent.radius; color: fa.tintColor; opacity: fa.material === "glass" ? 0 : fa.tint === "graphite" ? 0 : 0.28 }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: (w.backgrounds[looks.background] || w.backgrounds.dark)[0] }
                    GradientStop { position: 1; color: (w.backgrounds[looks.background] || w.backgrounds.dark)[1] }
                }
            }

            Shortcut { sequence: "Alt+Left"; onActivated: w.goBack() }
            Shortcut { sequence: "Alt+Right"; onActivated: w.goFwd() }
            Shortcut { sequence: "Alt+Up"; onActivated: w.up() }
            Shortcut { sequence: "Backspace"; enabled: !search.activeFocus && w.creating === "" && w.renaming === ""; onActivated: w.up() }
            Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
            Shortcut { sequence: "F4"; onActivated: Quickshell.execDetached(["kitty", "--directory", w.path]) }
            Shortcut { sequence: "F2"; enabled: w.selected !== ""; onActivated: { w.renaming = w.selected; } }
            Shortcut { sequence: "Delete"; enabled: w.selected !== "" && !search.activeFocus; onActivated: { w.run(["gio", "trash", w.selected], "В корзине: " + w.base(w.selected)); w.selected = ""; } }
            Shortcut { sequence: "Ctrl+H"; onActivated: { dirs.showHidden = !dirs.showHidden; files.showHidden = dirs.showHidden; } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                // ── title row: app, navigation, path, search, views, looks ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    FolderArt { implicitWidth: 24; implicitHeight: 20 }
                    ColumnLayout {
                        spacing: -2
                        visible: w.width > 560
                        T { text: "Проводник"; font.pixelSize: 11; font.weight: Font.Bold }
                        T { text: w.pretty(w.path); font.pixelSize: 8; color: Theme.dim; Layout.maximumWidth: 80 }
                    }
                    Rectangle {
                        implicitWidth: navRow.implicitWidth + 6; implicitHeight: 30; radius: 10
                        color: Qt.rgba(1, 1, 1, 0.05); border.color: Theme.line
                        Row {
                            id: navRow
                            anchors.centerIn: parent
                            IconBtn { glyph: "󰅁"; enabledBtn: w.back.length > 0; onClicked: w.goBack() }
                            IconBtn { glyph: "󰅂"; enabledBtn: w.fwd.length > 0; onClicked: w.goFwd() }
                            IconBtn { glyph: "󰁝"; enabledBtn: w.path !== "/"; onClicked: w.up() }
                        }
                    }
                    // breadcrumbs
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30; radius: 10
                        color: Qt.rgba(1, 1, 1, 0.05); border.color: Theme.line
                        clip: true
                        Flickable {
                            id: crumbsF
                            anchors.fill: parent
                            anchors.leftMargin: 4; anchors.rightMargin: 4
                            contentWidth: crumbs.implicitWidth
                            flickableDirection: Flickable.HorizontalFlick
                            onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
                            Row {
                                id: crumbs
                                height: parent.height
                                spacing: 0
                                Repeater {
                                    model: {
                                        let out = [{ n: "/", p: "/" }], acc = "";
                                        for (let part of w.path.split("/").filter(x => x !== "")) {
                                            acc += "/" + part;
                                            out.push({ n: acc === w.home ? "󰋜 " + part : part, p: acc });
                                        }
                                        return out;
                                    }
                                    Row {
                                        id: cr
                                        required property var modelData
                                        required property int index
                                        anchors.verticalCenter: parent.verticalCenter
                                        G { visible: cr.index > 1; text: "󰅂"; font.pixelSize: 10; color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle {
                                            readonly property bool last: cr.modelData.p === w.path
                                            width: crt.implicitWidth + 12; height: 22; radius: 7
                                            color: last ? Qt.rgba(1, 1, 1, 0.12) : crm.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                                            T { id: crt; anchors.centerIn: parent; text: cr.modelData.n; font.family: cr.modelData.n.charAt(0) === "󰋜" ? Theme.icons : Theme.font; font.weight: parent.last ? Font.Bold : Font.Normal; color: parent.last ? Theme.text : Theme.sub }
                                            MouseArea { id: crm; anchors.fill: parent; hoverEnabled: true; onClicked: w.go(cr.modelData.p) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // search
                    Rectangle {
                        implicitWidth: search.activeFocus || w.query !== "" ? 150 : 110
                        Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        implicitHeight: 30; radius: 10
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: search.activeFocus ? Qt.rgba(1, 1, 1, 0.3) : Theme.line
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 6
                            spacing: 5
                            G { text: ""; font.pixelSize: 10; color: Theme.sub }
                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.text
                                clip: true
                                onTextChanged: w.query = text
                                Keys.onEscapePressed: { text = ""; focus = false; }
                                T { visible: search.text === "" && !search.activeFocus; text: "Поиск в «" + w.base(w.path) + "»"; color: Theme.dim; font.pixelSize: 10; width: search.width }
                            }
                        }
                    }
                    Rectangle {
                        implicitWidth: viewRow.implicitWidth + 6; implicitHeight: 30; radius: 10
                        color: Qt.rgba(1, 1, 1, 0.05); border.color: Theme.line
                        Row {
                            id: viewRow
                            anchors.centerIn: parent
                            IconBtn { glyph: "󰕰"; on: looks.view === "icons"; onClicked: looks.view = "icons" }
                            IconBtn { glyph: "󰕲"; on: looks.view === "list"; onClicked: looks.view = "list" }
                        }
                    }
                    IconBtn { glyph: "󰏘"; on: w.showLooks; implicitWidth: 30; implicitHeight: 30; onClicked: w.showLooks = !w.showLooks }
                }

                // ── body ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    // sidebar
                    Rectangle {
                        Layout.preferredWidth: 150
                        Layout.fillHeight: true
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.035)
                        border.color: Theme.line
                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 6
                            contentHeight: side.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ColumnLayout {
                                id: side
                                width: parent.width
                                spacing: 1
                                T { text: "МЕСТА"; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 0.8; color: Theme.dim; Layout.leftMargin: 6; Layout.topMargin: 2; Layout.bottomMargin: 2 }
                                Repeater {
                                    model: w.places
                                    Rectangle {
                                        id: pl
                                        required property var modelData
                                        readonly property bool on: w.path === modelData.p
                                        Layout.fillWidth: true
                                        implicitHeight: 24; radius: 7
                                        color: on ? Qt.rgba(1, 1, 1, 0.12) : plm.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 7
                                            spacing: 7
                                            G { text: pl.modelData.g; font.pixelSize: 12; color: pl.on ? Theme.text : Theme.sub }
                                            T { Layout.fillWidth: true; text: pl.modelData.n; font.weight: pl.on ? Font.DemiBold : Font.Normal }
                                        }
                                        MouseArea { id: plm; anchors.fill: parent; hoverEnabled: true; onClicked: w.go(pl.modelData.p) }
                                    }
                                }
                                Rectangle { Layout.fillWidth: true; Layout.topMargin: 5; Layout.bottomMargin: 3; implicitHeight: 1; color: Theme.line }
                                T { text: "УСТРОЙСТВА"; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 0.8; color: Theme.dim; Layout.leftMargin: 6; Layout.bottomMargin: 2 }
                                Repeater {
                                    model: w.devices
                                    Rectangle {
                                        id: dv
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 40; radius: 7
                                        color: dvm.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                                        ColumnLayout {
                                            anchors.fill: parent; anchors.margins: 5; anchors.leftMargin: 7
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                G { text: dv.modelData.usb ? "󰕓" : "󰋊"; font.pixelSize: 11; color: Theme.sub }
                                                T { Layout.fillWidth: true; text: (dv.modelData.usb ? (dv.modelData.label || "USB-накопитель") : dv.modelData.mount === "/" ? "Корень /" : (dv.modelData.label || w.base(dv.modelData.mount)) + " " + dv.modelData.mount); font.weight: Font.DemiBold }
                                                T { text: dv.modelData.fs; font.pixelSize: 8; color: Theme.dim }
                                                G {
                                                    visible: dv.modelData.usb
                                                    text: "󰕔"; font.pixelSize: 11; color: Theme.sub
                                                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: w.run(["udisksctl", "unmount", "-b", dv.modelData.path], "Можно доставать") }
                                                }
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: 3; radius: 2
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle { width: parent.width * dv.modelData.used / Math.max(1, dv.modelData.size); height: parent.height; radius: 2; color: Theme.accent }
                                            }
                                            T { text: w.human(dv.modelData.used) + " из " + w.human(dv.modelData.size); font.pixelSize: 8; color: Theme.dim }
                                        }
                                        MouseArea { id: dvm; anchors.fill: parent; hoverEnabled: true; z: -1; onClicked: w.go(dv.modelData.mount) }
                                    }
                                }
                            }
                        }
                    }

                    // content
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.03)
                        border.color: Theme.line
                        clip: true

                        Flickable {
                            id: content
                            anchors.fill: parent
                            anchors.margins: 10
                            contentHeight: body.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {
                                policy: content.contentHeight > content.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.25) }
                            }
                            MouseArea { width: content.width; height: Math.max(content.height, body.implicitHeight); onClicked: w.selected = ""; z: -1 }

                            ColumnLayout {
                                id: body
                                width: content.width
                                spacing: 8

                                // header
                                RowLayout {
                                    Layout.fillWidth: true
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        T { Layout.fillWidth: true; text: w.base(w.path) === "" ? "/" : (w.path === w.home ? "Домашняя папка" : w.base(w.path)); font.pixelSize: 18; font.weight: Font.Bold }
                                        T {
                                            text: (w.dirList.length > 0 ? w.dirList.length + " " + (w.dirList.length === 1 ? "папка" : w.dirList.length < 5 ? "папки" : "папок") + ", " : "")
                                                + w.fileList.length + " " + (w.fileList.length === 1 ? "файл" : w.fileList.length < 5 && w.fileList.length > 1 ? "файла" : "файлов")
                                                + " · " + w.human(w.totalSize)
                                            color: Theme.dim; font.pixelSize: 10
                                        }
                                    }
                                    Chip { glyph: "󰒺"; label: "По имени"; onClicked: { let d = !dirs.sortReversed; dirs.sortReversed = d; files.sortReversed = d; } }
                                    Chip { glyph: "󰐕"; label: "Создать"; primary: true; onClicked: { w.creating = "folder"; newName.text = "Новая папка"; newName.selectAll(); newName.forceActiveFocus(); } }
                                }

                                // new folder name
                                Rectangle {
                                    visible: w.creating !== ""
                                    Layout.fillWidth: true
                                    implicitHeight: 30; radius: 9
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    border.color: Qt.rgba(1, 1, 1, 0.3)
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 4
                                        G { text: "󰉋"; font.pixelSize: 12; color: Theme.sub }
                                        TextInput {
                                            id: newName
                                            Layout.fillWidth: true
                                            font.family: Theme.font; font.pixelSize: 11; color: Theme.text
                                            onAccepted: { if (text.trim() !== "" && text.indexOf("/") < 0) w.run(["mkdir", "--", w.path + "/" + text.trim()], "Создана папка «" + text.trim() + "»"); w.creating = ""; }
                                            Keys.onEscapePressed: w.creating = ""
                                        }
                                        Chip { label: "Готово"; primary: true; onClicked: newName.accepted() }
                                    }
                                }

                                // folders
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: looks.view === "icons"
                                    Repeater {
                                        model: w.dirList
                                        Rectangle {
                                            id: ft
                                            required property var modelData
                                            readonly property bool sel: w.selected === modelData.path
                                            readonly property var look: w.lookOf(modelData.path)
                                            width: Math.floor((body.width - 24) / 4); height: width * 0.78 + 34
                                            radius: 12
                                            color: sel ? Qt.rgba(1, 1, 1, 0.1) : ftm.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.035)
                                            border.color: sel ? Qt.rgba(1, 1, 1, 0.6) : Theme.line
                                            border.width: sel ? 1.5 : 1
                                            scale: ftm.pressed ? 0.96 : 1
                                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                                            FolderListModel { id: inner; folder: "file://" + ft.modelData.path; showDotAndDotDot: false }
                                            FolderArt {
                                                x: parent.width * 0.12; y: 8
                                                width: parent.width * 0.76; height: width * 0.66
                                                material: ft.look.material
                                                tint: ft.look.tint
                                            }
                                            Rectangle {
                                                visible: ft.sel
                                                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                                                width: 15; height: 15; radius: 8; color: Theme.accent
                                                G { anchors.centerIn: parent; text: "󰄬"; font.pixelSize: 10; color: Theme.accentInk }
                                            }
                                            Column {
                                                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                                width: parent.width
                                                T { width: parent.width - 8; x: 4; horizontalAlignment: Text.AlignHCenter; text: ft.modelData.name; font.weight: Font.Bold }
                                                T { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: inner.count + " " + (inner.count % 10 === 1 && inner.count % 100 !== 11 ? "элемент" : [2, 3, 4].indexOf(inner.count % 10) >= 0 && [12, 13, 14].indexOf(inner.count % 100) < 0 ? "элемента" : "элементов"); font.pixelSize: 9; color: Theme.dim }
                                            }
                                            MouseArea {
                                                id: ftm
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                onClicked: e => { w.selected = ft.modelData.path; if (e.button === Qt.RightButton) w.showLooks = true; }
                                                onDoubleClicked: w.go(ft.modelData.path)
                                            }
                                        }
                                    }
                                }

                                T { visible: w.fileList.length > 0 && looks.view === "icons"; text: "Файлы"; font.weight: Font.Bold; color: Theme.sub; Layout.topMargin: 2 }

                                // files as tiles
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: looks.view === "icons"
                                    Repeater {
                                        model: w.fileList
                                        Rectangle {
                                            id: fi
                                            required property var modelData
                                            readonly property bool sel: w.selected === modelData.path
                                            width: Math.floor((body.width - 30) / 6); height: width + 22
                                            radius: 10
                                            color: sel ? Qt.rgba(1, 1, 1, 0.12) : fim.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                                            // dark card with a type badge (or the picture itself)
                                            Rectangle {
                                                x: parent.width * 0.14; y: 4
                                                width: parent.width * 0.72; height: width * 0.86
                                                radius: 7
                                                color: "#2a2a2e"
                                                border.color: Qt.rgba(1, 1, 1, 0.1)
                                                clip: true
                                                Rectangle { x: parent.width * 0.18; y: -3; width: parent.width * 0.6; height: parent.height * 0.55; radius: 3; color: "#ececef"; visible: !w.isImage(fi.modelData.name) }
                                                Image {
                                                    anchors.fill: parent
                                                    visible: w.isImage(fi.modelData.name)
                                                    source: visible ? "file://" + fi.modelData.path : ""
                                                    sourceSize.width: 96
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                }
                                                Rectangle {
                                                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                                    height: parent.height * 0.42
                                                    gradient: Gradient {
                                                        GradientStop { position: 0; color: Qt.rgba(0.25, 0.25, 0.28, 0.85) }
                                                        GradientStop { position: 1; color: Qt.rgba(0.12, 0.12, 0.14, 0.95) }
                                                    }
                                                    T { anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: w.ext(fi.modelData.name); font.family: Theme.mono; font.pixelSize: 7; font.weight: Font.Bold; color: "#d4d4da" }
                                                }
                                            }
                                            Column {
                                                anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                                                width: parent.width
                                                T { width: parent.width - 4; x: 2; horizontalAlignment: Text.AlignHCenter; text: fi.modelData.name; font.pixelSize: 9; font.weight: Font.DemiBold }
                                                T { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: w.human(fi.modelData.size); font.pixelSize: 8; color: Theme.dim }
                                            }
                                            MouseArea {
                                                id: fim
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: w.selected = fi.modelData.path
                                                onDoubleClicked: w.openFile(fi.modelData.path)
                                            }
                                        }
                                    }
                                }

                                // details list
                                Repeater {
                                    model: looks.view === "list" ? w.dirList.map(d => ({ name: d.name, path: d.path, dir: true })).concat(w.fileList.map(f => ({ name: f.name, path: f.path, size: f.size, mod: f.mod, dir: false }))) : []
                                    Rectangle {
                                        id: li
                                        required property var modelData
                                        readonly property bool sel: w.selected === modelData.path
                                        Layout.fillWidth: true
                                        implicitHeight: 24; radius: 7
                                        color: sel ? Qt.rgba(1, 1, 1, 0.12) : lim.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                            spacing: 8
                                            G { text: li.modelData.dir ? "󰉋" : w.isImage(li.modelData.name) ? "󰋩" : "󰈔"; font.pixelSize: 12; color: li.modelData.dir ? Theme.text : Theme.sub }
                                            T { Layout.fillWidth: true; text: li.modelData.name; font.weight: li.modelData.dir ? Font.DemiBold : Font.Normal }
                                            T { text: li.modelData.dir ? "папка" : w.ext(li.modelData.name); font.family: Theme.mono; font.pixelSize: 8; color: Theme.dim; Layout.preferredWidth: 40 }
                                            T { text: li.modelData.dir ? "" : w.human(li.modelData.size); color: Theme.dim; Layout.preferredWidth: 55; horizontalAlignment: Text.AlignRight }
                                        }
                                        MouseArea {
                                            id: lim
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: w.selected = li.modelData.path
                                            onDoubleClicked: li.modelData.dir ? w.go(li.modelData.path) : w.openFile(li.modelData.path)
                                        }
                                    }
                                }

                                T {
                                    visible: w.dirList.length === 0 && w.fileList.length === 0
                                    Layout.fillWidth: true
                                    Layout.topMargin: 30
                                    horizontalAlignment: Text.AlignHCenter
                                    text: w.query !== "" ? "Ничего не нашлось" : "Папка пуста"
                                    color: Theme.dim
                                }
                            }
                        }

                        // rename bar
                        Rectangle {
                            visible: w.renaming !== ""
                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.margins: 8
                            height: 32; radius: 10
                            color: Theme.cardSolid
                            border.color: Qt.rgba(1, 1, 1, 0.3)
                            onVisibleChanged: if (visible) { ren.text = w.base(w.renaming); ren.selectAll(); ren.forceActiveFocus(); }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 4
                                T { text: "Новое имя:"; color: Theme.dim }
                                TextInput {
                                    id: ren
                                    Layout.fillWidth: true
                                    font.family: Theme.font; font.pixelSize: 11; color: Theme.text
                                    onAccepted: {
                                        let t = text.trim();
                                        if (t !== "" && t.indexOf("/") < 0 && t !== w.base(w.renaming))
                                            w.run(["mv", "-n", "--", w.renaming, w.path + "/" + t], "Переименовано");
                                        w.renaming = "";
                                    }
                                    Keys.onEscapePressed: w.renaming = ""
                                }
                                Chip { label: "Готово"; primary: true; onClicked: ren.accepted() }
                            }
                        }
                    }

                    // «Оформление папки»
                    Rectangle {
                        id: looksPane
                        visible: w.showLooks
                        Layout.preferredWidth: 170
                        Layout.fillHeight: true
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.035)
                        border.color: Theme.line
                        readonly property string target: w.selected !== "" && w.dirList.some(d => d.path === w.selected) ? w.selected : w.path
                        readonly property var look: w.lookOf(target)
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 5
                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -1
                                    T { text: "Оформление папки"; font.pixelSize: 12; font.weight: Font.Bold }
                                    T { Layout.fillWidth: true; text: w.base(looksPane.target) || "/"; color: Theme.dim; font.pixelSize: 9 }
                                }
                                IconBtn { glyph: "󰅖"; onClicked: w.showLooks = false }
                            }
                            T { text: "Материал"; color: Theme.sub; font.pixelSize: 9 }
                            Grid {
                                columns: 4
                                spacing: 4
                                Repeater {
                                    model: [{ v: "glass", t: "Стекло" }, { v: "silk", t: "Шёлк" }, { v: "archive", t: "Архив" }, { v: "lava", t: "Лава" }]
                                    Rectangle {
                                        required property var modelData
                                        readonly property bool on: looksPane.look.material === modelData.v
                                        width: 35; height: 40; radius: 7
                                        color: Qt.rgba(1, 1, 1, 0.05)
                                        border.color: on ? Theme.accent : Theme.line
                                        border.width: on ? 1.5 : 1
                                        FolderArt { x: 5; y: 3; width: 25; height: 20; material: parent.modelData.v; tint: looksPane.look.tint }
                                        T { anchors.bottom: parent.bottom; anchors.bottomMargin: 2; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: parent.modelData.t; font.pixelSize: 7 }
                                        MouseArea { anchors.fill: parent; onClicked: w.setLook(looksPane.target, "material", parent.modelData.v) }
                                    }
                                }
                            }
                            T { text: "Оттенок"; color: Theme.sub; font.pixelSize: 9; Layout.topMargin: 2 }
                            Row {
                                spacing: 5
                                Repeater {
                                    model: [["graphite", "#3a3a40"], ["gray", "#8b8b93"], ["white", "#f2f2f4"], ["blue", "#6f8fc0"], ["green", "#6fb08a"], ["sand", "#d9c2a0"]]
                                    Rectangle {
                                        required property var modelData
                                        readonly property bool on: looksPane.look.tint === modelData[0]
                                        width: 21; height: 21; radius: 11
                                        color: modelData[1]
                                        border.color: on ? Theme.accent : Qt.rgba(1, 1, 1, 0.2)
                                        border.width: on ? 2 : 1
                                        G { anchors.centerIn: parent; visible: parent.on; text: "󰄬"; font.pixelSize: 10; color: parent.modelData[0] === "white" || parent.modelData[0] === "sand" ? Theme.accentInk : Theme.text }
                                        MouseArea { anchors.fill: parent; onClicked: w.setLook(looksPane.target, "tint", parent.modelData[0]) }
                                    }
                                }
                            }
                            T { text: "Фон окна"; color: Theme.sub; font.pixelSize: 9; Layout.topMargin: 2 }
                            Row {
                                spacing: 4
                                Repeater {
                                    model: ["dark", "black", "ember", "silver"]
                                    Rectangle {
                                        id: bgs
                                        required property string modelData
                                        width: 34; height: 22; radius: 6
                                        border.color: looks.background === modelData ? Theme.accent : Theme.line
                                        border.width: looks.background === modelData ? 1.5 : 1
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: w.backgrounds[bgs.modelData][0] }
                                            GradientStop { position: 1; color: w.backgrounds[bgs.modelData][1] }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: looks.background = parent.modelData }
                                    }
                                }
                            }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line; Layout.topMargin: 3 }
                            GridLayout {
                                columns: 2
                                columnSpacing: 6
                                rowSpacing: 1
                                Layout.fillWidth: true
                                T { text: "Путь"; color: Theme.dim; font.pixelSize: 8 }
                                T { Layout.fillWidth: true; text: w.pretty(looksPane.target); font.family: Theme.mono; font.pixelSize: 8 }
                                T { text: "Диск"; color: Theme.dim; font.pixelSize: 8 }
                                T { Layout.fillWidth: true; text: w.here ? w.here.mount + " · " + w.here.fs : "—"; font.family: Theme.mono; font.pixelSize: 8 }
                            }
                            Item { Layout.fillHeight: true }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Chip { label: "Сбросить"; onClicked: { let all = Object.assign({}, looks.folders); delete all[looksPane.target]; looks.folders = all; } }
                                Chip {
                                    Layout.fillWidth: true
                                    label: "Ко всем"
                                    primary: true
                                    onClicked: {
                                        let all = Object.assign({}, looks.folders);
                                        for (let d of w.dirList) all[d.path] = Object.assign({}, looksPane.look);
                                        looks.folders = all;
                                        w.say("Оформление применено ко всем папкам");
                                    }
                                }
                            }
                        }
                    }
                }

                // ── status bar ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    T {
                        Layout.fillWidth: true
                        text: w.toast !== "" ? w.toast
                            : w.selected !== "" ? "Выделено: " + w.base(w.selected) + "  ·  F2 — переименовать, Delete — в корзину"
                            : w.pretty(w.path)
                        color: w.toast !== "" ? Theme.text : Theme.sub
                        font.pixelSize: 10
                    }
                    T { visible: w.here !== null; text: w.here ? "Свободно " + w.human(w.here.avail) : ""; color: Theme.sub; font.pixelSize: 10 }
                    Rectangle {
                        visible: w.here !== null
                        implicitWidth: 60; implicitHeight: 4; radius: 2
                        color: Qt.rgba(1, 1, 1, 0.12)
                        Rectangle { width: w.here ? parent.width * w.here.used / Math.max(1, w.here.size) : 0; height: parent.height; radius: 2; color: Theme.accent }
                    }
                    Chip { glyph: "󰆍"; label: "Терминал  F4"; onClicked: Quickshell.execDetached(["kitty", "--directory", w.path]) }
                }
            }

            Component.onCompleted: w.path = root.startPath
        }
    }
}
