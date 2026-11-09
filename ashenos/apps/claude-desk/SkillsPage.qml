import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// Skills, subagents and memory (CLAUDE.md), plus every command the CLI
// reported. Your own skills/agents can be created, edited and deleted here.
Rectangle {
    id: page
    required property var ses
    property bool shown: false
    property var skills: []
    property var agents: []
    property string memGlobal: ""
    property string memProject: ""
    property string filter: ""
    property string confirmDelete: ""
    property string tab: "skills"        // "skills" | "agents" | "memory" | "all"

    // editor state; editing === null → list view.
    // {kind: "skill"|"agent"|"memory", name, description, body, model, extra, path, title}
    property var editing: null
    property string error: ""
    property bool needRestart: false
    property string agentModel: ""

    signal useRequested(string text)     // draft this into the composer

    readonly property string helper: Qt.resolvedUrl("skills.py").toString().replace(/^file:\/\//, "")
    readonly property string home: Quickshell.env("HOME")
    readonly property string globalMemPath: home + "/.claude/CLAUDE.md"
    readonly property string projectMemPath: ses.workDir + "/CLAUDE.md"
    readonly property bool hasCreator: ses.commands.some(c => c.name === "skill-creator")
    readonly property bool isAgent: editing !== null && editing.kind === "agent"
    readonly property bool isMemory: editing !== null && editing.kind === "memory"
    readonly property var agentModels: [
        { v: "", t: "как в чате" }, { v: "sonnet", t: "Sonnet" }, { v: "opus", t: "Opus" }, { v: "haiku", t: "Haiku" }
    ]

    function open(tab) {
        page.shown = true;
        page.editing = null;
        page.filter = "";
        page.confirmDelete = "";
        if (tab) page.tab = tab;
        search.text = "";
        page.forceActiveFocus();
        refresh();
    }
    function close() {
        page.shown = false;
        page.editing = null;
        applyRestart();
    }
    function refresh() {
        skillLister.running = false; skillLister.running = true;
        agentLister.running = false; agentLister.running = true;
        memGlobalReader.running = false; memGlobalReader.running = true;
        memProjectReader.running = false; memProjectReader.running = true;
    }

    // new skills/agents/memory only reach Claude after the CLI restarts; wait until it's idle
    function applyRestart() {
        if (!page.needRestart) return;
        if (page.ses.busy) { restartWait.start(); return; }
        page.needRestart = false;
        page.ses.restart();
    }
    Timer { id: restartWait; interval: 1500; repeat: true; onTriggered: if (!page.ses.busy) { stop(); page.applyRestart(); } }

    function edit(kind, item) {
        page.error = "";
        let e = { kind: kind };
        for (let k in (item || {})) e[k] = item[k];
        page.editing = e;
        nameField.text = e.name || "";
        descField.text = e.description || "";
        bodyArea.text = e.body || "";
        page.agentModel = e.model || "";
        if (kind === "memory") bodyArea.forceActiveFocus();
        else nameField.forceActiveFocus();
    }
    function editMemory(global) {
        edit("memory", {
            path: global ? page.globalMemPath : page.projectMemPath,
            title: global ? "Общая память" : "Память папки",
            body: global ? page.memGlobal : page.memProject
        });
    }

    function slug(t) {
        return t.toLowerCase().trim().replace(/[\s_]+/g, "-").replace(/[^a-z0-9-]/g, "").replace(/^-+/, "").substring(0, 64);
    }
    function shortPath(p) { return p.startsWith(page.home) ? "~" + p.substring(page.home.length) : p; }
    function firstLine(t) {
        let l = t.split("\n").map(x => x.replace(/^#+\s*/, "").trim()).filter(x => x !== "");
        return l.length > 0 ? l[0] : "";
    }

    function save() {
        let e = page.editing;
        if (!e) return;
        if (e.kind === "memory") {
            page.error = "";
            saver.command = ["python3", "-I", page.helper, "memory-write", e.path, bodyArea.text];
            saver.running = true;
            return;
        }
        let name = nameField.text.trim();
        let old = e.name || "";
        let what = e.kind === "agent" ? "Агент" : "Скилл";
        let taken = (e.kind === "agent" ? page.agents : page.skills).map(s => s.name);
        if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(name) || name === "synced") {
            page.error = "Имя: латиница в нижнем регистре, цифры и дефис";
            return;
        }
        if (name !== old && taken.indexOf(name) >= 0) { page.error = what + " с таким именем уже есть"; return; }
        if (descField.text.trim() === "") { page.error = "Опиши, когда Claude должен его использовать"; return; }
        if (bodyArea.text.trim() === "") { page.error = "Напиши инструкции"; return; }
        page.error = "";
        let cmd = ["python3", "-I", page.helper];
        if (e.kind === "agent") cmd.push("--agents");
        cmd = cmd.concat(["save", name, old, descField.text, bodyArea.text]);
        if (e.kind === "agent") cmd.push(page.agentModel);
        saver.command = cmd;
        saver.running = true;
    }

    color: Theme.bg
    visible: x < parent.width
    x: shown ? 0 : parent.width
    Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    focus: shown
    Keys.onEscapePressed: page.editing !== null ? page.editing = null : page.close()
    MouseArea { anchors.fill: parent; onClicked: page.forceActiveFocus() }

    Process {
        id: skillLister
        command: ["python3", "-I", page.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.skills = JSON.parse(this.text); } catch (e) { page.skills = []; } }
        }
    }
    Process {
        id: agentLister
        command: ["python3", "-I", page.helper, "--agents", "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.agents = JSON.parse(this.text); } catch (e) { page.agents = []; } }
        }
    }
    Process {
        id: memGlobalReader
        command: ["python3", "-I", page.helper, "memory-read", page.globalMemPath]
        stdout: StdioCollector { onStreamFinished: page.memGlobal = this.text }
    }
    Process {
        id: memProjectReader
        command: ["python3", "-I", page.helper, "memory-read", page.projectMemPath]
        stdout: StdioCollector { onStreamFinished: page.memProject = this.text }
    }
    Process {
        id: saver
        stderr: StdioCollector { id: saveErr }
        onExited: function(code) {
            if (code !== 0) {
                let t = saveErr.text.trim();
                page.error = t === "exists" ? "Такое имя уже занято" : "Не удалось сохранить: " + t;
                return;
            }
            page.editing = null;
            page.needRestart = true;
            page.refresh();
        }
    }
    Process {
        id: remover
        onExited: { page.needRestart = true; page.refresh(); }
    }

    // shared look for inputs
    component Box: Rectangle {
        property bool focused: false
        radius: 10
        color: Theme.card
        border.color: focused ? Qt.alpha(Theme.accent, 0.7) : Theme.border
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }
    component FieldLabel: Text {
        font.family: Theme.font
        font.pixelSize: 11
        font.bold: true
        color: Theme.accent
        Layout.leftMargin: 4
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    // ── list view ─────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8
        visible: page.editing === null

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PillButton { implicitHeight: 28; icon: "󰁍"; onClicked: page.close() }
            Text {
                text: "Скиллы"
                font.family: Theme.font
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
            }
            Box {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 15
                focused: search.activeFocus
                opacity: page.tab === "memory" ? 0.4 : 1
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
                    enabled: page.tab !== "memory"
                    onTextChanged: page.filter = text
                    Keys.onEscapePressed: page.close()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: search.text === ""
                        text: "󰍉  поиск"
                        font.family: Theme.font
                        font.pixelSize: 12
                        color: Theme.dim
                    }
                }
            }
            PillButton {
                implicitHeight: 28
                icon: "󰐕"
                label: page.width > 520 ? "Новый" : ""
                primary: true
                visible: page.tab === "skills" || page.tab === "agents"
                onClicked: page.edit(page.tab === "agents" ? "agent" : "skill", null)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { id: "skills", t: "Мои скиллы", n: page.skills.length },
                    { id: "agents", t: "Агенты", n: page.agents.length },
                    { id: "memory", t: "Память", n: -1 },
                    { id: "all", t: "Все", n: page.ses.commands.length }
                ]
                PillButton {
                    implicitHeight: 26
                    label: modelData.t + (modelData.n >= 0 ? " (" + modelData.n + ")" : "")
                    active: page.tab === modelData.id
                    onClicked: { page.tab = modelData.id; page.confirmDelete = ""; }
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: page.needRestart && page.width > 600
                text: page.ses.busy ? "󰑓 после ответа" : "󰑓 при выходе"
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.dim
            }
        }

        // ── skills / agents / all ──
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.tab !== "memory"
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: {
                let f = page.filter.trim().toLowerCase();
                let own = page.skills.map(s => s.name);
                let src = page.tab === "skills"
                    ? page.skills.map(s => ({ kind: "skill", name: s.name, description: s.description, own: true, item: s }))
                    : page.tab === "agents"
                    ? page.agents.map(s => ({ kind: "agent", name: s.name, description: s.description, own: true, item: s,
                                              hint: s.model ? "󰧑 " + s.model : "" }))
                    : page.ses.commands.filter(c => !c.name.startsWith("__"))
                          .map(c => ({ kind: "command", name: c.name, description: c.description || "", hint: c.argumentHint || "",
                                       own: own.indexOf(c.name) >= 0 }));
                return f === "" ? src : src.filter(s => (s.name + " " + s.description).toLowerCase().indexOf(f) >= 0);
            }
            ScrollBar.vertical: ScrollBar {
                policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: Qt.alpha(Theme.sub, 0.4) }
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool editable: modelData.item !== undefined && modelData.item.editable
                readonly property bool confirming: editable && page.confirmDelete === modelData.kind + ":" + modelData.name
                width: list.width - 8
                implicitHeight: col.implicitHeight + 16
                radius: Theme.radius
                color: hover.hovered ? Theme.cardHi : Theme.card
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: hover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        page.useRequested(row.modelData.kind === "agent"
                            ? "Поручи агенту " + row.modelData.name + ": "
                            : "/" + row.modelData.name + " ");
                        page.close();
                    }
                }

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: actions.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 2
                    RowLayout {
                        spacing: 6
                        Layout.fillWidth: true
                        Text {
                            text: row.modelData.kind === "agent" ? "󱙺 " + row.modelData.name
                                : (row.modelData.own ? "󰘦 " : "") + "/" + row.modelData.name
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.bold: true
                            color: row.modelData.own ? Theme.accent : Theme.text
                            elide: Text.ElideRight
                            Layout.maximumWidth: col.width * 0.6
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: (row.modelData.hint || "") !== ""
                            text: row.modelData.hint || ""
                            font.family: Theme.font
                            font.pixelSize: 11
                            color: Theme.dim
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.confirming ? "Удалить «" + row.modelData.name + "» насовсем?"
                            : row.modelData.description.replace(/^\([^)]*\)\s*/, "") || "без описания"
                        font.family: Theme.font
                        font.pixelSize: 11
                        color: row.confirming ? Theme.error : Theme.dim
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: row.editable
                    PillButton {
                        visible: row.confirming
                        implicitHeight: 26
                        label: "Удалить"
                        danger: true
                        onClicked: {
                            let cmd = ["python3", "-I", page.helper];
                            if (row.modelData.kind === "agent") cmd.push("--agents");
                            remover.command = cmd.concat(["delete", row.modelData.name]);
                            remover.running = true;
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
                        visible: !row.confirming
                        implicitHeight: 26
                        icon: "󰏫"
                        opacity: hover.hovered ? 1 : 0.6
                        onClicked: page.edit(row.modelData.kind, row.modelData.item)
                    }
                    PillButton {
                        visible: !row.confirming
                        implicitHeight: 26
                        icon: "󰆴"
                        opacity: hover.hovered ? 1 : 0.5
                        onClicked: page.confirmDelete = row.modelData.kind + ":" + row.modelData.name
                    }
                }
            }

            // empty states
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 20, 460)
                spacing: 10
                visible: list.count === 0
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: page.filter !== "" ? "Ничего не нашлось"
                        : page.tab === "skills" ? "Своих скиллов пока нет.\nСкилл — это инструкция, которую Claude подхватывает сам, когда она к месту, или по команде /имя."
                        : page.tab === "agents" ? "Своих агентов пока нет.\nАгент — помощник со своей ролью и инструкциями: Claude поручает ему часть работы, и тот делает её в отдельном контексте."
                        : "Список появится, когда Claude Code запустится"
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.dim
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    visible: (page.tab === "skills" || page.tab === "agents") && page.filter === ""
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    PillButton {
                        icon: "󰐕"
                        label: "Написать самому"
                        onClicked: page.edit(page.tab === "agents" ? "agent" : "skill", null)
                    }
                    PillButton {
                        icon: "󰚩"
                        label: "Попросить Claude"
                        visible: page.tab === "agents" || page.hasCreator
                        onClicked: {
                            page.useRequested(page.tab === "agents"
                                ? "Создай субагента: файл ~/.claude/agents/<имя>.md с frontmatter name и description. Он должен "
                                : "/skill-creator Создай скилл, который ");
                            page.close();
                        }
                    }
                }
            }
        }

        // ── memory: CLAUDE.md files Claude reads at the start of every chat ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.tab === "memory"
            spacing: 6

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: "То, что Claude читает в начале каждого чата: кто ты, как отвечать, что важно помнить."
                font.family: Theme.font
                font.pixelSize: 12
                color: Theme.dim
                wrapMode: Text.Wrap
            }

            Repeater {
                model: [
                    { global: true, icon: "󰋜", title: "Общая — для всех папок", path: page.globalMemPath, text: page.memGlobal },
                    { global: false, icon: "󰉋", title: "Только для " + page.shortPath(page.ses.workDir), path: page.projectMemPath, text: page.memProject }
                ]
                Rectangle {
                    id: mrow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: mcol.implicitHeight + 18
                    radius: Theme.radius
                    color: mhover.hovered ? Theme.cardHi : Theme.card
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: mhover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.editMemory(mrow.modelData.global)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 10
                        Text {
                            text: mrow.modelData.icon
                            font.family: Theme.font
                            font.pixelSize: 18
                            color: Theme.accent
                        }
                        ColumnLayout {
                            id: mcol
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: mrow.modelData.title
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.bold: true
                                color: Theme.text
                                elide: Text.ElideMiddle
                            }
                            Text {
                                Layout.fillWidth: true
                                text: mrow.modelData.text.trim() === "" ? "пусто — нажми, чтобы написать"
                                    : page.firstLine(mrow.modelData.text) + "  ·  строк: " + mrow.modelData.text.trim().split("\n").length
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.dim
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: page.shortPath(mrow.modelData.path)
                                font.family: Theme.font
                                font.pixelSize: 10
                                color: Qt.alpha(Theme.dim, 0.7)
                                elide: Text.ElideMiddle
                            }
                        }
                        Text {
                            text: "󰏫"
                            font.family: Theme.font
                            font.pixelSize: 15
                            color: Theme.sub
                            opacity: mhover.hovered ? 1 : 0.5
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── editor ────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6
        visible: page.editing !== null

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PillButton { implicitHeight: 28; icon: "󰁍"; onClicked: page.editing = null }
            Text {
                Layout.fillWidth: true
                text: !page.editing ? ""
                    : page.isMemory ? page.editing.title
                    : page.isAgent ? (page.editing.name ? "Агент " + page.editing.name : "Новый агент")
                    : (page.editing.name ? "Скилл /" + page.editing.name : "Новый скилл")
                font.family: Theme.font
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
                elide: Text.ElideRight
            }
            PillButton {
                implicitHeight: 28
                icon: "󰚩"
                label: page.width > 560 ? "Доработать с Claude" : ""
                visible: page.editing !== null && page.editing.kind === "skill" && !!page.editing.name && page.hasCreator
                onClicked: {
                    page.useRequested("/skill-creator Улучши скилл ~/.claude/skills/" + page.editing.name + "/SKILL.md: ");
                    page.close();
                }
            }
            PillButton {
                implicitHeight: 28
                icon: "󰆓"
                label: "Сохранить"
                primary: true
                enabled: !saver.running
                onClicked: page.save()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: page.error !== ""
            text: page.error
            font.family: Theme.font
            font.pixelSize: 12
            color: Theme.error
            wrapMode: Text.Wrap
        }

        FieldLabel {
            visible: !page.isMemory
            text: page.isAgent ? "ИМЯ" : "ИМЯ — команда /имя"
        }
        Box {
            visible: !page.isMemory
            Layout.fillWidth: true
            implicitHeight: 32
            focused: nameField.activeFocus
            TextInput {
                id: nameField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.text
                selectionColor: Theme.accent
                clip: true
                // keep it a valid file name as you type
                onTextEdited: { let s = page.slug(text); if (s !== text) { text = s; cursorPosition = s.length; } }
                KeyNavigation.tab: descField
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: nameField.text === ""
                    text: page.isAgent ? "например: code-reviewer" : "например: commit-ru"
                    font: nameField.font
                    color: Theme.dim
                }
            }
        }

        FieldLabel {
            visible: !page.isMemory
            text: page.isAgent ? "КОГДА ПОРУЧАТЬ — по этому Claude решает, звать ли агента"
                               : "КОГДА ИСПОЛЬЗОВАТЬ — по этому Claude решает, подключать ли скилл"
        }
        Box {
            visible: !page.isMemory
            Layout.fillWidth: true
            implicitHeight: Math.max(32, descField.contentHeight + 14)
            focused: descField.activeFocus
            TextEdit {
                id: descField
                anchors.fill: parent
                anchors.margins: 7
                anchors.leftMargin: 10
                font.family: Theme.font
                font.pixelSize: 13
                color: Theme.text
                selectionColor: Theme.accent
                wrapMode: TextEdit.Wrap
                KeyNavigation.tab: bodyArea
                Keys.onReturnPressed: bodyArea.forceActiveFocus()
                Text {
                    anchors.fill: parent
                    visible: descField.text === ""
                    text: page.isAgent ? "Проверяет свежие изменения в коде на ошибки. Звать после правок."
                                       : "Пиши коммиты по-русски. Использовать, когда просят закоммитить."
                    font: descField.font
                    color: Theme.dim
                    wrapMode: Text.Wrap
                }
            }
        }

        // agents can run on their own model
        RowLayout {
            visible: page.isAgent
            Layout.fillWidth: true
            spacing: 6
            FieldLabel { text: "МОДЕЛЬ"; Layout.fillWidth: false }
            Repeater {
                model: page.agentModels
                PillButton {
                    implicitHeight: 26
                    label: modelData.t
                    active: page.agentModel === modelData.v
                    onClicked: page.agentModel = modelData.v
                }
            }
            Item { Layout.fillWidth: true }
        }

        FieldLabel {
            text: page.isMemory ? page.shortPath(page.editing.path) + " (Markdown)"
                : page.isAgent ? "РОЛЬ И ИНСТРУКЦИИ (Markdown)" : "ИНСТРУКЦИИ (Markdown)"
        }
        Box {
            Layout.fillWidth: true
            Layout.fillHeight: true
            focused: bodyArea.activeFocus
            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                TextArea {
                    id: bodyArea
                    wrapMode: TextArea.Wrap
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.text
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    placeholderText: page.isMemory ? "- Отвечай по-русски, коротко\n- У меня Raspberry Pi, Arch ARM, sway\n- …"
                        : page.isAgent ? "Ты — внимательный ревьюер кода.\n\n1. Посмотри git diff\n2. Найди ошибки и опасные места\n3. Ответь списком: файл:строка — проблема"
                        : "# Что делать\n\n1. Посмотри git diff\n2. Напиши короткое сообщение коммита на русском\n…"
                    placeholderTextColor: Theme.dim
                    background: null
                    Keys.onPressed: function(ev) {
                        if (ev.key === Qt.Key_S && (ev.modifiers & Qt.ControlModifier)) { page.save(); ev.accepted = true; }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: (page.editing && page.editing.extra > 0 ? "В папке скилла ещё файлов: " + page.editing.extra + " — они не трогаются. " : "")
                + "Ctrl+S — сохранить, Esc — назад. Claude увидит изменения после перезапуска (сам, когда закроешь страницу)."
            font.family: Theme.font
            font.pixelSize: 11
            color: Theme.dim
            wrapMode: Text.Wrap
        }
    }
}
