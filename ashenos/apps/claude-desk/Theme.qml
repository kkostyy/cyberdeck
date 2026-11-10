pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colours follow serpantinum's matugen palette and update live with the wallpaper.
Singleton {
    id: theme

    property color bg: "#130d07"
    property color panel: "#19120c"
    property color card: "#261e18"
    property color cardHi: "#312822"
    property color border: "#3c332c"
    property color text: "#efe0d5"
    property color sub: "#d5c3b6"
    property color dim: "#9e8e82"
    property color accent: "#feb877"
    property color accentDeep: "#6b3b03"
    property color error: "#ffb4ab"
    property color ok: "#c2cb98"

    readonly property string font: "Iosevka Nerd Font"
    readonly property real radius: 12

    function apply(c) {
        if (!c) return;
        if (c.base) theme.bg = c.base;
        if (c.crust) theme.panel = c.crust;
        if (c.surface0) theme.card = c.surface0;
        if (c.surface1) theme.cardHi = c.surface1;
        if (c.surface2) theme.border = c.surface2;
        if (c.text) theme.text = c.text;
        if (c.subtext0) theme.sub = c.subtext0;
        if (c.subtext1) theme.dim = c.subtext1;
        if (c.blue) theme.accent = c.blue;
        if (c.sapphire) theme.accentDeep = c.sapphire;
        if (c.red) theme.error = c.red;
        if (c.peach) theme.ok = c.peach;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/serpantinum/qs_colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { theme.apply(JSON.parse(text())); } catch (e) {}
        }
    }

    Behavior on bg { ColorAnimation { duration: 600 } }
    Behavior on card { ColorAnimation { duration: 600 } }
    Behavior on accent { ColorAnimation { duration: 600 } }
}
