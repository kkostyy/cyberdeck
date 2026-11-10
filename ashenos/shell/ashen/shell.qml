//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

// AshenOS shell: black bezel frame, top bar with the island, and liquid drops.
ShellRoot {
    id: root
    Status { id: status }
    Lock { st: status }
    Settings { st: status }

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
