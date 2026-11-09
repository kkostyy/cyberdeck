import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Files Claude changed in this chat (Edit / MultiEdit / Write), newest first.
// An Edit can be undone when its new text is still in the file exactly once.
Rectangle {
    id: page
    required property var ses
    property bool shown: false
    property var items: []            // [{row, tool, path, name, input, reverted}]
    property string message: ""
    readonly property int count: items.length

    function rebuild() {
        let out = [];
        for (let i = ses.messages.count - 1; i >= 0; i--) {
            let r = ses.messages.get(i);
            if (r.kind !== "tool" || ["Edit", "MultiEdit", "Write"].indexOf(r.toolName) < 0 || r.input === "") continue;
            let inp;
            try { inp = JSON.parse(r.input); } catch (e) { continue; }
            if (!inp.file_path) continue;
            out.push({ row: i, tool: r.toolName, path: inp.file_path, name: inp.file_path.split("/").pop(),
                       input: r.input, status: r.status, reverted: page.revertedRows.indexOf(i) >= 0 });
        }
        page.items = out;
    }
    property var revertedRows: []
    Connections {
        target: page.ses.messages
        function onCountChanged() { rebuildTimer.restart(); }
    }
    Timer { id: rebuildTimer; interval: 500; onTriggered: page.rebuild() }

    function open() { rebuild(); message = ""; shown = true; forceActiveFocus(); }
    function close() { shown = false; }
    function shortDir(p) {
        let home = Quickshell.env("HOME");
        return p.startsWith(home) ? "~" + p.substring(home.length) : p;
    }

    color: Theme.bg
    visible: x < parent.width
    x: shown ? 0 : parent.width
    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    focus: shown
    Keys.onEscapePressed: close()
    MouseArea { anchors.fill: parent; onClicked: page.forceActiveFocus() }

    Process {
        id: reverter
        property int row: -1
        property string payload: ""
        stdinEnabled: true
        command: ["python3", "-I", Qt.resolvedUrl("revert_edit.py").toString().replace(/^file:\/\//, "")]
        onStarted: { write(payload); stdinEnabled = false; }
        onExited: stdinEnabled = true
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim();
                if (t === "OK") {
                    page.revertedRows = page.revertedRows.concat([reverter.row]);
                    page.message = "Правка откачена";
                    page.rebuild();
                } else page.message = t || "Не получилось";
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PillButton { implicitHeight: 28; icon: "󰁍"; onClicked: page.close() }
            Text {
                Layout.fillWidth: true
                text: "Изменения в этом чате"
                font.family: Theme.font
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
            }
            Text {
                text: page.message
                font.family: Theme.font
                font.pixelSize: 11
                color: page.message === "Правка откачена" ? Theme.ok : Theme.error
                elide: Text.ElideRight
                Layout.maximumWidth: page.width * 0.45
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: page.items
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.alpha(Theme.sub, 0.4) }
            }
            delegate: Rectangle {
                id: ch
                required property var modelData
                width: list.width - 8
                implicitHeight: col.implicitHeight + 16
                radius: Theme.radius
                color: Theme.card
                opacity: modelData.reverted ? 0.55 : 1
                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: btns.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: (ch.modelData.tool === "Write" ? "󰏫 " : "󰷈 ") + ch.modelData.name
                              + (ch.modelData.reverted ? "  · откачено" : ch.modelData.status === "error" ? "  · не применилось" : "")
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.bold: true
                        color: Theme.text
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: page.shortDir(ch.modelData.path)
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: Theme.dim
                        elide: Text.ElideMiddle
                    }
                }
                Row {
                    id: btns
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    PillButton {
                        implicitHeight: 26
                        icon: "󰈔"
                        label: page.width > 520 ? "Открыть" : ""
                        onClicked: Quickshell.execDetached(["bash", "-c", "command -v code >/dev/null && exec code \"$1\" || exec xdg-open \"$1\"", "open", ch.modelData.path])
                    }
                    PillButton {
                        implicitHeight: 26
                        icon: "󰕌"
                        label: page.width > 520 ? "Откатить" : ""
                        visible: ch.modelData.tool === "Edit" && !ch.modelData.reverted && ch.modelData.status === "ok"
                        onClicked: {
                            if (reverter.running) return;
                            reverter.row = ch.modelData.row;
                            reverter.payload = ch.modelData.input;
                            reverter.running = true;
                        }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: "В этом чате Claude ещё не менял файлы"
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.dim
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Откатить можно правки (Edit), если исправленный фрагмент всё ещё в файле. Создание файлов (Write) не откатывается."
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 11
            color: Theme.dim
        }
    }
}
