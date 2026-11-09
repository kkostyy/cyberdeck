pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// AshenOS black by default; if serpantinum's matugen palette exists, it is used
// instead and updates live with the wallpaper.
Singleton {
    id: theme

    property color bg: "#050506"
    property color panel: "#0b0b0d"
    property color card: "#161619"
    property color cardHi: "#222226"
    property color border: "#3a3a40"
    property color text: "#e8e8ec"
    property color sub: "#a1a1a8"
    property color dim: "#8b8b93"
    property color accent: "#f2f2f4"
    property color accentDeep: "#3a3a40"
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
