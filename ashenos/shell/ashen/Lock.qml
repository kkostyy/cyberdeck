import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Session lock + idle: lock and screen-off timeouts from Config (not while music plays).
//   quickshell ipc call ashen-lock lock      — lock now
//   quickshell ipc call ashen-lock preview   — show the lock screen in a normal window
Scope {
    id: root
    required property var st
    property bool previewing: false

    WlSessionLock {
        id: sessionLock
        locked: false
        onLockedChanged: root.st.locked = locked
        surface: Component {
            WlSessionLockSurface {
                color: Theme.bezel
                LockContent {
                    anchors.fill: parent
                    st: root.st
                    onUnlocked: sessionLock.locked = false
                }
            }
        }
    }

    LazyLoader {
        active: root.previewing
        FloatingWindow {
            title: "AshenOS — экран блокировки (превью)"
            implicitWidth: 695
            implicitHeight: 417
            color: Theme.bezel
            onClosed: root.previewing = false
            LockContent {
                anchors.fill: parent
                st: root.st
                preview: true
                onUnlocked: root.previewing = false
            }
        }
    }

    IdleMonitor {
        timeout: Math.max(1, Config.data.lockAfter)
        enabled: Config.data.lockAfter > 0 && !root.st.playing && !sessionLock.locked
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) sessionLock.locked = true
    }
    IdleMonitor {
        timeout: Math.max(1, Config.data.screenOffAfter)
        enabled: Config.data.screenOffAfter > 0 && !root.st.playing
        respectInhibitors: true
        onIsIdleChanged: Quickshell.execDetached(["swaymsg", "output * power " + (isIdle ? "off" : "on")])
    }

    IpcHandler {
        target: "ashen-lock"
        function lock(): void { sessionLock.locked = true; }
        function preview(): void { root.previewing = true; }
    }
}
