import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Full-window settings page that slides in over the chat.
Rectangle {
    id: page
    required property var ses
    property string modelText: ""
    property var modes: []
    property bool shown: false
    signal modelMenuRequested()

    // ── always-allow rules ──
    property var rules: []
    property bool rulesDirty: false
    function _readSettings() {
        try { return JSON.parse(rulesFile.text()) || {}; } catch (e) { return {}; }
    }
    function _writeRules(list) {
        let o = _readSettings();
        if (!o.permissions) o.permissions = {};
        o.permissions.allow = list;
        Quickshell.execDetached(["mkdir", "-p", page.ses.workDir + "/.claude"]);
        rulesFile.setText(JSON.stringify(o, null, 2) + "\n");
        page.rules = list;
        page.rulesDirty = true;
    }
    function isOneOff(r) { return /^Bash\(/.test(r) && r.indexOf("*") < 0; }
    function addRule(r) {
        r = r.trim();
        if (r === "" || page.rules.indexOf(r) >= 0) return;
        _writeRules(page.rules.concat([r]));
    }
    function removeRule(i) {
        let l = page.rules.slice();
        l.splice(i, 1);
        _writeRules(l);
    }

    function open() {
        dirField.text = shortDir(ses.workDir);
        promptField.text = Prefs.appendPrompt;
        page.shown = true;
        page.forceActiveFocus();
        versionProc.running = true;
    }
    function close() { page.shown = false; }

    function shortDir(p) {
        let home = Quickshell.env("HOME");
        return p.startsWith(home) ? "~" + p.substring(home.length) : p;
    }

    color: Theme.bg
    visible: x < parent.width
    x: shown ? 0 : parent.width
    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    focus: shown
    Keys.onEscapePressed: page.close()

    // Swallow clicks so nothing underneath reacts
    MouseArea { anchors.fill: parent; onClicked: page.forceActiveFocus() }

    component SectionTitle: Text {
        Layout.topMargin: 10
        Layout.leftMargin: 4
        font.family: Theme.font
        font.pixelSize: 11
        font.bold: true
        font.capitalization: Font.AllUppercase
        color: Theme.accent
    }

    // A setting: title + hint on the left, control (children) on the right
    component SRow: Rectangle {
        id: srow
        property string title: ""
        property string hint: ""
        default property alias control: slot.data
        Layout.fillWidth: true
        implicitHeight: Math.max(texts.implicitHeight, slot.childrenRect.height) + 18
        radius: Theme.radius
        color: Theme.card

        ColumnLayout {
            id: texts
            anchors.left: parent.left
            anchors.right: slot.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: srow.title
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.text
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: srow.hint !== ""
                text: srow.hint
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.dim
                wrapMode: Text.Wrap
            }
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

    // Single-line text box in the app's style
    component Field: Rectangle {
        property alias text: ti.text
        property alias input: ti
        property string placeholder: ""
        signal accepted()
        signal editingFinished()       // Enter or leaving the field
        implicitHeight: 32
        radius: 10
        color: Theme.panel
        border.color: ti.activeFocus ? Qt.alpha(Theme.accent, 0.7) : Theme.border
        Behavior on border.color { ColorAnimation { duration: 150 } }
        TextInput {
            id: ti
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            selectByMouse: true
            clip: true
            onAccepted: parent.accepted()
            onEditingFinished: parent.editingFinished()
        }
        Text {
            anchors.fill: ti
            verticalAlignment: Text.AlignVCenter
            visible: ti.text === "" && !ti.activeFocus
            text: parent.placeholder
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.dim
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        // ── header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PillButton {
                implicitHeight: 28
                icon: "󰁍"
                onClicked: page.close()
            }
            Text {
                Layout.fillWidth: true
                text: "Настройки"
                font.family: Theme.font
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
            }
            Text {
                text: "Esc — назад"
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.dim
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight + 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.alpha(Theme.sub, 0.4) }
            }

            ColumnLayout {
                id: col
                width: flick.width - 8
                spacing: 6

                // ── conversation ──
                SectionTitle { text: "Разговор"; Layout.topMargin: 2 }

                SRow {
                    title: "Рабочая папка"
                    hint: "Смена папки начинает новый чат"
                    RowLayout {
                        spacing: 6
                        Field {
                            id: dirField
                            implicitWidth: Math.min(260, page.width * 0.4)
                            onAccepted: dirApply.clicked()
                        }
                        PillButton {
                            id: dirApply
                            implicitHeight: 30
                            icon: "󰄬"
                            onClicked: {
                                let p = dirField.text.trim().replace(/^~/, Quickshell.env("HOME"));
                                if (p !== "" && p !== page.ses.workDir) page.ses.newChat(p);
                                dirField.text = page.shortDir(page.ses.workDir);
                            }
                        }
                    }
                }

                // permission mode: full-width card, five modes don't fit a row
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: modeCol.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.card
                    ColumnLayout {
                        id: modeCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        anchors.leftMargin: 12
                        spacing: 8
                        Text {
                            text: "Разрешения"
                            font.family: Theme.font
                            font.pixelSize: 13
                            color: Theme.text
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: page.modes
                                PillButton {
                                    required property var modelData
                                    implicitHeight: 28
                                    icon: modelData.icon
                                    label: modelData.label
                                    danger: modelData.danger === true && !active
                                    active: page.ses.permissionMode === modelData.id
                                    onClicked: page.ses.setMode(modelData.id)
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: {
                                for (let m of page.modes) if (m.id === page.ses.permissionMode) return m.hint;
                                return "";
                            }
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: page.ses.permissionMode === "bypassPermissions" ? Theme.error : Theme.dim
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // always-allowed rules from <workDir>/.claude/settings.local.json
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: rulesCol.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.card
                    ColumnLayout {
                        id: rulesCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        anchors.leftMargin: 12
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: "Всегда разрешено"
                                font.family: Theme.font
                                font.pixelSize: 13
                                color: Theme.text
                            }
                            // exact one-off commands the "Всегда" button saved; they never match again
                            PillButton {
                                readonly property int count: page.rules.filter(r => page.isOneOff(r)).length
                                visible: count > 0
                                implicitHeight: 24
                                pixelSize: 11
                                icon: "󰃢"
                                label: "Убрать разовые (" + count + ")"
                                onClicked: page._writeRules(page.rules.filter(r => !page.isOneOff(r)))
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Эти действия Claude делает без вопроса. Кнопка «Всегда» на запросе добавляет сюда правило. Файл: "
                                + page.shortDir(rulesFile.path)
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.dim
                            wrapMode: Text.Wrap
                        }
                        Text {
                            visible: page.rules.length === 0
                            text: "Пока пусто"
                            font.family: Theme.font
                            font.pixelSize: 12
                            color: Theme.sub
                        }
                        Repeater {
                            model: page.rules
                            Rectangle {
                                id: ruleRow
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: 8
                                color: ruleHover.hovered ? Theme.cardHi : Theme.panel
                                HoverHandler { id: ruleHover }
                                Text {
                                    anchors.left: parent.left
                                    anchors.right: delBtn.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 6
                                    text: ruleRow.modelData
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    color: Theme.sub
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: delBtn
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅖"
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    color: delMouse.containsMouse ? Theme.error : Theme.dim
                                    MouseArea {
                                        id: delMouse
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: page.removeRule(ruleRow.index)
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field {
                                id: ruleField
                                Layout.fillWidth: true
                                placeholder: "Bash(git *)  ·  Edit  ·  WebFetch(domain:github.com)"
                                onAccepted: addRuleBtn.clicked()
                            }
                            PillButton {
                                id: addRuleBtn
                                implicitHeight: 30
                                icon: "󰐕"
                                label: "Добавить"
                                onClicked: { page.addRule(ruleField.text); ruleField.text = ""; }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: ["Bash(ls *)", "Bash(cat *)", "Bash(grep *)", "Bash(find *)", "Bash(git *)", "Bash(quickshell *)", "WebSearch"]
                                PillButton {
                                    required property var modelData
                                    visible: page.rules.indexOf(modelData) < 0
                                    implicitHeight: 24
                                    pixelSize: 11
                                    label: "+ " + modelData
                                    onClicked: page.addRule(modelData)
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: page.rulesDirty
                            Text {
                                Layout.fillWidth: true
                                text: "Правила применятся после перезапуска Claude Code"
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.accent
                                wrapMode: Text.Wrap
                            }
                            PillButton {
                                implicitHeight: 28
                                label: "Перезапустить"
                                primary: true
                                opacity: page.ses.busy ? 0.5 : 1
                                onClicked: if (!page.ses.busy) { page.ses.restart(); page.rulesDirty = false; }
                            }
                        }
                    }
                }

                SRow {
                    title: "Модель и глубина размышлений"
                    hint: page.modelText === "Модель" ? "По умолчанию" : page.modelText
                    PillButton {
                        implicitHeight: 28
                        icon: "󰧑"
                        label: "Выбрать"
                        onClicked: page.modelMenuRequested()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: promptCol.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.card
                    ColumnLayout {
                        id: promptCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        anchors.leftMargin: 12
                        spacing: 6
                        Text {
                            text: "Дополнительные инструкции"
                            font.family: Theme.font
                            font.pixelSize: 13
                            color: Theme.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Добавляются к системному промпту. Например: «отвечай кратко», «пиши комментарии по-русски»."
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.dim
                            wrapMode: Text.Wrap
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.max(60, Math.min(promptField.contentHeight + 16, 140))
                            radius: 10
                            color: Theme.panel
                            border.color: promptField.activeFocus ? Qt.alpha(Theme.accent, 0.7) : Theme.border
                            TextArea {
                                id: promptField
                                anchors.fill: parent
                                wrapMode: TextArea.Wrap
                                placeholderText: "Пусто"
                                placeholderTextColor: Theme.dim
                                color: Theme.text
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.bg
                                font.family: Theme.font
                                font.pixelSize: 12
                                background: null
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: page.ses.busy ? "Применится после ответа"
                                    : promptField.text.trim() !== Prefs.appendPrompt.trim() ? "Claude Code перезапустится, разговор сохранится" : ""
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.dim
                                wrapMode: Text.Wrap
                            }
                            PillButton {
                                implicitHeight: 28
                                label: "Применить"
                                primary: promptField.text.trim() !== Prefs.appendPrompt.trim()
                                opacity: page.ses.busy ? 0.5 : 1
                                onClicked: {
                                    if (page.ses.busy || promptField.text.trim() === Prefs.appendPrompt.trim()) return;
                                    Prefs.appendPrompt = promptField.text.trim();
                                    page.ses.restart();
                                }
                            }
                        }
                    }
                }

                // ── look ──
                SectionTitle { text: "Вид" }

                SRow {
                    title: "Размер текста в чате"
                    Row {
                        spacing: 6
                        Repeater {
                            model: [0.9, 1.0, 1.15, 1.3]
                            PillButton {
                                required property var modelData
                                implicitHeight: 28
                                label: Math.round(modelData * 100) + "%"
                                active: Math.abs(Prefs.textScale - modelData) < 0.01
                                onClicked: Prefs.textScale = modelData
                            }
                        }
                    }
                }

                SRow {
                    title: "Показывать вызовы инструментов"
                    hint: "Карточки Bash, Read, Edit… в ленте"
                    Toggle { checked: Prefs.showTools; onToggled: v => Prefs.showTools = v }
                }

                SRow {
                    title: "Показывать стоимость"
                    hint: "Сумма за текущий чат в шапке"
                    Toggle { checked: Prefs.showCost; onToggled: v => Prefs.showCost = v }
                }

                SRow {
                    title: "Enter отправляет сообщение"
                    hint: Prefs.enterSends ? "Новая строка — Shift+Enter" : "Отправка — Ctrl+Enter, Enter — новая строка"
                    Toggle { checked: Prefs.enterSends; onToggled: v => Prefs.enterSends = v }
                }

                // ── notifications ──
                SectionTitle { text: "Уведомления" }

                SRow {
                    title: "Уведомлять, когда окно в фоне"
                    hint: "Ответ готов или Claude ждёт разрешения"
                    Toggle { checked: Prefs.notify; onToggled: v => Prefs.notify = v }
                }

                SRow {
                    title: "Звук"
                    opacity: Prefs.notify ? 1 : 0.5
                    Toggle { checked: Prefs.sound; onToggled: v => Prefs.sound = v }
                }

                // ── spending ──
                SectionTitle { text: "Расходы" }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: costRow.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.card
                    RowLayout {
                        id: costRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        spacing: 8
                        Repeater {
                            model: [["Сегодня", 1], ["7 дней", 7], ["30 дней", 30], ["Всего", 0]]
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "$" + page.ses.costSince(modelData[1]).toFixed(2)
                                    font.family: Theme.font
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: modelData[1] === 1 ? Theme.accent : Theme.text
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData[0]
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    color: Theme.dim
                                }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: "Примерная стоимость по данным Claude Code, считается с " + (Object.keys(page.ses.costs).sort()[0] || "сегодня") + ". При подписке это условные деньги"
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.dim
                    wrapMode: Text.Wrap
                }

                // ── behaviour ──
                SectionTitle { text: "Поведение" }

                SRow {
                    title: "Продолжать самому после сбоя"
                    hint: "Если пропадало питание, через 4 секунды после запуска Claude сам продолжит работу"
                    Toggle { checked: Prefs.autoContinue; onToggled: v => Prefs.autoContinue = v }
                }
                SRow {
                    title: "Кнопки под ответом"
                    hint: "Заново · Изменить запрос · Продолжи · Копировать"
                    Toggle { checked: Prefs.replyActions; onToggled: v => Prefs.replyActions = v }
                }
                SRow {
                    title: "Быстрые фразы над полем ввода"
                    hint: "Шаблоны и твои частые сообщения"
                    Toggle { checked: Prefs.quickPrompts; onToggled: v => Prefs.quickPrompts = v }
                }
                SRow {
                    title: "Недавние чаты вкладками"
                    hint: "Строка под шапкой — переключение одним касанием"
                    Toggle { checked: Prefs.recentTabs; onToggled: v => Prefs.recentTabs = v }
                }
                SRow {
                    title: "Спрашивать перед новым чатом"
                    hint: "Кнопка «+» сработает со второго нажатия"
                    Toggle { checked: Prefs.confirmNewChat; onToggled: v => Prefs.confirmNewChat = v }
                }
                SRow {
                    title: "Папка для новых чатов"
                    hint: Prefs.defaultDir === "" ? "Пусто — новый чат в текущей папке" : "Новые чаты открываются здесь"
                    Field {
                        implicitWidth: Math.min(220, page.width * 0.35)
                        text: Prefs.defaultDir
                        placeholder: "~/claude"
                        onEditingFinished: Prefs.defaultDir = text.trim()
                    }
                }

                // ── prompt templates ──
                SectionTitle { text: "Шаблоны" }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: tplCol.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.card
                    ColumnLayout {
                        id: tplCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        anchors.leftMargin: 12
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: "Готовые запросы — кнопками над полем ввода (󰆓). Название короткое, текст любой."
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.dim
                        }
                        Repeater {
                            model: Prefs.templates
                            Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 30
                                radius: 8
                                color: Theme.panel
                                Text {
                                    anchors.left: parent.left
                                    anchors.right: tplDel.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 8
                                    text: "󰆓 " + modelData.name + "  ·  " + modelData.text
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    color: Theme.sub
                                }
                                Text {
                                    id: tplDel
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅖"
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    color: Theme.dim
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { let l = Prefs.templates.slice(); l.splice(index, 1); Prefs.templates = l; }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field { id: tplName; implicitWidth: 110; placeholder: "Название" }
                            Field { id: tplText; Layout.fillWidth: true; placeholder: "Текст запроса"; onAccepted: tplAdd.clicked() }
                            PillButton {
                                id: tplAdd
                                implicitHeight: 30
                                icon: "󰐕"
                                onClicked: {
                                    let n = tplName.text.trim(), t = tplText.text.trim();
                                    if (n === "" || t === "") return;
                                    Prefs.templates = Prefs.templates.concat([{ name: n, text: t }]);
                                    tplName.text = ""; tplText.text = "";
                                }
                            }
                        }
                    }
                }

                // ── scheduled tasks ──
                SectionTitle { text: "Задания по расписанию" }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: taskCol.implicitHeight + 20
                    radius: Theme.radius
                    color: Theme.card
                    ColumnLayout {
                        id: taskCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        anchors.leftMargin: 12
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: "Каждый день в указанное время Claude выполнит запрос, сохранит ответ в ~/Documents/Claude/tasks и пришлёт уведомление. Действия, требующие разрешения, без тебя не выполняются."
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.dim
                        }
                        Repeater {
                            model: Prefs.tasks
                            Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 8
                                color: Theme.panel
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 6
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: "󰥔 " + modelData.time + "  " + modelData.name + "  ·  " + modelData.prompt
                                        elide: Text.ElideRight
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        color: modelData.enabled ? Theme.sub : Theme.dim
                                    }
                                    PillButton {
                                        implicitHeight: 24
                                        icon: "󰐊"
                                        onClicked: { page.taskMsg = "Запускаю «" + modelData.name + "»…"; taskRun.command = ["python3", "-I", page.tasksScript, "run", modelData.id]; taskRun.running = true; }
                                    }
                                    Toggle {
                                        checked: modelData.enabled
                                        onToggled: v => { let l = JSON.parse(JSON.stringify(Prefs.tasks)); l[index].enabled = v; Prefs.tasks = l; page.syncTasks(); }
                                    }
                                    Text {
                                        text: "󰅖"
                                        font.family: Theme.font
                                        font.pixelSize: 14
                                        color: Theme.dim
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { let l = Prefs.tasks.slice(); l.splice(index, 1); Prefs.tasks = l; page.syncTasks(); }
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field { id: taskName; implicitWidth: 100; placeholder: "Название" }
                            Field { id: taskTime; implicitWidth: 64; placeholder: "08:00" }
                            Field { id: taskPrompt; Layout.fillWidth: true; placeholder: "Что сделать"; onAccepted: taskAdd.clicked() }
                            PillButton {
                                id: taskAdd
                                implicitHeight: 30
                                icon: "󰐕"
                                onClicked: {
                                    let n = taskName.text.trim(), tm = taskTime.text.trim() || "08:00", p = taskPrompt.text.trim();
                                    if (n === "" || p === "") { page.taskMsg = "Нужны название и текст задания"; return; }
                                    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(tm)) { page.taskMsg = "Время в формате ЧЧ:ММ, например 08:30"; return; }
                                    let id = Math.random().toString(36).substring(2, 8);
                                    Prefs.tasks = Prefs.tasks.concat([{ id: id, name: n, prompt: p, time: tm, enabled: true }]);
                                    taskName.text = ""; taskTime.text = ""; taskPrompt.text = "";
                                    page.syncTasks();
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: page.taskMsg !== ""
                            text: page.taskMsg
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.accent
                        }
                    }
                }

                // ── phone push ──
                SectionTitle { text: "Уведомления на телефон" }

                SRow {
                    title: "Тема ntfy"
                    hint: Prefs.ntfyTopic === ""
                        ? "Выключено. Поставь на телефон приложение ntfy, подпишись на тему и впиши её сюда — придут пуши, когда Claude закончит или ждёт разрешения"
                        : "Пуши идут в тему «" + Prefs.ntfyTopic + "» (ntfy.sh). Тему знают только те, кому ты её сказал — сделай её длинной"
                    RowLayout {
                        spacing: 6
                        Field {
                            id: ntfyField
                            implicitWidth: Math.min(170, page.width * 0.28)
                            text: Prefs.ntfyTopic
                            placeholder: "тема"
                            onEditingFinished: Prefs.ntfyTopic = text.trim().replace(/[^A-Za-z0-9_-]/g, "")
                        }
                        PillButton {
                            implicitHeight: 30
                            icon: "󰒓"
                            label: page.width > 520 ? "Придумать" : ""
                            onClicked: { let t = "deck-" + Math.random().toString(36).substring(2, 10) + Math.random().toString(36).substring(2, 6); ntfyField.text = t; Prefs.ntfyTopic = t; }
                        }
                        PillButton {
                            implicitHeight: 30
                            icon: "󰂚"
                            label: page.width > 520 ? "Проверить" : ""
                            visible: Prefs.ntfyTopic !== ""
                            onClicked: Quickshell.execDetached(["curl", "-s", "-m", "10", "-H", "Title: Claude на деке", "-H", "Tags: robot",
                                                                "-d", "Проверка: уведомления работают 👋", "https://ntfy.sh/" + Prefs.ntfyTopic])
                        }
                    }
                }

                // ── export ──
                SectionTitle { text: "Экспорт чата" }

                SRow {
                    title: "Сохранить в Markdown"
                    hint: page.exportMsg !== "" ? page.exportMsg : "Файл в ~/Documents/Claude — удобно читать и пересылать"
                    PillButton {
                        implicitHeight: 28
                        icon: "󰈙"
                        label: "Сохранить"
                        opacity: exportProc.running ? 0.5 : 1
                        onClicked: page.exportChat(false)
                    }
                }

                SRow {
                    title: "Секретный gist на GitHub"
                    hint: "Ссылка скопируется в буфер. Gist не виден в поиске, но открывается у любого, у кого есть ссылка"
                    PillButton {
                        implicitHeight: 28
                        icon: "󰊤"
                        label: "Создать"
                        opacity: exportProc.running ? 0.5 : 1
                        onClicked: page.exportChat(true)
                    }
                }

                // ── maintenance ──
                SectionTitle { text: "Обслуживание" }

                SRow {
                    title: "Перезапустить Claude Code"
                    hint: "Если завис. Разговор продолжится"
                    PillButton {
                        implicitHeight: 28
                        icon: "󰑓"
                        label: "Перезапуск"
                        opacity: page.ses.busy ? 0.5 : 1
                        onClicked: page.ses.restart()
                    }
                }

                SRow {
                    title: "Перезагрузить приложение"
                    hint: "Применяет правки файлов приложения"
                    PillButton {
                        implicitHeight: 28
                        icon: "󰜉"
                        label: "Перезагрузка"
                        onClicked: Quickshell.reload(false)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    text: "claude-desk · " + (versionProc.version || "Claude Code")
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.dim
                }
            }
        }
    }

    FileView {
        id: rulesFile
        path: page.ses.workDir + "/.claude/settings.local.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let o = page._readSettings();
            page.rules = o.permissions && Array.isArray(o.permissions.allow) ? o.permissions.allow : [];
        }
        onLoadFailed: page.rules = []
    }

    // ── scheduled tasks: timers are rebuilt from Prefs.tasks by tasks.py ──
    readonly property string tasksScript: Quickshell.env("HOME") + "/.local/share/claude-desk/tasks.py"
    property string taskMsg: ""
    function syncTasks() { taskSyncDelay.restart(); }
    // wait for Prefs to land in prefs.json (300 ms debounce) before rebuilding timers
    Timer { id: taskSyncDelay; interval: 900; onTriggered: { taskSync.running = false; taskSync.running = true; } }
    Process {
        id: taskSync
        command: ["python3", "-I", page.tasksScript, "sync"]
        stdout: StdioCollector { onStreamFinished: { let t = this.text.trim(); page.taskMsg = t.startsWith("OK") ? "Расписание обновлено, активных заданий: " + t.substring(3) : "Не удалось обновить расписание"; } }
    }
    Process {
        id: taskRun
        stdout: StdioCollector { onStreamFinished: { let t = this.text.trim(); page.taskMsg = t.startsWith("/") ? "Готово, ответ: " + page.shortDir(t) : (t || "Не получилось"); } }
    }

    // ── chat export: markdown file, optionally uploaded as a secret gist ──
    property string exportMsg: ""
    function exportChat(gist) {
        if (exportProc.running) return;
        page.exportMsg = gist ? "Загружаю на GitHub…" : "Сохраняю…";
        exportProc.md = page.ses.toMarkdown();
        exportProc.command = ["bash", "-c",
            "d=$HOME/Documents/Claude; mkdir -p \"$d\"; f=\"$d/chat-$(date +%Y-%m-%d_%H-%M).md\"; cat > \"$f\" || exit 1; "
            + (gist ? "u=$(gh gist create \"$f\" --desc 'Чат с Claude (cyberdeck)' 2>/dev/null | tail -1); "
                      + "[ -n \"$u\" ] && printf %s \"$u\" | wl-copy && echo \"GIST $u\" || echo \"FAIL $f\""
                    : "echo \"FILE $f\"")];
        exportProc.running = true;
    }
    Process {
        id: exportProc
        property string md: ""
        stdinEnabled: true
        onStarted: { write(md); stdinEnabled = false; }
        onExited: stdinEnabled = true
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim();
                if (t.startsWith("GIST ")) page.exportMsg = "Gist создан, ссылка в буфере: " + t.substring(5);
                else if (t.startsWith("FILE ")) page.exportMsg = "Сохранено: " + page.shortDir(t.substring(5));
                else page.exportMsg = "Gist не создан (нет входа в GitHub?). Файл: " + page.shortDir(t.replace(/^FAIL /, ""));
            }
        }
    }

    Process {
        id: versionProc
        property string version: ""
        command: ["claude", "--version"]
        stdout: SplitParser { onRead: line => { if (line.trim() !== "") versionProc.version = line.trim(); } }
    }
}
