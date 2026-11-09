import QtQuick
import QtQuick.Layouts
import Quickshell

// One row of the conversation: user bubble, assistant markdown, tool call or error.
Item {
    id: item
    property var row
    property real maxWidth: width
    // failed commands open by themselves so the error is visible
    property bool expanded: row && row.kind === "tool" && row.status === "error"
    property bool isLast: false          // last row of the chat → show reply actions
    property bool busy: false
    property bool highlighted: false     // current Ctrl+F match
    signal action(string what)           // "retry" | "edit" | "continue" | "copy"
    readonly property bool showActions: isLast && !busy && Prefs.replyActions
                                        && (kind === "assistant" || kind === "error")

    readonly property string kind: row ? row.kind : ""
    readonly property bool hidden: kind === "tool" && !Prefs.showTools
    readonly property var toolInput: {
        if (!row || row.input === undefined || row.input === "") return null;
        try { return JSON.parse(row.input); } catch (e) { return null; }
    }
    // Edit/MultiEdit/Write as diff lines: [{t: "-"|"+"|" ", s: text}]
    function diffLines(name, inp) {
        if (!inp) return [];
        let out = [];
        let add = (sign, text) => {
            let ls = String(text).split("\n");
            for (let l of ls) { if (out.length < 60) out.push({ t: sign, s: l }); }
        };
        if (name === "Edit") { add("-", inp.old_string || ""); add("+", inp.new_string || ""); }
        else if (name === "MultiEdit" && Array.isArray(inp.edits)) {
            for (let e of inp.edits) { add("-", e.old_string || ""); add("+", e.new_string || ""); }
        } else if (name === "Write") add("+", inp.content || "");
        if (out.length >= 60) out.push({ t: " ", s: "…" });
        return out;
    }

    width: ListView.view ? ListView.view.width : 300
    height: hidden ? 0 : content.height + 10 + (showActions ? actionsRow.height + 6 : 0)
    visible: !hidden

    function toolIcon(name) {
        switch (name) {
        case "Bash": return "";
        case "Read": return "󰈙";
        case "Write": return "󰏫";
        case "Edit": case "NotebookEdit": return "󰷈";
        case "Grep": case "Glob": return "";
        case "WebFetch": case "WebSearch": return "󰖟";
        case "Task": case "Agent": return "󱙺";
        case "TodoWrite": return "󰄲";
        }
        return "󰘦";
    }

    // Split markdown into prose and fenced code so code gets its own card
    function segments(t, streaming) {
        let out = [];
        let re = /```([^\n`]*)\n?([\s\S]*?)(?:```|$)/g;
        let last = 0, m;
        while ((m = re.exec(t)) !== null) {
            if (m.index > last) out.push({ code: false, text: t.substring(last, m.index) });
            out.push({ code: true, lang: m[1].trim(), text: m[2].replace(/\n$/, "") });
            last = re.lastIndex;
            if (m[0].length === 0) break;
        }
        if (last < t.length) out.push({ code: false, text: t.substring(last) });
        out = out.filter(x => x.code || x.text.trim() !== "");
        if (streaming) {
            if (out.length === 0 || out[out.length - 1].code) out.push({ code: false, text: "▍" });
            else out[out.length - 1].text += " ▍";
        }
        return out;
    }

    Component {
        id: mdBlock
        TextEdit {
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.MarkdownText
            text: parent && parent.seg ? parent.seg.text : ""
            font.family: Theme.font
            font.pixelSize: Math.round(13 * Prefs.textScale)
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
        }
    }

    Component {
        id: codeBlock
        Rectangle {
            readonly property var seg: parent ? parent.seg : null
            implicitHeight: codeCol.implicitHeight + 14
            radius: 10
            color: Theme.panel
            border.color: Theme.border

            Column {
                id: codeCol
                x: 10; y: 7
                width: parent.width - 20
                spacing: 4
                Item {
                    width: parent.width
                    height: Math.max(langText.implicitHeight, 16)
                    Text {
                        id: langText
                        text: seg && seg.lang !== "" ? seg.lang : "код"
                        font.family: Theme.font
                        font.pixelSize: Math.round(10 * Prefs.textScale)
                        font.bold: true
                        color: Theme.accent
                    }
                    Text {
                        id: codeCopy
                        property bool copied: false
                        anchors.right: parent.right
                        text: copied ? "󰄬 скопировано" : "󰆏 копировать"
                        font.family: Theme.font
                        font.pixelSize: Math.round(10 * Prefs.textScale)
                        color: copied ? Theme.ok : codeCopyMouse.containsMouse ? Theme.accent : Theme.dim
                        MouseArea {
                            id: codeCopyMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["wl-copy", "--", seg ? seg.text : ""]);
                                codeCopy.copied = true;
                                codeCopyTimer.restart();
                            }
                        }
                        Timer { id: codeCopyTimer; interval: 1500; onTriggered: codeCopy.copied = false }
                    }
                }
                TextEdit {
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    text: seg ? seg.text : ""
                    font.family: Theme.font
                    font.pixelSize: Math.round(12 * Prefs.textScale)
                    color: Theme.sub
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                }
            }
        }
    }

    HoverHandler { id: hover }

    // Appear animation
    opacity: 0
    transform: Translate { id: slide; y: 12 }
    Component.onCompleted: appear.start()
    ParallelAnimation {
        id: appear
        NumberAnimation { target: item; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: slide; property: "y"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
    }

    Rectangle {
        visible: item.highlighted
        x: -4; y: 1
        width: parent.width + 8
        height: content.height + 8
        radius: Theme.radius
        color: Qt.alpha(Theme.accent, 0.12)
        border.color: Qt.alpha(Theme.accent, 0.6)
    }

    // ── under the last answer: retry / edit / continue / copy ──
    Row {
        id: actionsRow
        visible: item.showActions
        x: 22
        y: content.y + content.height + 4
        spacing: 6
        ActionChip { icon: "󰑓"; label: "Заново"; onClicked: item.action("retry") }
        ActionChip { icon: "󰏫"; label: "Изменить запрос"; onClicked: item.action("edit") }
        ActionChip { icon: "󰐊"; label: "Продолжи"; onClicked: item.action("continue") }
        ActionChip { visible: item.kind === "assistant"; icon: "󰆏"; label: "Копировать"; onClicked: item.action("copy") }
    }

    Item {
        id: content
        width: parent.width
        height: childrenRect.height
        y: 5

        // ── user ─────────────────────────────────────
        Rectangle {
            visible: item.kind === "user"
            anchors.right: parent.right
            anchors.rightMargin: 4
            width: Math.min(userText.implicitWidth + 24, item.width * 0.82)
            height: visible ? userText.implicitHeight + 16 : 0
            radius: Theme.radius
            color: Theme.accentDeep
            border.color: Qt.alpha(Theme.accent, 0.35)

            TextEdit {
                id: userText
                anchors.fill: parent
                anchors.margins: 8
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                text: item.row ? item.row.text : ""
                font.family: Theme.font
                font.pixelSize: Math.round(13 * Prefs.textScale)
                color: Theme.text
                selectionColor: Theme.accent
                selectedTextColor: Theme.bg
            }
        }

        // ── assistant ────────────────────────────────
        RowLayout {
            visible: item.kind === "assistant"
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                text: "✻"
                font.pixelSize: Math.round(15 * Prefs.textScale)
                color: Theme.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: item.kind === "assistant" ? item.segments(item.row.text, item.row.streaming) : []

                    Loader {
                        Layout.fillWidth: true
                        property var seg: modelData
                        sourceComponent: seg.code ? codeBlock : mdBlock
                    }
                }
            }

            // copy the whole reply (shown on hover)
            Text {
                id: copyBtn
                property bool copied: false
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
                text: copied ? "󰄬" : "󰆏"
                font.family: Theme.font
                font.pixelSize: 14
                color: copied ? Theme.ok : copyMouse.containsMouse ? Theme.accent : Theme.dim
                opacity: item.kind === "assistant" && item.row && !item.row.streaming && (hover.hovered || copied) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", "--", item.row.text]);
                        copyBtn.copied = true;
                        copiedTimer.restart();
                    }
                }
                Timer { id: copiedTimer; interval: 1500; onTriggered: copyBtn.copied = false }
            }
        }

        // ── tool call ────────────────────────────────
        Rectangle {
            id: toolCard
            visible: item.kind === "tool"
            x: 22
            width: parent.width - 26
            height: visible ? toolCol.implicitHeight + 12 : 0
            radius: 10
            color: toolMouse.containsMouse ? Theme.cardHi : Theme.card
            border.color: item.row && item.row.status === "running" ? Qt.alpha(Theme.accent, 0.25 + 0.35 * pulse) : Theme.border
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            clip: true

            property real pulse: 0
            SequentialAnimation on pulse {
                running: item.row && item.row.status === "running"
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 1; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0; duration: 600; easing.type: Easing.InOutSine }
            }

            MouseArea {
                id: toolMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: item.expanded = !item.expanded
            }

            ColumnLayout {
                id: toolCol
                x: 10; y: 6
                width: parent.width - 20
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: item.toolIcon(item.row ? item.row.toolName : "")
                        font.family: Theme.font
                        font.pixelSize: Math.round(14 * Prefs.textScale)
                        color: Theme.accent
                    }
                    Text {
                        text: item.row ? item.row.toolName : ""
                        font.family: Theme.font
                        font.pixelSize: Math.round(12 * Prefs.textScale)
                        font.bold: true
                        color: Theme.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: item.row ? item.row.summary : ""
                        font.family: Theme.font
                        font.pixelSize: Math.round(12 * Prefs.textScale)
                        color: Theme.sub
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    // status: spinning arc while running, pops into a mark when done
                    Item {
                        width: 16; height: 16
                        Rectangle {
                            id: spinRing
                            visible: item.row && item.row.status === "running"
                            anchors.fill: parent
                            radius: 8
                            color: "transparent"
                            border.width: 2
                            border.color: Qt.alpha(Theme.accent, 0.25)
                            Rectangle {
                                width: 5; height: 5; radius: 2.5
                                color: Theme.accent
                                x: 8 - 2.5 + 6 * Math.cos(spinA.angle)
                                y: 8 - 2.5 + 6 * Math.sin(spinA.angle)
                            }
                            QtObject { id: spinA; property real angle: 0 }
                            NumberAnimation { target: spinA; property: "angle"; from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite; running: spinRing.visible }
                        }
                        Text {
                            id: mark
                            anchors.centerIn: parent
                            visible: item.row && item.row.status !== "running"
                            text: !item.row ? "" : item.row.status === "ok" ? "󰄬" : item.row.status === "denied" ? "󰜺" : "󰅖"
                            font.family: Theme.font
                            font.pixelSize: Math.round(14 * Prefs.textScale)
                            color: item.row && item.row.status === "ok" ? Theme.ok : Theme.error
                            scale: visible ? 1 : 0
                            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                        }
                    }
                }

                // TodoWrite: Claude's task list as a checklist
                Column {
                    Layout.fillWidth: true
                    visible: item.row && item.row.toolName === "TodoWrite" && item.toolInput && Array.isArray(item.toolInput.todos)
                    spacing: 3
                    Repeater {
                        model: parent.visible ? item.toolInput.todos : []
                        Row {
                            required property var modelData
                            spacing: 8
                            Text {
                                text: modelData.status === "completed" ? "󰄬" : modelData.status === "in_progress" ? "󰪥" : "󰄱"
                                font.family: Theme.font
                                font.pixelSize: Math.round(13 * Prefs.textScale)
                                color: modelData.status === "completed" ? Theme.ok : modelData.status === "in_progress" ? Theme.accent : Theme.dim
                            }
                            Text {
                                width: toolCol.width - 30
                                text: modelData.status === "in_progress" && modelData.activeForm ? modelData.activeForm : (modelData.content || "")
                                font.family: Theme.font
                                font.pixelSize: Math.round(12 * Prefs.textScale)
                                font.strikeout: modelData.status === "completed"
                                font.bold: modelData.status === "in_progress"
                                color: modelData.status === "completed" ? Theme.dim : Theme.text
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                // Edit / Write: what changed, red = removed, green = added
                Rectangle {
                    Layout.fillWidth: true
                    visible: item.expanded && diffRepeater.count > 0
                    implicitHeight: diffCol.implicitHeight + 8
                    radius: 6
                    color: Theme.bg
                    Column {
                        id: diffCol
                        x: 4; y: 4
                        width: parent.width - 8
                        Repeater {
                            id: diffRepeater
                            model: item.expanded && item.row ? item.diffLines(item.row.toolName, item.toolInput) : []
                            Rectangle {
                                required property var modelData
                                width: diffCol.width
                                implicitHeight: diffText.implicitHeight
                                color: modelData.t === "-" ? Qt.alpha(Theme.error, 0.14) : modelData.t === "+" ? Qt.alpha(Theme.ok, 0.14) : "transparent"
                                Text {
                                    id: diffText
                                    width: parent.width
                                    text: modelData.t + " " + modelData.s
                                    font.family: Theme.font
                                    font.pixelSize: Math.round(11 * Prefs.textScale)
                                    color: modelData.t === "-" ? Theme.error : modelData.t === "+" ? Theme.ok : Theme.dim
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: item.expanded && item.row && item.row.detail !== "" && diffRepeater.count === 0
                    Layout.fillWidth: true
                    text: item.row ? item.row.detail : ""
                    color: item.row && item.row.status === "error" ? Theme.error : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Math.round(11 * Prefs.textScale)
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        // ── error ────────────────────────────────────
        Rectangle {
            visible: item.kind === "error"
            width: parent.width
            height: visible ? errText.implicitHeight + 14 : 0
            radius: 10
            color: Qt.alpha(Theme.error, 0.12)
            border.color: Qt.alpha(Theme.error, 0.4)
            Text {
                id: errText
                anchors.fill: parent
                anchors.margins: 7
                anchors.leftMargin: 10
                text: "󰀦  " + (item.row ? item.row.text : "")
                font.family: Theme.font
                font.pixelSize: Math.round(12 * Prefs.textScale)
                color: Theme.error
                wrapMode: Text.Wrap
            }
        }
    }
}
