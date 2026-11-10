import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// "Параметры" window (design/screens/07-settings.jpg): sidebar of sections, content on the right.
// Everything is stored in Config (~/.config/ashen/config.json).
//   quickshell ipc call ashen-settings open [section]
Scope {
    id: root
    required property var st
    property bool shown: false
    property string section: "wall"

    IpcHandler {
        target: "ashen-settings"
        function open(section: string): void { if (section !== "") root.section = section; root.shown = true; }
        function close(): void { root.shown = false; }
    }

    readonly property var sections: [
        { id: "wall", t: "Обои", g: "󰸉" },
        { id: "dock", t: "Док", g: "󱂬" },
        { id: "bar", t: "Верхняя полоса", g: "󰍜" },
        { id: "screen", t: "Экран и сон", g: "󰍹" },
        { id: "notif", t: "Уведомления", g: "󰂚" },
        { id: "wx", t: "Погода", g: "󰖐" },
        { id: "time", t: "Экранное время", g: "󱎫" },
        { id: "about", t: "О системе", g: "󰋽" }
    ]

    LazyLoader {
        active: root.shown
        FloatingWindow {
            id: win
            title: "Параметры"
            implicitWidth: 620
            implicitHeight: 360
            color: Theme.bezel
            onClosed: root.shown = false

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
            component Pill: Rectangle {
                id: pl
                property string label: ""
                property string glyph: ""
                property bool on: false
                signal clicked()
                implicitWidth: pr.implicitWidth + 18
                implicitHeight: 24
                radius: 8
                color: on ? Theme.accent : pm.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
                Behavior on color { ColorAnimation { duration: 150 } }
                scale: pm.pressed ? 0.92 : 1
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                RowLayout {
                    id: pr
                    anchors.centerIn: parent
                    spacing: 5
                    G { visible: pl.glyph !== ""; text: pl.glyph; font.pixelSize: 12; color: pl.on ? Theme.accentInk : Theme.text }
                    T { visible: pl.label !== ""; text: pl.label; font.weight: Font.DemiBold; color: pl.on ? Theme.accentInk : Theme.text }
                }
                MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; onClicked: pl.clicked() }
            }
            component Switch_: Rectangle {
                id: sw
                property bool on: false
                signal toggled()
                implicitWidth: 34; implicitHeight: 20; radius: 10
                color: on ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                Behavior on color { ColorAnimation { duration: 180 } }
                Rectangle {
                    x: sw.on ? sw.width - width - 3 : 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14; radius: 7
                    color: sw.on ? Theme.accentInk : Theme.text
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
                MouseArea { anchors.fill: parent; onClicked: sw.toggled() }
            }
            // a settings row: title + hint, control on the right
            component Row_: Rectangle {
                id: rw
                property string title: ""
                property string hint: ""
                default property alias control: slot.data
                Layout.fillWidth: true
                implicitHeight: Math.max(tx.implicitHeight, slot.childrenRect.height) + 16
                radius: 10
                color: Theme.cardSolid
                ColumnLayout {
                    id: tx
                    anchors.left: parent.left
                    anchors.right: slot.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 1
                    T { Layout.fillWidth: true; text: rw.title; font.pixelSize: 12 }
                    T { Layout.fillWidth: true; visible: rw.hint !== ""; text: rw.hint; color: Theme.dim; font.pixelSize: 10; wrapMode: Text.Wrap }
                }
                Item {
                    id: slot
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: childrenRect.width
                    height: childrenRect.height
                }
            }
            component Head: T {
                Layout.topMargin: 4
                font.pixelSize: 16
                font.weight: Font.Bold
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── sidebar ──
                Rectangle {
                    Layout.preferredWidth: 160
                    Layout.fillHeight: true
                    color: "#0b0b0d"
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2
                        T { text: "Параметры"; font.pixelSize: 13; font.weight: Font.Bold; Layout.leftMargin: 6; Layout.bottomMargin: 6 }
                        Repeater {
                            model: root.sections
                            Rectangle {
                                id: sb
                                required property var modelData
                                readonly property bool on: root.section === modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: 8
                                color: on ? Qt.rgba(1, 1, 1, 0.12) : sbm.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    spacing: 8
                                    G { text: sb.modelData.g; font.pixelSize: 13; color: sb.on ? Theme.accent : Theme.sub }
                                    T { Layout.fillWidth: true; text: sb.modelData.t; font.weight: sb.on ? Font.DemiBold : Font.Normal }
                                }
                                MouseArea { id: sbm; anchors.fill: parent; hoverEnabled: true; onClicked: root.section = sb.modelData.id }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }

                // ── content ──
                Flickable {
                    id: page
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: body.implicitHeight + 24
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: page.contentHeight > page.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.25) }
                    }
                    Connections { target: root; function onSectionChanged() { page.contentY = 0; } }

                    ColumnLayout {
                        id: body
                        x: 14; y: 12
                        width: page.width - 28
                        spacing: 8

                        // ── wallpaper ──
                        ColumnLayout {
                            visible: root.section === "wall"
                            Layout.fillWidth: true
                            spacing: 8
                            Head { text: "Обои" }
                            T { text: "Картинки и видео из ~/Pictures/Wallpapers. Видео — живые обои: встают на паузу, когда экран закрыт окнами."; color: Theme.dim; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            RowLayout {
                                spacing: 6
                                T { text: "Расположение:"; color: Theme.sub }
                                Repeater {
                                    model: [{ v: "fill", t: "Заполнить" }, { v: "fit", t: "Вписать" }, { v: "center", t: "По центру" }]
                                    Pill { required property var modelData; label: modelData.t; on: Config.data.wallpaperFill === modelData.v; onClicked: Config.data.wallpaperFill = modelData.v }
                                }
                            }
                            Process {
                                id: walls
                                property var files: []
                                running: root.section === "wall"
                                command: ["bash", "-c", "find \"$HOME/Pictures/Wallpapers\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \\) 2>/dev/null | sort"]
                                stdout: StdioCollector { onStreamFinished: walls.files = [""].concat(this.text.split("\n").filter(l => l !== "")) }
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: walls.files
                                    Rectangle {
                                        id: wt
                                        required property string modelData
                                        readonly property bool on: Config.data.wallpaper === modelData
                                        readonly property bool video: /\.(mp4|webm|mkv)$/i.test(modelData)
                                        width: 126; height: 80
                                        radius: 10
                                        color: "#0b0b0d"
                                        border.width: on ? 2 : 1
                                        border.color: on ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
                                        clip: true
                                        WallArt { anchors.fill: parent; anchors.margins: 2; visible: wt.modelData === ""; source: "" }
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            visible: wt.modelData !== "" && !wt.video
                                            source: visible ? "file://" + wt.modelData : ""
                                            sourceSize.width: 160
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                        G { anchors.centerIn: parent; visible: wt.video; text: "󰕧"; font.pixelSize: 26; color: Theme.sub }
                                        Rectangle {
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                            anchors.margins: 2
                                            height: 18
                                            color: Qt.rgba(0, 0, 0, 0.6)
                                            T {
                                                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                                                verticalAlignment: Text.AlignVCenter
                                                text: wt.modelData === "" ? "AshenOS" : (wt.video ? "▶ " : "") + wt.modelData.split("/").pop()
                                                font.pixelSize: 9
                                            }
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: Config.data.wallpaper = wt.modelData }
                                    }
                                }
                            }
                        }

                        // ── dock ──
                        ColumnLayout {
                            visible: root.section === "dock"
                            Layout.fillWidth: true
                            spacing: 6
                            Head { text: "Док" }
                            T { text: "Закреплённые приложения по порядку. Запущенные незакреплённые док показывает сам."; color: Theme.dim; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Repeater {
                                model: Config.data.dock
                                Rectangle {
                                    id: di
                                    required property string modelData
                                    required property int index
                                    readonly property var entry: DesktopEntries.byId(modelData) || DesktopEntries.heuristicLookup(modelData)
                                    Layout.fillWidth: true
                                    implicitHeight: 30
                                    radius: 9
                                    color: Theme.cardSolid
                                    function move(d) {
                                        let a = Config.data.dock.slice(), j = index + d;
                                        if (j < 0 || j >= a.length) return;
                                        let t = a[index]; a[index] = a[j]; a[j] = t;
                                        Config.data.dock = a;
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 6
                                        spacing: 8
                                        Image {
                                            Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                            sourceSize.width: 18; sourceSize.height: 18
                                            source: di.entry ? Quickshell.iconPath(di.entry.icon, true) : ""
                                        }
                                        T { Layout.fillWidth: true; text: di.entry ? di.entry.name : di.modelData + " (не найдено)"; color: di.entry ? Theme.text : Theme.dim }
                                        Pill { glyph: "󰁝"; onClicked: di.move(-1) }
                                        Pill { glyph: "󰁅"; onClicked: di.move(1) }
                                        Pill { glyph: "󰅖"; onClicked: Config.data.dock = Config.data.dock.filter((x, i) => i !== di.index) }
                                    }
                                }
                            }
                            // add an app
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 9
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: addQ.activeFocus ? Qt.rgba(1, 1, 1, 0.3) : Theme.line
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    spacing: 6
                                    G { text: "󰐕"; font.pixelSize: 12; color: Theme.sub }
                                    TextInput {
                                        id: addQ
                                        Layout.fillWidth: true
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        color: Theme.text
                                        clip: true
                                        T { visible: addQ.text === ""; text: "Добавить приложение…"; color: Theme.dim }
                                    }
                                }
                            }
                            Repeater {
                                model: {
                                    let q = addQ.text.trim().toLowerCase();
                                    if (q === "") return [];
                                    return DesktopEntries.applications.values
                                        .filter(a => !a.noDisplay && Config.data.dock.indexOf(a.id) < 0 && a.name.toLowerCase().indexOf(q) >= 0)
                                        .slice(0, 4);
                                }
                                Rectangle {
                                    id: ad
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: 8
                                    color: adm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        spacing: 8
                                        Image { Layout.preferredWidth: 16; Layout.preferredHeight: 16; sourceSize.width: 16; sourceSize.height: 16; source: Quickshell.iconPath(ad.modelData.icon, true) }
                                        T { Layout.fillWidth: true; text: ad.modelData.name }
                                    }
                                    MouseArea {
                                        id: adm
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: { Config.data.dock = Config.data.dock.concat([ad.modelData.id]); addQ.text = ""; }
                                    }
                                }
                            }
                        }

                        // ── bar ──
                        ColumnLayout {
                            visible: root.section === "bar"
                            Layout.fillWidth: true
                            spacing: 6
                            Head { text: "Верхняя полоса" }
                            Row_ { title: "Кнопка Claude"; hint: "Открывает и прячет приложение Claude"; Switch_ { on: Config.data.barClaude; onToggled: Config.data.barClaude = !Config.data.barClaude } }
                            Row_ { title: "Нагрузка системы"; hint: "Три кольца: процессор, память, температура"; Switch_ { on: Config.data.barSysmon; onToggled: Config.data.barSysmon = !Config.data.barSysmon } }
                        }

                        // ── screen ──
                        ColumnLayout {
                            visible: root.section === "screen"
                            Layout.fillWidth: true
                            spacing: 6
                            Head { text: "Экран и сон" }
                            Row_ {
                                title: "Яркость"
                                Item {
                                    width: 170; height: 20
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width; height: 6; radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.12)
                                        Rectangle { width: parent.width * root.st.brightness; height: parent.height; radius: 3; color: Theme.accent }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onPressed: e => root.st.setBrightness(e.x / width)
                                        onPositionChanged: e => { if (pressed) root.st.setBrightness(Math.max(0, Math.min(1, e.x / width))); }
                                    }
                                }
                            }
                            Repeater {
                                model: [
                                    { k: "lockAfter", t: "Блокировать через", h: "Если ничего не делать (не во время музыки)" },
                                    { k: "screenOffAfter", t: "Гасить экран через", h: "Экран включится от любого нажатия" }
                                ]
                                Row_ {
                                    id: tr
                                    required property var modelData
                                    title: modelData.t
                                    hint: modelData.h
                                    Row {
                                        spacing: 4
                                        Repeater {
                                            model: [{ v: 120, t: "2 м" }, { v: 300, t: "5 м" }, { v: 600, t: "10 м" }, { v: 1800, t: "30 м" }, { v: 0, t: "никогда" }]
                                            Pill {
                                                required property var modelData
                                                label: modelData.t
                                                on: Config.data[tr.modelData.k] === modelData.v
                                                onClicked: Config.data[tr.modelData.k] = modelData.v
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // PIN for the lock screen (pin.py: salted hash, mode 600)
                        ColumnLayout {
                            visible: root.section === "screen"
                            Layout.fillWidth: true
                            spacing: 6
                            Process {
                                id: pinStatus
                                property bool isSet: false
                                running: root.section === "screen"
                                command: ["python3", "-I", Qt.resolvedUrl("pin.py").toString().replace(/^file:\/\//, ""), "status"]
                                stdout: StdioCollector { onStreamFinished: pinStatus.isSet = this.text.trim() === "set" }
                            }
                            Process {
                                id: pinSet
                                stdinEnabled: true
                                command: ["python3", "-I", Qt.resolvedUrl("pin.py").toString().replace(/^file:\/\//, ""), "set"]
                                onExited: code => { pinNote.text = code === 0 ? "PIN сохранён" : "Нужно 4–8 цифр"; pinStatus.running = true; }
                            }
                            Row_ {
                                title: "PIN-код на экране блокировки"
                                hint: pinStatus.isSet ? "Задан. После 5 ошибок PIN блокируется на минуту" : "Не задан — разблокировка только паролем"
                                Row {
                                    spacing: 4
                                    Rectangle {
                                        width: 80; height: 24; radius: 8
                                        color: Qt.rgba(1, 1, 1, 0.07)
                                        TextInput {
                                            id: pinIn
                                            anchors.fill: parent; anchors.leftMargin: 8
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            validator: RegularExpressionValidator { regularExpression: /[0-9]{0,8}/ }
                                            font.family: Theme.font; font.pixelSize: 11; color: Theme.text
                                            T { visible: pinIn.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "новый PIN"; color: Theme.dim }
                                        }
                                    }
                                    Pill { label: "Задать"; onClicked: { pinSet.running = true; pinSet.write(pinIn.text + "\n"); pinIn.text = ""; } }
                                    Pill {
                                        visible: pinStatus.isSet
                                        label: "Убрать"
                                        onClicked: { Quickshell.execDetached(["python3", "-I", Qt.resolvedUrl("pin.py").toString().replace(/^file:\/\//, ""), "clear"]); pinNote.text = "PIN убран"; pinStatus.isSet = false; }
                                    }
                                }
                            }
                            T { id: pinNote; color: Theme.dim; text: "" }
                        }

                        // ── notifications ──
                        ColumnLayout {
                            visible: root.section === "notif"
                            Layout.fillWidth: true
                            spacing: 6
                            Head { text: "Уведомления" }
                            Row_ { title: "Не беспокоить"; hint: "Уведомления не всплывают из острова, но попадают в список"; Switch_ { on: Config.data.dnd; onToggled: Config.data.dnd = !Config.data.dnd } }
                            Row_ { title: "В списке сейчас: " + root.st.notifs.length; Pill { label: "Очистить"; onClicked: root.st.clearNotifs() } }
                        }

                        // ── weather ──
                        ColumnLayout {
                            visible: root.section === "wx"
                            Layout.fillWidth: true
                            spacing: 6
                            Head { text: "Погода" }
                            Row_ {
                                title: Config.data.lat !== 0 || Config.data.lon !== 0 ? "Город: " + Config.data.city : "Город определяется по IP"
                                hint: root.st.weather ? "Сейчас: " + Math.round(root.st.weather.temp) + "°, " + root.st.weatherText + (root.st.weather.city ? " (" + root.st.weather.city + ")" : "") : ""
                                Pill {
                                    visible: Config.data.lat !== 0 || Config.data.lon !== 0
                                    label: "По IP"
                                    onClicked: { Config.data.lat = 0; Config.data.lon = 0; Config.data.city = ""; root.st.refreshWeather(); }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 9
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: cityQ.activeFocus ? Qt.rgba(1, 1, 1, 0.3) : Theme.line
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    spacing: 6
                                    G { text: ""; font.pixelSize: 11; color: Theme.sub }
                                    TextInput {
                                        id: cityQ
                                        Layout.fillWidth: true
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        color: Theme.text
                                        clip: true
                                        onAccepted: if (text.trim() !== "") { geo.command = ["python3", "-I", Qt.resolvedUrl("weather.py").toString().replace(/^file:\/\//, ""), "--geocode", text.trim()]; geo.running = true; }
                                        T { visible: cityQ.text === ""; text: "Другой город — введите и Enter"; color: Theme.dim }
                                    }
                                }
                            }
                            Process {
                                id: geo
                                property var hits: []
                                stdout: StdioCollector { onStreamFinished: { try { geo.hits = JSON.parse(this.text); } catch (e) { geo.hits = []; } } }
                            }
                            Repeater {
                                model: geo.hits
                                Rectangle {
                                    id: gh
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: 8
                                    color: ghm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.cardSolid
                                    T {
                                        anchors.fill: parent; anchors.leftMargin: 9
                                        verticalAlignment: Text.AlignVCenter
                                        text: gh.modelData.city + (gh.modelData.where ? "  · " + gh.modelData.where : "")
                                    }
                                    MouseArea {
                                        id: ghm
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            Config.data.lat = gh.modelData.lat;
                                            Config.data.lon = gh.modelData.lon;
                                            Config.data.city = gh.modelData.city;
                                            geo.hits = [];
                                            cityQ.text = "";
                                            root.st.refreshWeather();
                                        }
                                    }
                                }
                            }
                        }

                        // ── screen time ──
                        ColumnLayout {
                            id: tm
                            visible: root.section === "time"
                            Layout.fillWidth: true
                            spacing: 6
                            readonly property var today: root.st.usageFor(root.st.today)
                            readonly property int total: today.reduce((a, x) => a + x.secs, 0)
                            function hm(s) { let h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60); return h > 0 ? h + " ч " + m + " мин" : m + " мин"; }
                            function appName(id) { let e = DesktopEntries.heuristicLookup(id); return e ? e.name : id; }
                            // last 7 days, oldest first
                            readonly property var week: {
                                let out = [], d = new Date(root.st.clock.date);
                                for (let i = 6; i >= 0; i--) {
                                    let x = new Date(d.getFullYear(), d.getMonth(), d.getDate() - i);
                                    let k = Qt.formatDate(x, "yyyy-MM-dd");
                                    out.push({ k: k, d: x, s: root.st.usageFor(k).reduce((a, y) => a + y.secs, 0) });
                                }
                                return out;
                            }
                            readonly property int weekMax: Math.max(60, ...week.map(x => x.s))

                            Head { text: "Экранное время" }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 14
                                ColumnLayout {
                                    spacing: 0
                                    T { text: "Сегодня"; color: Theme.dim }
                                    T { text: tm.hm(tm.total); font.pixelSize: 22; font.weight: Font.Bold }
                                }
                                Item { Layout.fillWidth: true }
                                // week bars
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: tm.week
                                        Column {
                                            required property var modelData
                                            required property int index
                                            spacing: 2
                                            Item {
                                                width: 16; height: 40
                                                Rectangle {
                                                    anchors.bottom: parent.bottom
                                                    width: parent.width
                                                    height: Math.max(3, parent.height * parent.parent.modelData.s / tm.weekMax)
                                                    radius: 4
                                                    color: parent.parent.index === 6 ? Theme.accent : Qt.rgba(1, 1, 1, 0.3)
                                                }
                                            }
                                            T {
                                                width: 16
                                                horizontalAlignment: Text.AlignHCenter
                                                text: parent.modelData.d.toLocaleDateString(Qt.locale("ru_RU"), "ddd").substring(0, 2)
                                                font.pixelSize: 8
                                                color: Theme.dim
                                            }
                                        }
                                    }
                                }
                            }
                            T { visible: tm.today.length === 0; text: "Пока ничего не набралось — время считается, пока окно активно и вы не отходили."; color: Theme.dim; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Repeater {
                                model: tm.today.slice(0, 6)
                                RowLayout {
                                    id: ua
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8
                                    T { text: tm.appName(ua.modelData.app); Layout.preferredWidth: 120 }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 8
                                        radius: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        Rectangle { width: parent.width * ua.modelData.secs / Math.max(1, tm.today[0].secs); height: parent.height; radius: 4; color: Theme.accent }
                                    }
                                    T { text: tm.hm(ua.modelData.secs); color: Theme.sub; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                                }
                            }
                        }

                        // ── about ──
                        ColumnLayout {
                            visible: root.section === "about"
                            Layout.fillWidth: true
                            spacing: 6
                            Head { text: "О системе" }
                            Process {
                                id: info
                                property string out: ""
                                running: root.section === "about"
                                command: ["bash", "-c", "command -v ashenos-info >/dev/null && ashenos-info || { . /etc/os-release; echo \"$PRETTY_NAME\"; uname -r; }"]
                                stdout: StdioCollector { onStreamFinished: info.out = this.text.trim() }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: infoT.implicitHeight + 20
                                radius: 10
                                color: Theme.cardSolid
                                T { id: infoT; x: 12; y: 10; width: parent.width - 24; text: info.out; font.family: Theme.mono; wrapMode: Text.Wrap; elide: Text.ElideNone }
                            }
                            T { text: "Оболочка AshenOS на Quickshell · github.com/kkostyy/cyberdeck"; color: Theme.dim }
                        }
                    }
                }
            }
        }
    }
}
