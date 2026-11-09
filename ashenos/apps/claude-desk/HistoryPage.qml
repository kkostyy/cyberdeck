import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Earlier conversations in the current folder; tap one to continue it.
Rectangle {
    id: page
    required property var ses
    property bool shown: false
    property var chats: []
    property string filter: ""
    property string confirmDelete: ""

    function open() {
        page.shown = true;
        page.filter = "";
        search.text = "";
        page.forceActiveFocus();
        lister.running = false;
        lister.running = true;
    }
    function close() { page.shown = false; }

    function when(ts) {
        let d = new Date(ts * 1000), now = new Date();
        let day = Qt.formatDate(d, "yyyy-MM-dd"), t = Qt.formatTime(d, "HH:mm");
        if (day === Qt.formatDate(now, "yyyy-MM-dd")) return "сегодня, " + t;
        if (day === Qt.formatDate(new Date(now.getTime() - 86400000), "yyyy-MM-dd")) return "вчера, " + t;
        if (now.getTime() - d.getTime() < 6 * 86400000) return d.toLocaleDateString(Qt.locale("ru_RU"), "dddd") + ", " + t;
        return d.toLocaleDateString(Qt.locale("ru_RU"), "d MMMM") + ", " + t;
    }
    readonly property var shownChats: {
        let f = filter.trim().toLowerCase();
        return f === "" ? chats : chats.filter(c => (c.title + " " + c.last).toLowerCase().indexOf(f) >= 0);
    }

    color: Theme.bg
    visible: x < parent.width
    x: shown ? 0 : parent.width
    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    focus: shown
    Keys.onEscapePressed: page.close()
    MouseArea { anchors.fill: parent; onClicked: page.forceActiveFocus() }

    Process {
        id: lister
        command: ["python3", "-I", Qt.resolvedUrl("chats.py").toString().replace(/^file:\/\//, ""), page.ses.workDir]
        stdout: StdioCollector {
            onStreamFinished: { try { page.chats = JSON.parse(this.text); } catch (e) { page.chats = []; } }
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
                text: "История"
                font.family: Theme.font
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 15
                color: Theme.card
                border.color: search.activeFocus ? Qt.alpha(Theme.accent, 0.7) : Theme.border
                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.text
                    selectionColor: Theme.accent
                    clip: true
                    onTextChanged: page.filter = text
                    Keys.onEscapePressed: page.close()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: search.text === ""
                        text: "󰍉  поиск по чатам"
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.dim
                    }
                }
            }
            PillButton {
                implicitHeight: 28
                icon: "󰐕"
                label: page.width > 500 ? "Новый чат" : ""
                onClicked: { page.ses.newChat(); page.close(); }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: page.shownChats
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.alpha(Theme.sub, 0.4) }
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool current: modelData.id === page.ses.sessionId
                readonly property bool confirming: page.confirmDelete === modelData.id
                width: list.width - 8
                implicitHeight: col.implicitHeight + 16
                radius: Theme.radius
                color: current ? Qt.alpha(Theme.accent, 0.18) : hover.hovered ? Theme.cardHi : Theme.card
                border.color: current ? Qt.alpha(Theme.accent, 0.6) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: hover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { page.ses.resume(row.modelData.id); page.close(); }
                }

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: actions.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.bold: row.current
                        color: Theme.text
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.confirming ? "Удалить этот чат насовсем?"
                            : page.when(row.modelData.mtime) + " · сообщений: " + row.modelData.count
                              + (row.modelData.last !== row.modelData.title ? " · «" + row.modelData.last + "»" : "")
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: row.confirming ? Theme.error : Theme.dim
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    PillButton {
                        visible: row.confirming
                        implicitHeight: 26
                        label: "Удалить"
                        danger: true
                        onClicked: {
                            let path = Quickshell.env("HOME") + "/.claude/projects/"
                                + page.ses.workDir.replace(/[^a-zA-Z0-9]/g, "-") + "/" + row.modelData.id + ".jsonl";
                            Quickshell.execDetached(["rm", "-f", "--", path]);
                            page.chats = page.chats.filter(c => c.id !== row.modelData.id);
                            page.confirmDelete = "";
                        }
                    }
                    PillButton {
                        visible: row.confirming
                        implicitHeight: 26
                        label: "Нет"
                        onClicked: page.confirmDelete = ""
                    }
                    PillButton {
                        visible: !row.confirming && !row.current
                        implicitHeight: 26
                        icon: "󰆴"
                        opacity: hover.hovered ? 1 : 0.5
                        onClicked: page.confirmDelete = row.modelData.id
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: page.chats.length === 0 ? "Здесь появятся прошлые разговоры" : "Ничего не нашлось"
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.dim
            }
        }
    }
}
