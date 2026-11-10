pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell settings in ~/.config/ashen/config.json; changes save themselves and
// edits to the file are picked up live.
Singleton {
    id: cfg
    readonly property string dir: Quickshell.env("HOME") + "/.config/ashen"
    readonly property alias data: adapter

    Process {
        running: true
        command: ["mkdir", "-p", cfg.dir]
        onExited: if (!file.loaded) file.writeAdapter()
    }

    FileView {
        id: file
        property bool loaded: false
        path: cfg.dir + "/config.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: loaded = true
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter
            // "" — built-in AshenOS background; a picture or a video (mp4/webm/mkv) path otherwise
            property string wallpaper: ""
            property string wallpaperFill: "fill"          // fill | fit | center
            property var dock: ["claude-desk", "chromium", "org.gnome.Nautilus", "kitty", "org.kde.konsole"]
            property int lockAfter: 300                     // seconds, 0 — never
            property int screenOffAfter: 450
            property bool dnd: false                        // notifications go to the list only
            property bool barClaude: true
            property bool barSysmon: true
            // weather location; 0/0 — detect by IP
            property real lat: 0
            property real lon: 0
            property string city: ""
        }
    }
}
