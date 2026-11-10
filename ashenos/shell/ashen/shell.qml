//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// AshenOS shell: black bezel frame, top bar with the island, and liquid drops.
ShellRoot {
    id: root
    Status { id: status }
    Lock { st: status }
    Settings { st: status }
    Explorer {}

    Variants {
        model: Quickshell.screens
        Scope {
            id: perScreen
            required property var modelData
            Wallpaper { screen: perScreen.modelData; paused: !!root.pausedOutputs[perScreen.modelData.name] }
            Widgets { modelData: perScreen.modelData; st: status }
            Frame { screen: perScreen.modelData }
            Bar { modelData: perScreen.modelData; st: status }
            Dock { modelData: perScreen.modelData }
            // "Тёплый": a click-through warm tint over everything (like the prototype's display filter)
            PanelWindow {
                screen: perScreen.modelData
                visible: Config.data.warm
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: Qt.rgba(1, 0.55, 0.15, 0.12)
                mask: Region {}
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "ashen-warm"
            }
        }
    }

    // live wallpaper playback per output (bin/ashen-autopause)
    property var pausedOutputs: ({})
    IpcHandler {
        target: "wallpaper"
        function setPlayback(output: string, state: string): void {
            let m = Object.assign({}, root.pausedOutputs);
            m[output] = state === "pause";
            root.pausedOutputs = m;
        }
    }

    IpcHandler {
        target: "ashen-shell"
        function reload(): void { Quickshell.reload(false); }
    }
}
