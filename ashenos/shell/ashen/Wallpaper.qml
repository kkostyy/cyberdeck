import QtQuick
import Quickshell
import Quickshell.Wayland

// Desktop background layer.
PanelWindow {
    id: win
    property string image: ""
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "#0b0b0d"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "ashen-wallpaper"
    WallArt { anchors.fill: parent; image: win.image }
}
