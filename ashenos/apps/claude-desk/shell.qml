//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io

ShellRoot {
    component IconBtn: Text {
        id: ib
        signal clicked()
        width: 28; height: 30
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.font
        font.pixelSize: 16
        color: ibMouse.containsMouse ? Theme.accent : Theme.dim
        Behavior on color { ColorAnimation { duration: 150 } }
        MouseArea {
            id: ibMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }
    // Claude often edits this app from inside it; a hot reload would kill
    // the running claude process, so reload only on demand (IPC `reload`).
    settings.watchFiles: false

    FloatingWindow {
        id: win
        title: "Claude"
        implicitWidth: 680
        implicitHeight: 400
        color: Theme.bg
        onClosed: Qt.quit()

        Session {
            id: session
            onScrollRequested: scrollTimer.restart()
            onModelMenuRequested: modelMenu.open()
        }

        IpcHandler {
            target: "claude-desk"
            // used by the web mirror too: queue while Claude is busy
            function send(text: string): void { if (session.busy) session.enqueue(text, []); else session.send(text); }
            function stop(): void { session.interrupt(); }
            function answer(decision: string): void { session.answerPermission(decision); }
            function retry(): void { session.retryLast(); }
            function continueWork(): void { if (session.interrupted) session.continueWork(); else session.send("Продолжи"); }
            function newChat(dir: string): void { session.newChat(dir); }
            function allow(): void { session.answerPermission("allow"); }
            function deny(): void { session.answerPermission("deny"); }
            function reload(): void { Quickshell.reload(false); }
            function draft(text: string): void { input.text = text; input.cursorPosition = text.length; input.forceActiveFocus(); }
            function openModelMenu(): void { modelMenu.open(); }
            function openSettings(): void { settingsPage.open(); }
            function openHistory(): void { historyPage.open(); }
            function openSkills(): void { skillsPage.open(); }
            function screenshot(): void { composer.takeScreenshot(); }
            function attach(path: string): void { composer.attachImage(path); }
        }

        Timer {
            id: scrollTimer
            interval: 16
            onTriggered: if (chat.stick) chat.positionViewAtEnd()
        }

        Shortcut { sequence: "Ctrl+N"; context: Qt.ApplicationShortcut; onActivated: win.requestNewChat() }
        Shortcut { sequence: "Ctrl+F"; context: Qt.ApplicationShortcut; onActivated: searchBar.openSearch() }
        Shortcut { sequence: "Ctrl+H"; context: Qt.ApplicationShortcut; onActivated: historyPage.shown ? historyPage.close() : historyPage.open() }
        Shortcut { sequence: "Ctrl+,"; context: Qt.ApplicationShortcut; onActivated: settingsPage.shown ? settingsPage.close() : settingsPage.open() }
        Shortcut { sequence: "Ctrl+K"; context: Qt.ApplicationShortcut; onActivated: skillsPage.shown ? skillsPage.close() : skillsPage.open() }
        Shortcut { sequence: "Ctrl+M"; context: Qt.ApplicationShortcut; onActivated: modelMenu.visible ? modelMenu.close() : modelMenu.open() }
        Shortcut { sequence: "Ctrl+Shift+S"; context: Qt.ApplicationShortcut; onActivated: composer.takeScreenshot() }
        // text size: 80 % … 160 %
        Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; context: Qt.ApplicationShortcut; onActivated: Prefs.textScale = Math.min(1.6, Math.round((Prefs.textScale + 0.1) * 10) / 10) }
        Shortcut { sequence: "Ctrl+-"; context: Qt.ApplicationShortcut; onActivated: Prefs.textScale = Math.max(0.8, Math.round((Prefs.textScale - 0.1) * 10) / 10) }
        Shortcut { sequence: "Ctrl+0"; context: Qt.ApplicationShortcut; onActivated: Prefs.textScale = 1.0 }

        // `quick`: reachable by the header button; "Без вопросов" only from Settings
        readonly property var modes: [
            { id: "default", label: "Спрашивать", icon: "󰒃", quick: true,
              hint: "Спрашивает перед каждой командой и правкой" },
            { id: "acceptEdits", label: "Правки сам", icon: "󰷈", quick: true,
              hint: "Сам правит файлы в рабочей папке, но каждую команду Bash спрашивает" },
            { id: "auto", label: "Авто", icon: "󰚩", quick: true,
              hint: "Безопасные команды и правки делает сам, спрашивает только о рискованном" },
            { id: "plan", label: "План", icon: "󰙅", quick: true,
              hint: "Только читает и составляет план, ничего не меняет" },
            { id: "bypassPermissions", label: "Без вопросов", icon: "󱐋", quick: false, danger: true,
              hint: "Ничего не спрашивает, даже про удаление файлов. Включай осознанно" }
        ]
        function modeInfo(id) {
            for (let i = 0; i < modes.length; i++) if (modes[i].id === id) return modes[i];
            return modes[0];
        }
        function cycleMode() {
            let quick = modes.filter(m => m.quick);
            let i = quick.findIndex(m => m.id === session.permissionMode);
            session.setMode(quick[(i + 1) % quick.length].id);
        }
        function replyAction(what, text) {
            chat.stick = true;
            if (what === "retry") session.retryLast();
            else if (what === "continue") session.send("Продолжи");
            else if (what === "copy") Quickshell.execDetached(["wl-copy", "--", text]);
            else if (what === "edit") {
                input.text = session.lastUserText();
                input.cursorPosition = input.text.length;
                input.forceActiveFocus();
            }
        }
        // "+" asks once more when Prefs.confirmNewChat is on
        property bool newChatArmed: false
        Timer { id: newChatDisarm; interval: 3000; onTriggered: win.newChatArmed = false }
        function requestNewChat() {
            if (Prefs.confirmNewChat && !win.newChatArmed && session.messages.count > 0) {
                win.newChatArmed = true;
                newChatDisarm.restart();
                return;
            }
            win.newChatArmed = false;
            session.newChat();
            composer.focusInput();
        }

        function modelLabel() {
            let info = session.currentModelInfo;
            let name = info && info.value !== "default" ? info.displayName
                     : (session.model || "Модель").replace(/^claude-/, "").replace(/-(\d+)-(\d+)$/, " $1.$2");
            const efforts = { low: "низк.", medium: "сред.", high: "выс.", xhigh: "оч. выс.", max: "макс." };
            return session.effort !== "" ? name + " · " + (efforts[session.effort] || session.effort) : name;
        }
        function shortDir(p) {
            let home = Quickshell.env("HOME");
            return p.startsWith(home) ? "~" + p.substring(home.length) : p;
        }

        // ── background glow that breathes while Claude works ──
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -height * 0.6
            width: parent.width * 1.2
            height: parent.height * 0.9
            radius: height / 2
            color: Theme.accent
            opacity: session.busy ? 0.07 + 0.04 * glowPulse.v : 0.035
            Behavior on opacity { NumberAnimation { duration: 600 } }
            QtObject { id: glowPulse; property real v: 0 }
            SequentialAnimation {
                running: session.busy
                loops: Animation.Infinite
                NumberAnimation { target: glowPulse; property: "v"; to: 1; duration: 1400; easing.type: Easing.InOutSine }
                NumberAnimation { target: glowPulse; property: "v"; to: 0; duration: 1400; easing.type: Easing.InOutSine }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // ── header ─────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Star { width: 24; height: 24; active: session.busy }

                Text {
                    text: "Claude"
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.bold: true
                    color: Theme.text
                }

                // working folder; tap to change
                Rectangle {
                    id: dirChip
                    property bool editing: false
                    Layout.fillWidth: true
                    Layout.minimumWidth: 36
                    Layout.maximumWidth: Math.min(dirLabel.implicitWidth + 20, 240)
                    implicitHeight: 28
                    radius: 14
                    color: dirMouse.containsMouse || editing ? Theme.cardHi : Theme.card
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        id: dirLabel
                        visible: !dirChip.editing
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: "󰉋  " + win.shortDir(session.workDir)
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.sub
                        elide: Text.ElideMiddle
                    }
                    MouseArea {
                        id: dirMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        visible: !dirChip.editing
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dirChip.editing = true;
                            dirInput.text = win.shortDir(session.workDir);
                            dirInput.forceActiveFocus();
                            dirInput.selectAll();
                        }
                    }
                    TextInput {
                        id: dirInput
                        visible: dirChip.editing
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.text
                        selectionColor: Theme.accent
                        clip: true
                        onAccepted: {
                            let p = text.trim().replace(/^~/, Quickshell.env("HOME"));
                            dirChip.editing = false;
                            if (p !== "" && p !== session.workDir) session.newChat(p);
                            composer.focusInput();
                        }
                        Keys.onEscapePressed: { dirChip.editing = false; composer.focusInput(); }
                        onActiveFocusChanged: if (!activeFocus) dirChip.editing = false
                    }
                }

                Item { Layout.fillWidth: true }

                // how full the conversation context is (last API call)
                Text {
                    visible: session.contextUsed >= 0 && win.width > 420
                    text: "󰍛 " + Math.round(session.contextUsed * 100) + "%"
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: session.contextUsed > 0.85 ? Theme.error : session.contextUsed > 0.6 ? Theme.accent : Theme.dim
                    HoverHandler { id: ctxHover }
                    ToolTip.visible: ctxHover.hovered
                    ToolTip.text: "Контекст заполнен на " + Math.round(session.contextUsed * 100) + "% из "
                        + Math.round(session.contextWindow / 1000) + "k токенов. Ближе к 100% Claude сожмёт историю — или начни новый чат"
                }

                Text {
                    visible: Prefs.showCost && session.totalCost > 0 && win.width > 420
                    text: "$" + session.totalCost.toFixed(2)
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.dim
                }

                PillButton {
                    id: modelBtn
                    implicitHeight: 28
                    icon: "󰧑"
                    label: win.width < 560 ? "" : win.modelLabel()
                    active: modelMenu.visible
                    onClicked: modelMenu.visible ? modelMenu.close() : modelMenu.open()
                }

                PillButton {
                    implicitHeight: 28
                    icon: win.modeInfo(session.permissionMode).icon
                    label: win.width < 560 ? "" : win.modeInfo(session.permissionMode).label
                    danger: win.modeInfo(session.permissionMode).danger === true
                    active: session.permissionMode !== "default" && !danger
                    onClicked: win.cycleMode()
                }

                PillButton {
                    implicitHeight: 28
                    implicitWidth: 28
                    icon: "󰘦"
                    active: skillsPage.shown
                    onClicked: skillsPage.shown ? skillsPage.close() : skillsPage.open()
                }

                PillButton {
                    implicitHeight: 28
                    implicitWidth: 28
                    icon: "󰋚"
                    active: historyPage.shown
                    onClicked: historyPage.shown ? historyPage.close() : historyPage.open()
                }

                PillButton {
                    implicitHeight: 28
                    icon: win.newChatArmed ? "󰄬" : "󰐕"
                    label: win.newChatArmed ? "Точно?" : ""
                    active: win.newChatArmed
                    implicitWidth: win.newChatArmed ? implicitHeight * 2.6 : implicitHeight
                    onClicked: win.requestNewChat()
                }

                PillButton {
                    implicitHeight: 28
                    implicitWidth: 28
                    icon: "󰒓"
                    active: settingsPage.shown
                    onClicked: settingsPage.shown ? settingsPage.close() : settingsPage.open()
                }
            }

            // ── recent chats as tabs (one CLI process; tapping resumes that chat) ──
            Flickable {
                id: tabsRow
                Layout.fillWidth: true
                implicitHeight: 28
                visible: Prefs.recentTabs && (recentChats.list.length > 1 || changesPage.count > 0)
                contentWidth: tabsInner.implicitWidth
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: tabsInner
                    spacing: 6
                    Repeater {
                        model: recentChats.list.slice(0, 6)
                        Rectangle {
                            required property var modelData
                            readonly property bool current: modelData.id === session.sessionId
                            width: Math.min(tabText.implicitWidth + 22, 170)
                            height: 26
                            radius: 13
                            color: current ? Qt.alpha(Theme.accent, 0.22) : tabMouse.containsMouse ? Theme.cardHi : Theme.card
                            border.color: current ? Qt.alpha(Theme.accent, 0.7) : "transparent"
                            Text {
                                id: tabText
                                anchors.fill: parent
                                anchors.leftMargin: 11
                                anchors.rightMargin: 11
                                verticalAlignment: Text.AlignVCenter
                                text: modelData.title
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.bold: parent.current
                                color: parent.current ? Theme.text : Theme.sub
                            }
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!parent.current && !session.busy) session.resume(parent.modelData.id)
                            }
                        }
                    }
                    PillButton {
                        visible: changesPage.count > 0
                        implicitHeight: 26
                        pixelSize: 11
                        icon: "󰦒"
                        label: "Изменения: " + changesPage.count
                        onClicked: changesPage.open()
                    }
                }
            }
            QtObject {
                id: recentChats
                property var list: []
            }
            Process {
                id: recentProc
                command: ["python3", "-I", Qt.resolvedUrl("chats.py").toString().replace(/^file:\/\//, ""), session.workDir]
                stdout: StdioCollector { onStreamFinished: { try { recentChats.list = JSON.parse(this.text); } catch (e) {} } }
            }
            // refresh the tabs when the chat changes or an answer finishes
            Timer { id: recentRefresh; interval: 800; onTriggered: { recentProc.running = false; recentProc.running = true; } }
            Connections {
                target: session
                function onSessionIdChanged() { recentRefresh.restart(); }
                function onBusyChanged() { if (!session.busy) recentRefresh.restart(); }
            }
            Component.onCompleted: recentRefresh.restart()

            // ── conversation ───────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── Ctrl+F: find in this chat ──
                Rectangle {
                    id: searchBar
                    property bool shown: false
                    property var matches: []
                    property int pos: 0
                    function openSearch() { shown = true; searchInput.forceActiveFocus(); searchInput.selectAll(); }
                    function closeSearch() { shown = false; chat.hl = -1; composer.focusInput(); }
                    function update() {
                        let q = searchInput.text.trim().toLowerCase(), m = [];
                        if (q !== "")
                            for (let i = 0; i < session.messages.count; i++) {
                                let r = session.messages.get(i);
                                if ((r.text + " " + r.summary).toLowerCase().indexOf(q) >= 0) m.push(i);
                            }
                        matches = m;
                        pos = m.length - 1;           // start from the newest match
                        go(0);
                    }
                    function go(step) {
                        if (matches.length === 0) { chat.hl = -1; return; }
                        pos = (pos + step + matches.length) % matches.length;
                        chat.hl = matches[pos];
                        chat.stick = false;
                        chat.positionViewAtIndex(chat.hl, ListView.Center);
                    }
                    z: 5
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    width: Math.min(parent.width - 12, 340)
                    height: 34
                    radius: 17
                    color: Theme.card
                    border.color: Qt.alpha(Theme.accent, 0.6)
                    visible: shown
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 6
                        spacing: 6
                        Text { text: "󰍉"; font.family: Theme.font; font.pixelSize: 14; color: Theme.dim }
                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.text
                            selectionColor: Theme.accent
                            clip: true
                            onTextChanged: searchBar.update()
                            Keys.onReturnPressed: (ev) => searchBar.go((ev.modifiers & Qt.ShiftModifier) ? 1 : -1)
                            Keys.onEscapePressed: searchBar.closeSearch()
                        }
                        Text {
                            text: searchInput.text === "" ? "" : searchBar.matches.length === 0 ? "нет" : (searchBar.pos + 1) + "/" + searchBar.matches.length
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.dim
                        }
                        PillButton { implicitHeight: 24; icon: "󰁝"; onClicked: searchBar.go(-1) }
                        PillButton { implicitHeight: 24; icon: "󰁅"; onClicked: searchBar.go(1) }
                        PillButton { implicitHeight: 24; icon: "󰅖"; onClicked: searchBar.closeSearch() }
                    }
                }

                ListView {
                    id: chat
                    // follow new messages only while the user is at the bottom
                    property bool stick: true
                    function nearEnd() { return contentHeight - (contentY + height) < 60; }
                    onMovementEnded: stick = nearEnd()
                    onFlickEnded: stick = nearEnd()
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    model: session.messages
                    bottomMargin: permCard.shown ? Math.max(0, permCard.height - composer.height) + 4 : 0
                    Behavior on bottomMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    onBottomMarginChanged: if (permCard.shown) positionViewAtEnd()
                    boundsBehavior: Flickable.StopAtBounds
                    // first visible match of the Ctrl+F search
                    property int hl: -1
                    delegate: ChatItem {
                        row: model
                        isLast: index === chat.count - 1
                        busy: session.busy
                        highlighted: index === chat.hl
                        onAction: (what) => win.replyAction(what, model.text)
                    }
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.alpha(Theme.sub, 0.4) }
                    }

                    footer: Item {
                        width: chat.width
                        height: session.thinking && session.busy && !session.currentPermission ? 34 : 6
                        Behavior on height { NumberAnimation { duration: 200 } }

                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            opacity: parent.height > 20 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Star { width: 14; height: 14; active: parent.opacity > 0 }
                            Shimmer { text: thinkingLine.verb + "…"; pixelSize: 13 }
                            Text {
                                text: thinkingLine.seconds > 0 ? "  " + thinkingLine.seconds + " с" : ""
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.dim
                            }
                        }
                    }
                }

                // back to the newest message
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    width: 36; height: 36; radius: 18
                    color: downMouse.containsMouse ? Theme.cardHi : Theme.card
                    border.color: Theme.border
                    opacity: chat.stick ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Text { anchors.centerIn: parent; text: "󰁅"; font.family: Theme.font; font.pixelSize: 18; color: Theme.accent }
                    MouseArea {
                        id: downMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { chat.stick = true; chat.positionViewAtEnd(); }
                    }
                }

                // empty state
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 20, 520)
                    spacing: 14
                    opacity: session.messages.count === 0 ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    Star {
                        Layout.alignment: Qt.AlignHCenter
                        width: 56; height: 56
                        active: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Чем займёмся?"
                        font.family: Theme.font
                        font.pixelSize: 22
                        font.bold: true
                        color: Theme.text
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Claude Code в папке " + win.shortDir(session.workDir)
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.dim
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        Repeater {
                            model: [
                                { i: "󰍛", t: "Как себя чувствует мой Pi?" },
                                { i: "󰉋", t: "Что лежит в этой папке?" },
                                { i: "󰗚", t: "Напиши скрипт для бэкапа" }
                            ]
                            PillButton {
                                icon: modelData.i
                                label: modelData.t
                                onClicked: session.send(modelData.t)
                            }
                        }
                    }
                }
            }

            // ── work was cut off (power loss / crash) ──
            Rectangle {
                Layout.fillWidth: true
                visible: session.interrupted && !session.busy
                implicitHeight: intRow.implicitHeight + 16
                radius: Theme.radius
                color: Qt.alpha(Theme.accent, 0.12)
                border.color: Qt.alpha(Theme.accent, 0.5)
                RowLayout {
                    id: intRow
                    anchors.fill: parent
                    anchors.margins: 8
                    anchors.leftMargin: 12
                    spacing: 8
                    Text { text: "󱐋"; font.family: Theme.font; font.pixelSize: 18; color: Theme.accent }
                    Text {
                        Layout.fillWidth: true
                        text: "Работа прервалась — похоже, пропадало питание. Claude может продолжить с того же места."
                        wrapMode: Text.Wrap
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.text
                    }
                    PillButton {
                        implicitHeight: 32
                        icon: "󰐊"
                        label: "Продолжить"
                        primary: true
                        onClicked: { chat.stick = true; session.continueWork(); }
                    }
                    PillButton {
                        implicitHeight: 32
                        icon: "󰅖"
                        onClicked: session.interrupted = false
                    }
                }
            }

            // ── messages waiting for Claude to finish ──
            Repeater {
                model: session.queue
                Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 10
                    color: Theme.card
                    border.color: Theme.border
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 6
                        Text { text: "󰔟"; font.family: Theme.font; font.pixelSize: 13; color: Theme.dim }
                        Text {
                            Layout.fillWidth: true
                            text: "В очереди: " + (modelData.text.trim() !== "" ? modelData.text.replace(/\s+/g, " ") : "изображение")
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.sub
                        }
                        Text {
                            text: "󰅖"
                            font.family: Theme.font
                            font.pixelSize: 13
                            color: Theme.dim
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: session.dequeue(index) }
                        }
                    }
                }
            }

            // ── quick prompts: saved templates, then what the user sends most ──
            Flow {
                id: quickPrompts
                Layout.fillWidth: true
                spacing: 6
                visible: Prefs.quickPrompts && input.text === "" && !session.busy && !session.interrupted
                         && session.messages.count > 0 && composer.attachments.length === 0
                // [{label, text, tpl}]
                readonly property var items: {
                    let out = [], seen = {};
                    let add = (label, text, tpl) => {
                        let key = text.toLowerCase().replace(/[^a-zа-яё]/g, "");
                        if (seen[key] || out.length >= 5) return;
                        seen[key] = true;
                        out.push({ label: label, text: text, tpl: tpl });
                    };
                    for (let t of Prefs.templates) add(t.name, t.text, true);
                    let freq = {};
                    for (let t of session.sentHistory) {
                        let k = t.trim();
                        if (k.length > 0 && k.length <= 40) freq[k] = (freq[k] || 0) + 1;
                    }
                    let mine = Object.keys(freq).filter(k => freq[k] >= 2).sort((a, b) => freq[b] - freq[a]);
                    for (let t of mine.concat(["Продолжи", "Что ещё можно улучшить?"])) add(t, t, false);
                    return out;
                }
                Repeater {
                    model: quickPrompts.items
                    PillButton {
                        required property var modelData
                        implicitHeight: 28
                        pixelSize: 11
                        icon: modelData.tpl ? "󰆓" : ""
                        label: modelData.label
                        onClicked: { chat.stick = true; session.send(modelData.text); }
                    }
                }
            }

            // ── attachments waiting to be sent ──
            Flow {
                Layout.fillWidth: true
                visible: composer.attachments.length > 0
                spacing: 6
                Repeater {
                    model: composer.attachments
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: 64; height: 48
                        radius: 8
                        color: Theme.card
                        border.color: Theme.border
                        clip: true
                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: "file://" + parent.modelData.path
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 2
                            width: 18; height: 18; radius: 9
                            color: Qt.alpha(Theme.bg, 0.85)
                            Text { anchors.centerIn: parent; text: "󰅖"; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                onClicked: { let a = composer.attachments.slice(); a.splice(parent.parent.index, 1); composer.attachments = a; }
                            }
                        }
                    }
                }
            }

            // ── composer ───────────────────────────────
            Item {
                id: composer
                Layout.fillWidth: true
                implicitHeight: Math.max(46, Math.min(input.contentHeight + 22, 120))
                Behavior on implicitHeight { NumberAnimation { duration: 140 } }

                function focusInput() { input.forceActiveFocus(); }

                // images to send with the next message: [{path, media, data}]
                property var attachments: []
                readonly property bool canSend: input.text.trim() !== "" || attachments.length > 0
                function submit() {
                    if (!canSend) return;
                    if (input.text.trim() === "/skills" && attachments.length === 0) { input.text = ""; skillsPage.open(); return; }
                    let imgs = attachments.map(a => ({ media: a.media, data: a.data }));
                    chat.stick = true;
                    if (session.busy) session.enqueue(input.text, imgs);
                    else session.send(input.text, imgs);
                    input.text = "";
                    attachments = [];
                }
                // image in the clipboard → attachment, otherwise a normal text paste
                Process {
                    id: pasteProc
                    command: ["bash", "-c", "if wl-paste --list-types 2>/dev/null | grep -qx 'image/png'; then "
                        + "mkdir -p /tmp/claude-desk; f=/tmp/claude-desk/paste-$(date +%s%N).png; wl-paste --type image/png > \"$f\" && echo \"$f\"; "
                        + "else echo TEXT; fi"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let out = this.text.trim();
                            if (out === "TEXT" || out === "") input.paste();
                            else composer.attachImage(out);
                        }
                    }
                }
                function attachImage(path) {
                    let ext = path.split(".").pop().toLowerCase();
                    let media = ext === "jpg" || ext === "jpeg" ? "image/jpeg" : ext === "webp" ? "image/webp" : ext === "gif" ? "image/gif" : "image/png";
                    encoder.queue = encoder.queue.concat([{ path: path, media: media }]);
                    if (!encoder.running) encoder.next();
                }
                // let the user pick a region, then attach the shot. On sway the window
                // hides in the scratchpad meanwhile; elsewhere (KWin) Spectacle does it.
                function takeScreenshot() { shooter.running = true; }
                Process {
                    id: shooter
                    command: ["bash", "-c",
                        "w=$PPID; mkdir -p /tmp/claude-desk; f=/tmp/claude-desk/shot-$(date +%s%N).png; "
                        + "if [ -n \"$SWAYSOCK\" ]; then "
                        + "swaymsg \"[pid=$w] move scratchpad\" >/dev/null; sleep 0.25; g=$(slurp); r=$?; "
                        + "[ $r = 0 ] && grim -g \"$g\" \"$f\"; "
                        + "swaymsg \"[pid=$w] scratchpad show, floating disable, focus\" >/dev/null; "
                        + "else spectacle -b -r -n -o \"$f\" >/dev/null 2>&1; r=$?; fi; "
                        + "[ $r = 0 ] && [ -f \"$f\" ] && echo \"$f\""]
                    stdout: StdioCollector { onStreamFinished: { let f = this.text.trim(); if (f !== "") composer.attachImage(f); } }
                    onExited: composer.focusInput()
                }
                Process {
                    id: encoder
                    property var queue: []
                    property var cur: null
                    function next() {
                        if (queue.length === 0) return;
                        cur = queue[0];
                        queue = queue.slice(1);
                        command = ["base64", "-w0", cur.path];
                        running = true;
                    }
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let d = this.text.trim();
                            if (d !== "" && encoder.cur)
                                composer.attachments = composer.attachments.concat([{ path: encoder.cur.path, media: encoder.cur.media, data: d }]);
                        }
                    }
                    onExited: next()
                }
                FileDialog {
                    id: fileDialog
                    title: "Прикрепить файл"
                    currentFolder: "file://" + session.workDir
                    onAccepted: {
                        let path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
                        if (/\.(png|jpe?g|webp|gif)$/i.test(path)) composer.attachImage(path);
                        else {
                            let ins = (input.text === "" || input.text.endsWith(" ") ? "" : " ") + "файл " + path + " ";
                            input.insert(input.cursorPosition, ins);
                        }
                        composer.focusInput();
                    }
                }

                // "/name" typed with no space yet → show matching commands/skills
                property string dismissedText: ""
                readonly property bool slashTyping: /^\/\S*$/.test(input.text) && input.text !== dismissedText
                function pickCommand(cmd, sendNow) {
                    if (cmd.local && cmd.name === "skills") { input.text = ""; skillsPage.open(); return; }
                    if (sendNow && !session.busy && (cmd.argumentHint || "") === "") {
                        session.send("/" + cmd.name);
                        input.text = "";
                    } else {
                        input.text = "/" + cmd.name + " ";
                        input.cursorPosition = input.text.length;
                    }
                    input.forceActiveFocus();
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius + 4
                    color: Theme.card
                    border.width: 1.5
                    border.color: input.activeFocus ? Qt.alpha(Theme.accent, 0.7) : Theme.border
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    ScrollView {
                        id: inputScroll
                        anchors.left: parent.left
                        anchors.right: shotBtn.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 12
                        anchors.rightMargin: 6

                        TextArea {
                            id: input
                            wrapMode: TextArea.Wrap
                            placeholderText: session.busy ? "Claude работает… Можно писать — сообщение встанет в очередь" : "Напиши Claude…"
                            placeholderTextColor: Theme.dim
                            color: Theme.text
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.bg
                            font.family: Theme.font
                            font.pixelSize: Math.round(13 * Prefs.textScale)
                            topPadding: 13
                            bottomPadding: 9
                            leftPadding: 0
                            background: null
                            focus: true

                            Keys.onReturnPressed: function(ev) {
                                if (cmdMenu.shown) { composer.pickCommand(cmdMenu.items[cmdMenu.current], true); return; }
                                let newline = Prefs.enterSends ? (ev.modifiers & Qt.ShiftModifier) : !(ev.modifiers & Qt.ControlModifier);
                                if (newline) { ev.accepted = false; return; }
                                composer.submit();
                            }
                            Keys.onPressed: function(ev) {
                                if (ev.key === Qt.Key_V && (ev.modifiers & Qt.ControlModifier) && !(ev.modifiers & Qt.ShiftModifier)) {
                                    pasteProc.running = true;
                                    ev.accepted = true;
                                } else {
                                    ev.accepted = false;
                                }
                            }
                            Keys.onTabPressed: function(ev) {
                                if (cmdMenu.shown) composer.pickCommand(cmdMenu.items[cmdMenu.current], false);
                                else ev.accepted = false;
                            }
                            // ↑/↓ in an empty box (or while browsing) recall earlier messages
                            property int histIdx: -1
                            onTextChanged: if (histIdx >= 0 && text !== session.sentHistory[histIdx]) histIdx = -1
                            function recall(i) {
                                histIdx = i;
                                text = i >= 0 ? session.sentHistory[i] : "";
                                cursorPosition = text.length;
                            }
                            Keys.onUpPressed: function(ev) {
                                if (cmdMenu.shown) { cmdMenu.move(-1); return; }
                                let h = session.sentHistory;
                                if (h.length > 0 && (text === "" || histIdx >= 0)) recall(histIdx < 0 ? h.length - 1 : Math.max(0, histIdx - 1));
                                else ev.accepted = false;
                            }
                            Keys.onDownPressed: function(ev) {
                                if (cmdMenu.shown) { cmdMenu.move(1); return; }
                                if (histIdx >= 0) recall(histIdx + 1 < session.sentHistory.length ? histIdx + 1 : -1);
                                else ev.accepted = false;
                            }
                            Keys.onEscapePressed: {
                                if (cmdMenu.shown) composer.dismissedText = input.text;
                                else session.interrupt();
                            }
                        }
                    }

                    // screenshot of a screen region → attached image
                    IconBtn {
                        id: shotBtn
                        anchors.right: fileBtn.left
                        anchors.verticalCenter: sendBtn.verticalCenter
                        text: "󰹑"
                        onClicked: composer.takeScreenshot()
                    }
                    // file: images are attached, other files go in as a path
                    IconBtn {
                        id: fileBtn
                        anchors.right: skillBtn.left
                        anchors.verticalCenter: sendBtn.verticalCenter
                        text: "󰏢"
                        onClicked: fileDialog.open()
                    }

                    // skills / commands browser: starts a "/" query in the input
                    Text {
                        id: skillBtn
                        anchors.right: sendBtn.left
                        anchors.verticalCenter: sendBtn.verticalCenter
                        anchors.rightMargin: 4
                        width: 30; height: 30
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "󰘦"
                        font.family: Theme.font
                        font.pixelSize: 17
                        color: cmdMenu.shown || skillMouse.containsMouse ? Theme.accent : Theme.dim
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            id: skillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (cmdMenu.shown) { composer.dismissedText = input.text; return; }
                                composer.dismissedText = "";
                                if (!/^\/\S*$/.test(input.text)) input.text = "/";
                                input.cursorPosition = input.text.length;
                                input.forceActiveFocus();
                            }
                        }
                    }

                    // send ↔ stop morph; while busy with text typed it queues instead
                    Rectangle {
                        id: sendBtn
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 7
                        width: 32; height: 32
                        readonly property bool canSend: composer.canSend
                        readonly property bool stopMode: session.busy && !canSend
                        radius: stopMode ? 9 : 16
                        Behavior on radius { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        color: stopMode ? Theme.cardHi : canSend ? Theme.accent : Qt.alpha(Theme.accent, 0.3)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        scale: sendMouse.pressed ? 0.88 : 1
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 3 } }

                        Text {
                            anchors.centerIn: parent
                            text: sendBtn.stopMode ? "󰓛" : session.busy ? "󰔟" : "󰁝"
                            font.family: Theme.font
                            font.pixelSize: 16
                            color: sendBtn.stopMode ? Theme.accent : Theme.bg
                            rotation: sendBtn.stopMode ? 90 : 0
                            Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                        }
                        MouseArea {
                            id: sendMouse
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (sendBtn.stopMode) { session.interrupt(); return; }
                                composer.submit();
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        CommandMenu {
            id: cmdMenu
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            anchors.bottomMargin: 10 + composer.height + 6
            open: composer.slashTyping && !permCard.shown
            items: open ? session.matchCommands(input.text.substring(1)) : []
            onPicked: function(cmd) { composer.pickCommand(cmd, true); }
        }

        ChangesPage {
            id: changesPage
            width: parent.width
            height: parent.height
            ses: session
            onShownChanged: if (!shown) composer.focusInput()
        }

        HistoryPage {
            id: historyPage
            width: parent.width
            height: parent.height
            ses: session
            onShownChanged: if (!shown) composer.focusInput()
        }

        SkillsPage {
            id: skillsPage
            width: parent.width
            height: parent.height
            ses: session
            onUseRequested: function(text) { input.text = text; input.cursorPosition = text.length; }
            onShownChanged: if (!shown) composer.focusInput()
        }

        SettingsPage {
            id: settingsPage
            width: parent.width
            height: parent.height
            ses: session
            modes: win.modes
            modelText: win.modelLabel()
            onModelMenuRequested: modelMenu.open()
            onShownChanged: if (!shown) composer.focusInput()
        }

        ModelMenu {
            id: modelMenu
            ses: session
            parent: Overlay.overlay
            x: Math.max(10, win.width - width - 10)
            y: 46
            width: Math.min(implicitWidth, win.width - 20)
            height: Math.min(implicitHeight, win.height - 56)
        }

        PermissionCard {
            id: permCard
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            request: session.currentPermission
            mode: session.permissionMode
            onAnswered: function(decision) { session.answerPermission(decision); }
        }

        // ── thinking line state ──
        QtObject {
            id: thinkingLine
            readonly property var verbs: ["Размышляю", "Колдую", "Соображаю", "Вникаю", "Шуршу", "Сочиняю", "Варю мысли", "Прикидываю", "Мурлычу над кодом", "Распутываю"]
            property string verb: verbs[0]
            property int seconds: 0
        }
        Timer {
            interval: 1000
            repeat: true
            running: session.busy
            onRunningChanged: if (running) { thinkingLine.seconds = 0; thinkingLine.verb = thinkingLine.verbs[Math.floor(Math.random() * thinkingLine.verbs.length)]; }
            onTriggered: {
                thinkingLine.seconds++;
                if (thinkingLine.seconds % 6 === 0)
                    thinkingLine.verb = thinkingLine.verbs[Math.floor(Math.random() * thinkingLine.verbs.length)];
            }
        }
    }
}
