import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pam

// Lock screen UI (design/screens/01-lock.jpg). Password goes through PAM ("login" stack).
// In preview mode nothing is checked; the arrow just closes the preview.
Item {
    id: lc
    required property var st
    property bool preview: false
    signal unlocked()

    readonly property string user: Quickshell.env("USER") || "user"
    property string status: ""
    property bool busy: false
    property string pending: ""

    function submit() {
        if (busy) return;
        if (preview) { unlocked(); return; }
        if (pw.text === "") return;
        pending = pw.text;
        busy = true;
        status = "";
        pam.start();
    }

    PamContext {
        id: pam
        config: "login"
        onResponseRequiredChanged: {
            if (responseRequired) { respond(lc.pending); lc.pending = ""; }
        }
        onCompleted: result => {
            lc.busy = false;
            if (result === PamResult.Success) {
                pw.text = "";
                lc.unlocked();
            } else {
                lc.status = "Неверный пароль";
                pw.text = "";
                shake.restart();
                pw.forceActiveFocus();
            }
        }
        onError: { lc.busy = false; lc.status = "Не удалось проверить пароль"; }
    }

    WallArt { anchors.fill: parent }
    Bezel { anchors.fill: parent }

    component T: Text {
        font.family: Theme.font
        color: Theme.text
    }
    component G: Text {
        font.family: Theme.icons
        color: Theme.text
    }
    component Round: Rectangle {
        id: rb
        property string glyph: ""
        signal clicked()
        width: 30; height: 30; radius: 15
        color: rm.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        scale: rm.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        G { anchors.centerIn: parent; text: rb.glyph; font.pixelSize: 14 }
        MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; onClicked: rb.clicked() }
    }

    // ── top bezel ──
    Item {
        width: parent.width
        height: Theme.barH
        RowLayout {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                implicitWidth: lockRow.implicitWidth + 16
                implicitHeight: 21
                radius: 7
                color: Qt.rgba(1, 1, 1, 0.05)
                RowLayout {
                    id: lockRow
                    anchors.centerIn: parent
                    spacing: 6
                    G { text: "󰌾"; font.pixelSize: 11; color: Theme.sub }
                    T { text: "Экран блокировки"; font.pixelSize: 11 }
                }
            }
            T { text: lc.user + "@ashenos"; font.family: Theme.mono; font.pixelSize: 10; color: Theme.dim }
        }
        Rectangle {
            anchors.centerIn: parent
            width: islandRow.implicitWidth + 20
            height: 22
            radius: 11
            color: "#000000"
            border.color: Qt.rgba(1, 1, 1, 0.08)
            RowLayout {
                id: islandRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; color: Theme.accent }
                T { text: "Заблокировано"; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }
        RowLayout {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                visible: lc.st.layout !== ""
                implicitWidth: 22; implicitHeight: 17; radius: 5
                color: Qt.rgba(1, 1, 1, 0.1)
                T { anchors.centerIn: parent; text: lc.st.layout; font.pixelSize: 9; font.weight: Font.Bold }
            }
            G { text: lc.st.wifiIcon; font.pixelSize: 13 }
            T { text: Qt.formatTime(lc.st.clock.date, "HH:mm"); font.family: Theme.mono; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
    }

    // ── centre ──
    ColumnLayout {
        id: timeBlock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.barH + parent.height * 0.06
        spacing: 2
        T {
            Layout.alignment: Qt.AlignHCenter
            text: {
                let s = lc.st.clock.date.toLocaleDateString(Qt.locale("ru_RU"), "dddd, d MMMM");
                return s.charAt(0).toUpperCase() + s.substring(1);
            }
            font.pixelSize: 13
            color: "#d4d4da"
        }
        T {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(lc.st.clock.date, "HH:mm")
            font.pixelSize: Math.round(Math.min(78, lc.height * 0.17))
            font.weight: Font.Bold
            font.letterSpacing: -2
            color: "#ececf0"
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: timeBlock.bottom
        anchors.topMargin: Math.max(6, (parent.height - Theme.barH - timeBlock.height - implicitHeight) * 0.28)
        spacing: 7

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 46; implicitHeight: 46; radius: 23
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#7a3a3a" }
                GradientStop { position: 0.5; color: "#3d5c8a" }
                GradientStop { position: 1; color: "#5b7fb0" }
            }
            border.color: Qt.rgba(1, 1, 1, 0.25)
            border.width: 2
            T { anchors.centerIn: parent; text: lc.user.charAt(0).toUpperCase(); font.pixelSize: 20; font.weight: Font.Bold }
        }
        T { Layout.alignment: Qt.AlignHCenter; text: lc.user; font.pixelSize: 13; font.weight: Font.Bold }

        // password
        Rectangle {
            id: field
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            implicitWidth: 230
            implicitHeight: 32
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.07)
            border.color: lc.status !== "" ? Qt.rgba(1, 0.42, 0.42, 0.6) : pw.activeFocus ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.12)
            Behavior on border.color { ColorAnimation { duration: 200 } }
            transform: Translate { id: shakeT }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeT; property: "x"; to: -9; duration: 50 }
                NumberAnimation { target: shakeT; property: "x"; to: 8; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: -5; duration: 70 }
                NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 3
                spacing: 6
                TextInput {
                    id: pw
                    Layout.fillWidth: true
                    property bool reveal: false
                    echoMode: reveal ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.text
                    clip: true
                    focus: true
                    enabled: !lc.busy
                    onAccepted: lc.submit()
                    onTextChanged: if (text !== "") lc.status = ""
                    T { anchors.verticalCenter: parent.verticalCenter; visible: pw.text === ""; text: "Пароль"; color: Theme.dim; font.pixelSize: 12 }
                }
                G {
                    text: pw.reveal ? "󰈉" : "󰈈"
                    font.pixelSize: 13
                    color: Theme.dim
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: pw.reveal = !pw.reveal }
                }
                Rectangle {
                    implicitWidth: 26; implicitHeight: 26; radius: 13
                    color: Theme.accent
                    scale: am.pressed ? 0.85 : 1
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    G {
                        anchors.centerIn: parent
                        text: lc.busy ? "󰔟" : "󰁔"
                        font.pixelSize: 14
                        color: Theme.accentInk
                        RotationAnimation on rotation { running: lc.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                    }
                    MouseArea { id: am; anchors.fill: parent; onClicked: lc.submit() }
                }
            }
        }
        T {
            Layout.alignment: Qt.AlignHCenter
            text: lc.preview ? "Превью: стрелка закрывает окно" : lc.status
            opacity: text !== "" ? 1 : 0
            font.pixelSize: 11
            color: lc.preview ? Theme.dim : "#ff8a8a"
        }
    }

    // power
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.side + 12
        spacing: 8
        Round { glyph: "󰤄"; onClicked: if (!lc.preview) Quickshell.execDetached(["systemctl", "suspend"]) }
        Round { glyph: "󰜉"; onClicked: if (!lc.preview) Quickshell.execDetached(["systemctl", "reboot"]) }
        Round { glyph: "󰐥"; onClicked: if (!lc.preview) Quickshell.execDetached(["systemctl", "poweroff"]) }
    }

    Component.onCompleted: pw.forceActiveFocus()
}
