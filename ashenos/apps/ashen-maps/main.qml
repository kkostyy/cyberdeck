// AshenOS · Карты
// QtLocation + OpenStreetMap. Тёмные плитки CARTO, поиск Nominatim, маршруты OSRM,
// GPS через QtPositioning (geoclue2 / gpsd). Запуск: ashen-maps
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

ApplicationWindow {
    id: win
    visible: true
    width: 800; height: 480
    title: "Карты"
    color: "#0b0b0d"

    // параметры из лаунчера: accent=#rrggbb style=dark|light offline=/путь
    function arg(name, def) {
        for (const a of Qt.application.arguments) if (a.startsWith(name + "=")) return a.slice(name.length + 1)
        return def
    }
    readonly property color accent: arg("accent", "#ef3b3b")
    readonly property bool dark: arg("style", "dark") === "dark"
    readonly property string offlineDir: arg("offline", "")
    property var dest: null            // {name, coordinate}
    property string mode: "car"        // car | foot | bike
    property bool navigating: false

    Plugin {
        id: osm
        name: "osm"
        PluginParameter { name: "osm.useragent"; value: "AshenOS Maps" }
        PluginParameter { name: "osm.mapping.custom.host"; value: win.dark ? "https://basemaps.cartocdn.com/dark_all/" : "https://basemaps.cartocdn.com/rastertiles/voyager/" }
        PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
        PluginParameter { name: "osm.mapping.cache.disk.size"; value: 536870912 }   // 512 МБ — уже просмотренное работает офлайн
        PluginParameter { name: "osm.mapping.offline.directory"; value: win.offlineDir }
        PluginParameter { name: "osm.routing.host"; value: "https://router.project-osrm.org/route/v1/" + (win.mode === "car" ? "driving/" : win.mode === "bike" ? "cycling/" : "walking/") }
    }

    PositionSource {
        id: gps
        active: true
        updateInterval: 2000
        onPositionChanged: if (follow.checked) map.center = position.coordinate
    }
    readonly property var here: gps.position.latitudeValid ? gps.position.coordinate : QtPositioning.coordinate(59.437, 24.7536) // Таллин

    Map {
        id: map
        anchors.fill: parent
        plugin: osm
        zoomLevel: 13
        center: win.here
        activeMapType: supportedMapTypes[supportedMapTypes.length - 1]   // CustomMap
        copyrightsVisible: true

        PinchHandler { target: null; onScaleChanged: (d) => map.zoomLevel += Math.log2(d) ; grabPermissions: PointerHandler.TakeOverForbidden }
        WheelHandler { onWheel: (e) => map.zoomLevel += e.angleDelta.y / 240 }
        DragHandler { target: null; onTranslationChanged: (d) => { follow.checked = false; map.pan(-d.x, -d.y) } }
        TapHandler { onDoubleTapped: map.zoomLevel += 1 }

        // маршрут
        MapItemView {
            model: routes
            delegate: MapRoute { route: routeData; line.color: win.accent; line.width: 6; smooth: true; opacity: 0.95 }
        }
        // я
        MapQuickItem {
            coordinate: win.here
            anchorPoint: Qt.point(14, 14)
            sourceItem: Rectangle { width: 28; height: 28; radius: 14; color: "#334aa3ff"
                Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: "#4aa3ff"; border.color: "white"; border.width: 2 } }
        }
        // цель
        MapQuickItem {
            visible: win.dest !== null
            coordinate: win.dest ? win.dest.coordinate : win.here
            anchorPoint: Qt.point(15, 34)
            sourceItem: Rectangle { width: 30; height: 30; radius: 15; color: win.accent; border.color: "white"; border.width: 2
                Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white" } }
        }
    }

    RouteQuery { id: rq }
    RouteModel {
        id: routes
        plugin: osm
        query: rq
        autoUpdate: false
    }
    function buildRoute() {
        if (!dest) return
        rq.clearWaypoints()
        rq.addWaypoint(here); rq.addWaypoint(dest.coordinate)
        rq.travelModes = mode === "car" ? RouteQuery.CarTravel : mode === "bike" ? RouteQuery.BicycleTravel : RouteQuery.PedestrianTravel
        routes.update()
        map.fitViewportToMapItems()
    }
    readonly property var route: routes.count > 0 ? routes.get(0) : null
    function km(m) { return m < 950 ? Math.round(m / 10) * 10 + " м" : (m / 1000).toFixed(1).replace(".", ",") + " км" }
    function mins(s) { const m = Math.max(1, Math.round(s / 60)); return m < 60 ? m + " мин" : Math.floor(m / 60) + " ч " + (m % 60) + " мин" }

    // поиск адресов (Nominatim)
    ListModel { id: found }
    function search(q) {
        if (q.trim().length < 2) { found.clear(); return }
        const x = new XMLHttpRequest()
        x.open("GET", "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=6&accept-language=ru&viewbox=23.5,60.0,26.5,58.9&q=" + encodeURIComponent(q))
        x.setRequestHeader("User-Agent", "AshenOS Maps")
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            found.clear()
            if (x.status !== 200) { found.append({ name: "Нет сети — поиск недоступен", sub: "Карта работает из кэша", lat: 0, lon: 0 }); return }
            for (const r of JSON.parse(x.responseText)) {
                const p = r.display_name.split(", ")
                found.append({ name: p[0], sub: p.slice(1, 4).join(", "), lat: +r.lat, lon: +r.lon })
            }
        }
        x.send()
    }
    Timer { id: debounce; interval: 450; onTriggered: win.search(query.text) }

    // ===== левая панель =====
    Rectangle {
        id: panel
        x: 10; y: 10; width: 280; height: parent.height - 20
        radius: 18; color: "#ee121214"; border.color: "#22ffffff"
        visible: !win.navigating
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 10; spacing: 8
            TextField {
                id: query
                Layout.fillWidth: true; implicitHeight: 44
                placeholderText: "Поиск мест и адресов"
                color: "#f2f2f4"; placeholderTextColor: "#6f6f77"; font.pixelSize: 15
                background: Rectangle { radius: 12; color: "#14ffffff"; border.color: "#18ffffff" }
                onTextEdited: debounce.restart()
            }
            // результаты / маршрут
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                visible: win.dest === null
                model: found
                delegate: Rectangle {
                    width: ListView.view.width; height: 56; radius: 12; color: tap.pressed ? "#22ffffff" : "#0dffffff"
                    Column { anchors.fill: parent; anchors.margins: 10; spacing: 2
                        Text { text: name; color: "#f2f2f4"; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; width: parent.width }
                        Text { text: sub; color: "#8b8b93"; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width } }
                    TapHandler { id: tap; onTapped: if (lat) { win.dest = { name: name, coordinate: QtPositioning.coordinate(lat, lon) }; win.buildRoute() } }
                }
            }
            ColumnLayout {
                visible: win.dest !== null; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8
                Text { text: win.dest ? win.dest.name : ""; color: "#f2f2f4"; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                RowLayout { spacing: 6; Layout.fillWidth: true
                    Repeater { model: [["car", "Авто"], ["foot", "Пешком"], ["bike", "Вело"]]
                        Button { Layout.fillWidth: true; implicitHeight: 40; text: modelData[1]
                            contentItem: Text { text: parent.text; color: win.mode === modelData[0] ? "#111113" : "#d6d6db"; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { radius: 11; color: win.mode === modelData[0] ? "#f2f2f4" : "#0dffffff" }
                            onClicked: { win.mode = modelData[0]; win.buildRoute() } } }
                }
                Text { color: "#f2f2f4"; font.pixelSize: 22; font.bold: true
                    text: win.route ? win.mins(win.route.travelTime) + " · " + win.km(win.route.distance) : (routes.status === RouteModel.Loading ? "Строю маршрут…" : "Маршрут не найден") }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4
                    model: win.route ? win.route.segments : []
                    delegate: Text { width: ListView.view.width; wrapMode: Text.WordWrap; color: "#c9c9cf"; font.pixelSize: 12
                        text: "• " + modelData.maneuver.instructionText + "  (" + win.km(modelData.distance) + ")" }
                }
                RowLayout { spacing: 6
                    Button { implicitHeight: 44; implicitWidth: 44; text: "‹"
                        contentItem: Text { text: "‹"; color: "#f2f2f4"; font.pixelSize: 22; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 12; color: "#14ffffff" }
                        onClicked: { win.dest = null; routes.reset() } }
                    Button { Layout.fillWidth: true; implicitHeight: 44; text: "Поехали"; enabled: win.route !== null
                        contentItem: Text { text: parent.text; color: "white"; font.pixelSize: 15; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 12; color: win.accent; opacity: parent.enabled ? 1 : 0.4 }
                        onClicked: { win.navigating = true; follow.checked = true; map.zoomLevel = 16; map.center = win.here } }
                }
            }
        }
    }

    // ===== навигация =====
    Rectangle {
        visible: win.navigating && win.route !== null
        anchors.horizontalCenter: parent.horizontalCenter; y: 10
        width: Math.min(460, parent.width - 120); height: 64; radius: 18; color: win.accent
        Text { anchors.fill: parent; anchors.margins: 12; color: "white"; font.pixelSize: 15; font.bold: true; wrapMode: Text.WordWrap; verticalAlignment: Text.AlignVCenter
            text: win.route && win.route.segments.length ? win.route.segments[0].maneuver.instructionText : "" }
    }
    Rectangle {
        visible: win.navigating
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
        width: 360; height: 56; radius: 18; color: "#ee141416"; border.color: "#22ffffff"
        RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 14
            Text { color: "#f2f2f4"; font.pixelSize: 15; font.bold: true; text: win.route ? win.mins(win.route.travelTime) + " · " + win.km(win.route.distance) : "" }
            Item { Layout.fillWidth: true }
            Button { implicitHeight: 36; text: "Завершить"
                contentItem: Text { text: parent.text; color: "#ff9a9a"; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 11; color: "#2eff5c5c" }
                onClicked: win.navigating = false } }
    }
    // во время навигации маршрут пересчитывается от текущей точки
    Timer { interval: 15000; repeat: true; running: win.navigating; onTriggered: win.buildRoute() }

    // ===== кнопки справа =====
    Column {
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10; spacing: 8
        component Fab: Button {
            implicitWidth: 44; implicitHeight: 44
            contentItem: Text { text: parent.text; color: parent.checked ? "#4aa3ff" : "#f2f2f4"; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 22; color: "#e6141416"; border.color: "#22ffffff" }
        }
        Fab { id: follow; text: "◎"; checkable: true; checked: true; onClicked: if (checked) map.center = win.here }
        Fab { text: "+"; onClicked: map.zoomLevel += 1 }
        Fab { text: "−"; onClicked: map.zoomLevel -= 1 }
    }
    Text {
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 6; visible: win.navigating
        color: "#80808a"; font.pixelSize: 10
        text: gps.position.latitudeValid ? "GPS ±" + Math.round(gps.position.horizontalAccuracy || 0) + " м" : "GPS: нет сигнала — показан Таллин"
    }
}
