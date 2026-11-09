pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// App preferences (Settings page); stored in ~/.local/state/claude-desk/prefs.json.
Singleton {
    id: prefs

    property real textScale: 1.0
    property bool showTools: true
    property bool showCost: true
    property bool notify: true
    property bool sound: false
    property bool enterSends: true
    property string appendPrompt: ""
    // v6
    property bool autoContinue: false      // press "Продолжить" by itself after a power loss
    property bool quickPrompts: true       // chips above the input
    property bool replyActions: true       // Заново / Изменить / Продолжи under the last answer
    property bool recentTabs: true         // strip of recent chats under the header
    property bool confirmNewChat: false
    property string defaultDir: ""         // folder for new chats ("" = current)
    property string ntfyTopic: ""          // phone push via ntfy.sh ("" = off)
    property var templates: [
        { name: "Коммит", text: "Сделай коммит с понятным сообщением и запушь на GitHub" },
        { name: "Объясни", text: "Объясни простыми словами, что делает этот код и зачем" },
        { name: "Проверь", text: "Проверь, что всё работает, и исправь ошибки, если найдёшь" }
    ]
    property var tasks: []                 // scheduled prompts: [{id, name, prompt, time, enabled}]

    readonly property var _keys: ["textScale", "showTools", "showCost", "notify", "sound", "enterSends", "appendPrompt",
        "autoContinue", "quickPrompts", "replyActions", "recentTabs", "confirmNewChat", "defaultDir", "ntfyTopic", "templates", "tasks"]
    property bool _loaded: false

    function _save() {
        if (!prefs._loaded) return;
        saveTimer.restart();
    }
    onTextScaleChanged: _save()
    onShowToolsChanged: _save()
    onShowCostChanged: _save()
    onNotifyChanged: _save()
    onSoundChanged: _save()
    onEnterSendsChanged: _save()
    onAppendPromptChanged: _save()
    onAutoContinueChanged: _save()
    onQuickPromptsChanged: _save()
    onReplyActionsChanged: _save()
    onRecentTabsChanged: _save()
    onConfirmNewChatChanged: _save()
    onDefaultDirChanged: _save()
    onNtfyTopicChanged: _save()
    onTemplatesChanged: _save()
    onTasksChanged: _save()

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: {
            let o = {};
            for (let k of prefs._keys) o[k] = prefs[k];
            file.setText(JSON.stringify(o, null, 2) + "\n");
        }
    }

    function _load() {
        let o = {};
        try { o = JSON.parse(file.text()) || {}; } catch (e) { o = {}; }
        for (let k of prefs._keys) if (o[k] !== undefined && typeof o[k] === typeof prefs[k]) prefs[k] = o[k];
        prefs._loaded = true;
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/state/claude-desk/prefs.json"
        printErrors: false
        onLoaded: prefs._load()
        onLoadFailed: prefs._load()
    }
}
