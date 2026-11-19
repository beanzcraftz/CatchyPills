pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Bespoke IoT device control grid backed by Home Assistant REST API and webhooks.
 * Features synchronized Climate control, Bluetti AC200 power station management,
 * Logitech G502 X PLUS telemetry, and one-click smart switch controls.
 */
Item {
    id: root

    readonly property bool hasFanConfigured: {
        var fan = (typeof configManager !== "undefined" && configManager)
            ? configManager.envValue("IOT_ENTITY_OFFICE_FAN", "").trim()
            : ""
        return fan !== ""
    }

    property bool lampState: false
    property bool outletState: false
    property bool fanState: false

    property string activeAc: "office" // "office" (Shed Gree AC) or "house" (Main House Mitsubishi 7.5kW)

    // Gree AC (Office / Shed)
    property string greeMode: "cool"
    property real greeTemp: 22.0
    property string greeFanMode: "auto"
    property string greeRoomTempText: ""

    // Mitsubishi AC (Main House 7.5kW)
    property string mitsubishiMode: "cool"
    property real mitsubishiTemp: 23.0
    property string mitsubishiFanMode: "High"
    property string mitsubishiRoomTempText: "22.5°C"

    readonly property string activeAcMode: activeAc === "house" ? root.mitsubishiMode : root.greeMode
    readonly property real activeAcTemp: activeAc === "house" ? root.mitsubishiTemp : root.greeTemp
    readonly property string activeAcFanMode: activeAc === "house" ? root.mitsubishiFanMode : root.greeFanMode
    readonly property string activeAcRoomTempText: activeAc === "house" ? root.mitsubishiRoomTempText : root.greeRoomTempText
    readonly property string activeAcTargetEntity: activeAc === "house"
        ? (typeof configManager !== "undefined" && configManager && configManager.envValue("IOT_ENTITY_MITSUBISHI_AC", "") !== ""
           ? configManager.envValue("IOT_ENTITY_MITSUBISHI_AC") : "climate.melview_38_8d_3d_4b_c9_ae")
        : (typeof configManager !== "undefined" && configManager && configManager.envValue("IOT_ENTITY_OFFICE_AC", "") !== ""
           ? configManager.envValue("IOT_ENTITY_OFFICE_AC") : "climate.office_greeac")

    readonly property var switchDevices: {
        var list = [
            { deviceId: "office_lamp", label: "Desk Lamp", subtitle: "Olamp", icon: "💡", state: root.lampState },
            { deviceId: "office_outlet", label: "Power Outlet", subtitle: "Grid Socket", icon: "🔌", state: root.outletState }
        ]
        if (root.hasFanConfigured) {
            list.push({ deviceId: "office_fan", label: "Arlec Fan", subtitle: "Airflow", icon: "🌀", state: root.fanState })
        }
        return list
    }

    function fetchStates() {
        var haBase = (typeof configManager !== "undefined" && configManager)
            ? configManager.envValue("IOT_WEBHOOK_BASE", "http://192.168.1.244:8123").replace(/\/+$/, "")
            : "http://192.168.1.244:8123"
        var token = (typeof configManager !== "undefined" && configManager)
            ? configManager.envValue("IOT_API_KEY", "")
            : ""

        var xhr = new XMLHttpRequest()
        xhr.open("GET", haBase + "/api/states")
        if (token !== "") {
            xhr.setRequestHeader("Authorization", "Bearer " + token)
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    for (var i = 0; i < data.length; ++i) {
                        var item = data[i]
                        if (item.entity_id === "light.office_olamp") {
                            root.lampState = (item.state === "on")
                        } else if (item.entity_id === "switch.office_socket") {
                            root.outletState = (item.state === "on")
                        } else if (item.entity_id === "fan.office_fan") {
                            root.fanState = (item.state === "on")
                        } else if (item.entity_id === "climate.office_greeac") {
                            root.greeMode = item.state
                            if (item.attributes) {
                                if (item.attributes.temperature !== undefined) {
                                    root.greeTemp = item.attributes.temperature
                                }
                                if (item.attributes.current_temperature !== undefined) {
                                    root.greeRoomTempText = Math.round(item.attributes.current_temperature) + "°C"
                                }
                                if (item.attributes.fan_mode !== undefined) {
                                    root.greeFanMode = item.attributes.fan_mode
                                }
                            }
                        } else if (item.entity_id === "climate.melview_38_8d_3d_4b_c9_ae") {
                            root.mitsubishiMode = item.state
                            if (item.attributes) {
                                if (item.attributes.temperature !== undefined) {
                                    root.mitsubishiTemp = item.attributes.temperature
                                }
                                if (item.attributes.current_temperature !== undefined) {
                                    root.mitsubishiRoomTempText = item.attributes.current_temperature + "°C"
                                }
                                if (item.attributes.fan_mode !== undefined) {
                                    root.mitsubishiFanMode = item.attributes.fan_mode
                                }
                            }
                        }
                    }
                } catch (e) {
                    console.warn("Failed to parse HA IoT states:", e)
                }
            }
        }
        xhr.send()
    }

    Component.onCompleted: {
        root.fetchStates()
    }

    onVisibleChanged: {
        if (visible) {
            root.fetchStates()
        }
    }

    Timer {
        interval: 15000
        running: root.visible
        repeat: true
        onTriggered: root.fetchStates()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Webhook / Home Assistant status strip
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 10
            color: Qt.rgba(0.16, 0.16, 0.24, 0.66)
            border.width: 1
            border.color: iotController.configured
                          ? Qt.rgba(0.0, 0.90, 0.64, 0.30)
                          : Qt.rgba(0.96, 0.62, 0.04, 0.38)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: 3.5
                    color: iotController.busy
                           ? "#38bdf8"
                           : (iotController.configured ? "#00e5a3" : "#f59e0b")
                }

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: "#e2e8f0"
                    font.pixelSize: 11
                    text: iotController.statusText
                }

                // Compact Tomorrow's Solar Forecast Readout Pill
                Rectangle {
                    visible: solarController.available && (solarController.tomorrowPeakTime !== "--" || solarController.tomorrowSolarKwh !== "--")
                    Layout.preferredHeight: 20
                    Layout.preferredWidth: tomorrowForecastRow.implicitWidth + 14
                    radius: 6
                    color: tomorrowForecastHover.hovered ? Qt.rgba(0.96, 0.62, 0.04, 0.28) : Qt.rgba(0.96, 0.62, 0.04, 0.16)
                    border.width: 1
                    border.color: tomorrowForecastHover.hovered ? "#fbbf24" : Qt.rgba(0.96, 0.62, 0.04, 0.45)

                    HoverHandler { id: tomorrowForecastHover }

                    ToolTip.visible: tomorrowForecastHover.hovered
                    ToolTip.delay: 300
                    ToolTip.text: "Tomorrow's Solar Production Forecast\nPeak Solar Time: " + solarController.tomorrowPeakTime + "\nEst. Energy: " + solarController.tomorrowSolarKwh

                    RowLayout {
                        id: tomorrowForecastRow
                        anchors.centerIn: parent
                        spacing: 4

                        Label {
                            font.pixelSize: 10
                            text: "☀️"
                        }

                        Label {
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: "#fbbf24"
                            text: "Peak: " + solarController.tomorrowPeakTime + " • " + solarController.tomorrowSolarKwh
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: cfgLbl.implicitWidth + 14
                    Layout.preferredHeight: 20
                    radius: 6
                    color: iotController.configured
                           ? Qt.rgba(0.0, 0.90, 0.64, 0.14)
                           : (cfgHover.hovered ? Qt.rgba(0.96, 0.62, 0.04, 0.25) : Qt.rgba(0.96, 0.62, 0.04, 0.14))
                    border.width: 1
                    border.color: iotController.configured ? Qt.rgba(0.0, 0.90, 0.64, 0.35) : Qt.rgba(0.96, 0.62, 0.04, 0.45)

                    HoverHandler { id: cfgHover }

                    Label {
                        id: cfgLbl
                        anchors.centerIn: parent
                        color: iotController.configured ? "#00e5a3" : "#f59e0b"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        text: iotController.configured ? "Ready" : "Configure ⚙"
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !iotController.configured
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: appController.openSettings()
                    }
                }
            }
        }

        // Balanced 2-Column Dashboard Grid
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // ═══════════════════════════════════════════════════════════
            // COLUMN 1 (LEFT): Climate & Peripheral Telemetry
            // ═══════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Card 1: Gree AC Climate Tile
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 136
                    radius: 14
                    color: acHover.hovered ? Qt.rgba(0.18, 0.20, 0.28, 0.88) : Qt.rgba(0.14, 0.14, 0.22, 0.72)
                    border.width: 1
                    border.color: acHover.hovered ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.10)

                    HoverHandler { id: acHover }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                font.pixelSize: 18
                                text: "❄️"
                            }

                            ColumnLayout {
                                spacing: 1
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: acHover.hovered ? "#00e5a3" : "#f8fafc"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    text: root.activeAc === "house" ? "Mitsubishi AC" : "Gree AC"
                                }

                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: "#94a3b8"
                                    font.pixelSize: 10
                                    text: root.activeAc === "house"
                                          ? (root.activeAcRoomTempText !== "" ? ("House 7.5kW • " + root.activeAcRoomTempText) : "House 7.5kW")
                                          : (root.activeAcRoomTempText !== "" ? ("Office Climate • " + root.activeAcRoomTempText) : "Office Climate")
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // AC Switcher: [ Shed | House ]
                            RowLayout {
                                spacing: 2

                                Rectangle {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 20
                                    radius: 5
                                    color: root.activeAc === "office" ? Qt.rgba(0.0, 0.90, 0.64, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                                    border.width: 1
                                    border.color: root.activeAc === "office" ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.12)

                                    Label {
                                        anchors.centerIn: parent
                                        font.pixelSize: 9
                                        font.weight: root.activeAc === "office" ? Font.Bold : Font.Normal
                                        color: root.activeAc === "office" ? "#00e5a3" : "#94a3b8"
                                        text: "Shed"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeAc = "office"
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 20
                                    radius: 5
                                    color: root.activeAc === "house" ? Qt.rgba(0.0, 0.90, 0.64, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                                    border.width: 1
                                    border.color: root.activeAc === "house" ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.12)

                                    Label {
                                        anchors.centerIn: parent
                                        font.pixelSize: 9
                                        font.weight: root.activeAc === "house" ? Font.Bold : Font.Normal
                                        color: root.activeAc === "house" ? "#00e5a3" : "#94a3b8"
                                        text: "House"
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeAc = "house"
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: acModeBadgeLbl.implicitWidth + 12
                                Layout.preferredHeight: 20
                                radius: 5
                                color: root.activeAcMode === "off" ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0.0, 0.90, 0.64, 0.18)
                                border.width: 1
                                border.color: root.activeAcMode === "off" ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.0, 0.90, 0.64, 0.45)

                                Label {
                                    id: acModeBadgeLbl
                                    anchors.centerIn: parent
                                    color: root.activeAcMode === "off" ? "#94a3b8" : "#00e5a3"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    text: root.activeAcMode.toUpperCase()
                                }
                            }
                        }

                        // Mode Buttons Row: ❄️ (cool), ☀️ (heat), 💧 (dry), ⏻ (off)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { mode: "cool", icon: "❄️", tip: "Cool Mode" },
                                    { mode: "heat", icon: "☀️", tip: "Heat Mode" },
                                    { mode: "dry", icon: "💧", tip: "Dry Mode" },
                                    { mode: "off", icon: "⏻", tip: "Turn Off" }
                                ]

                                delegate: Rectangle {
                                    id: modeBtn
                                    required property var modelData
                                    readonly property bool isActive: root.activeAcMode === modeBtn.modelData.mode
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 24
                                    radius: 6
                                    color: modeBtnMouse.pressed
                                           ? Qt.rgba(0.0, 0.90, 0.64, 0.35)
                                           : (modeBtn.isActive
                                              ? Qt.rgba(0.0, 0.90, 0.64, 0.22)
                                              : (modeBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)))
                                    border.width: 1
                                    border.color: modeBtn.isActive
                                                  ? "#00e5a3"
                                                  : (modeBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10))

                                    HoverHandler { id: modeBtnHover }

                                    ToolTip.visible: modeBtnHover.hovered
                                    ToolTip.delay: 300
                                    ToolTip.text: modeBtn.modelData.tip

                                    Label {
                                        anchors.centerIn: parent
                                        font.pixelSize: 11
                                        text: modeBtn.modelData.icon
                                    }

                                    MouseArea {
                                        id: modeBtnMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.activeAc === "house") {
                                                root.mitsubishiMode = modeBtn.modelData.mode
                                            } else {
                                                root.greeMode = modeBtn.modelData.mode
                                            }
                                            iotController.setClimateMode(root.activeAcTargetEntity, modeBtn.modelData.mode)
                                        }
                                    }
                                }
                            }
                        }

                        // Temperature Stepper: [ - ] 22°C [ + ]
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                id: minusBtn
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 24
                                radius: 6
                                color: minusMouse.pressed
                                       ? Qt.rgba(0.0, 0.90, 0.64, 0.30)
                                       : (minusHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                border.color: minusHover.hovered ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.10)

                                HoverHandler { id: minusHover }

                                Label {
                                    anchors.centerIn: parent
                                    color: "#f8fafc"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    text: "-"
                                }

                                MouseArea {
                                    id: minusMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var step = root.activeAc === "house" ? 0.5 : 1.0
                                        var minT = root.activeAc === "house" ? 16.0 : 16.0
                                        if (root.activeAcTemp > minT) {
                                            var newT = Math.round((root.activeAcTemp - step) * 2) / 2
                                            if (root.activeAc === "house") {
                                                root.mitsubishiTemp = newT
                                            } else {
                                                root.greeTemp = newT
                                            }
                                            iotController.setClimateTemperature(root.activeAcTargetEntity, newT)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.25)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)

                                Label {
                                    anchors.centerIn: parent
                                    color: "#00e5a3"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    text: (root.activeAc === "house"
                                          ? root.activeAcTemp.toFixed(1)
                                          : Math.round(root.activeAcTemp)) + "°C"
                                }
                            }

                            Rectangle {
                                id: plusBtn
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 24
                                radius: 6
                                color: plusMouse.pressed
                                       ? Qt.rgba(0.0, 0.90, 0.64, 0.30)
                                       : (plusHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                border.color: plusHover.hovered ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.10)

                                HoverHandler { id: plusHover }

                                Label {
                                    anchors.centerIn: parent
                                    color: "#f8fafc"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    text: "+"
                                }

                                MouseArea {
                                    id: plusMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var step = root.activeAc === "house" ? 0.5 : 1.0
                                        var maxT = root.activeAc === "house" ? 31.0 : 30.0
                                        if (root.activeAcTemp < maxT) {
                                            var newT = Math.round((root.activeAcTemp + step) * 2) / 2
                                            if (root.activeAc === "house") {
                                                root.mitsubishiTemp = newT
                                            } else {
                                                root.greeTemp = newT
                                            }
                                            iotController.setClimateTemperature(root.activeAcTargetEntity, newT)
                                        }
                                    }
                                }
                            }
                        }

                        // Fan Speed Control Row: Auto, Low, Med, High
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { mode: "auto", label: "Auto", tip: "Auto Fan Speed" },
                                    { mode: "low", label: "Low", tip: "Low Fan Speed" },
                                    { mode: "medium", label: "Med", tip: "Medium Fan Speed" },
                                    { mode: "high", label: "High", tip: "High Fan Speed" }
                                ]

                                delegate: Rectangle {
                                    id: fanBtn
                                    required property var modelData
                                    readonly property bool isActive: root.activeAcFanMode.toLowerCase() === fanBtn.modelData.mode.toLowerCase()
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    radius: 6
                                    color: fanBtnMouse.pressed
                                           ? Qt.rgba(0.0, 0.90, 0.64, 0.35)
                                           : (fanBtn.isActive
                                              ? Qt.rgba(0.0, 0.90, 0.64, 0.22)
                                              : (fanBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)))
                                    border.width: 1
                                    border.color: fanBtn.isActive
                                                  ? "#00e5a3"
                                                  : (fanBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10))

                                    HoverHandler { id: fanBtnHover }

                                    ToolTip.visible: fanBtnHover.hovered
                                    ToolTip.delay: 300
                                    ToolTip.text: fanBtn.modelData.tip

                                    Label {
                                        anchors.centerIn: parent
                                        font.pixelSize: 10
                                        font.weight: fanBtn.isActive ? Font.DemiBold : Font.Normal
                                        color: fanBtn.isActive ? "#00e5a3" : "#f8fafc"
                                        text: fanBtn.modelData.label
                                    }

                                    MouseArea {
                                        id: fanBtnMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var speed = fanBtn.modelData.mode
                                            if (root.activeAc === "house") {
                                                if (speed === "low") speed = "Low"
                                                else if (speed === "medium") speed = "Medium"
                                                else if (speed === "high") speed = "High"
                                                root.mitsubishiFanMode = speed
                                            } else {
                                                root.greeFanMode = speed
                                            }
                                            iotController.setClimateFanMode(root.activeAcTargetEntity, speed)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Card 2: Logitech G502 X PLUS Peripheral Tile
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 136
                    radius: 14
                    color: mouseHover.hovered ? Qt.rgba(0.18, 0.20, 0.28, 0.88) : Qt.rgba(0.14, 0.14, 0.22, 0.72)
                    border.width: 1
                    border.color: mouseHover.hovered ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.10)

                    HoverHandler { id: mouseHover }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                font.pixelSize: 18
                                text: "🖱️"
                            }

                            ColumnLayout {
                                spacing: 1
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: mouseHover.hovered ? "#00e5a3" : "#f8fafc"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    text: "G502 X PLUS"
                                }

                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: "#94a3b8"
                                    font.pixelSize: 10
                                    text: peripheralController.connected ? peripheralController.statusText : "Logitech Lightspeed"
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredWidth: mouseBattBadgeLbl.implicitWidth + 12
                                Layout.preferredHeight: 18
                                radius: 6
                                color: peripheralController.connected
                                       ? (peripheralController.batteryPercentage >= 0 && peripheralController.batteryPercentage <= 20
                                          ? Qt.rgba(0.94, 0.27, 0.27, 0.22)
                                          : Qt.rgba(0.0, 0.90, 0.64, 0.18))
                                       : Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                border.color: peripheralController.connected
                                              ? (peripheralController.batteryPercentage >= 0 && peripheralController.batteryPercentage <= 20
                                                 ? "#ef4444"
                                                 : Qt.rgba(0.0, 0.90, 0.64, 0.45))
                                              : Qt.rgba(1, 1, 1, 0.10)

                                Label {
                                    id: mouseBattBadgeLbl
                                    anchors.centerIn: parent
                                    color: peripheralController.connected
                                           ? (peripheralController.batteryPercentage >= 0 && peripheralController.batteryPercentage <= 20 ? "#ef4444" : "#00e5a3")
                                           : "#94a3b8"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    text: peripheralController.connected ? peripheralController.mouseBattery : "Asleep"
                                }
                            }
                        }

                        // Readout Row: DPI and Battery side-by-side
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // DPI Readout
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.25)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Label {
                                        font.pixelSize: 10
                                        text: "🎯"
                                    }

                                    Label {
                                        color: "#38bdf8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        text: peripheralController.connected ? peripheralController.mouseDpi : "-- DPI"
                                    }
                                }
                            }

                            // Battery Readout
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.25)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Label {
                                        font.pixelSize: 10
                                        text: "🔋"
                                    }

                                    Label {
                                        color: peripheralController.connected && peripheralController.batteryPercentage <= 20 ? "#ef4444" : "#00e5a3"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        text: peripheralController.connected ? ("Battery: " + peripheralController.mouseBattery) : "Offline"
                                    }
                                }
                            }
                        }

                        // Status bar & Refresh button
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.20)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.06)

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: peripheralController.connected ? "#00e5a3" : "#64748b"
                                    }

                                    Label {
                                        text: peripheralController.connected ? "Lightspeed Active" : "Mouse Standby"
                                        font.pixelSize: 10
                                        color: peripheralController.connected ? "#f8fafc" : "#94a3b8"
                                    }
                                }
                            }

                            Rectangle {
                                id: syncBtn
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 24
                                radius: 6
                                color: syncMouse.pressed
                                       ? Qt.rgba(0.0, 0.90, 0.64, 0.35)
                                       : (syncHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                border.color: syncHover.hovered ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.10)

                                HoverHandler { id: syncHover }
                                ToolTip.visible: syncHover.hovered
                                ToolTip.delay: 300
                                ToolTip.text: "Query Solaar Telemetry"

                                Label {
                                    anchors.centerIn: parent
                                    font.pixelSize: 11
                                    text: "🔄"
                                }

                                MouseArea {
                                    id: syncMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: peripheralController.refresh()
                                }
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════════════════════════
            // COLUMN 2 (RIGHT): Bluetti Power & Smart Switches
            // ═══════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Card 1: Bluetti AC200 Power Station Tile
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 136
                    radius: 14
                    color: bluettiHover.hovered ? Qt.rgba(0.18, 0.20, 0.28, 0.88) : Qt.rgba(0.14, 0.14, 0.22, 0.72)
                    border.width: 1
                    border.color: bluettiHover.hovered ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.10)

                    HoverHandler { id: bluettiHover }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                font.pixelSize: 18
                                text: "🔋"
                            }

                            ColumnLayout {
                                spacing: 1
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: bluettiHover.hovered ? "#00e5a3" : "#f8fafc"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    text: "Bluetti AC200"
                                }

                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    color: "#94a3b8"
                                    font.pixelSize: 10
                                    text: solarController.hasBattery
                                          ? (solarController.batteryPercentage + "% Battery" + ((solarController.tomorrowPeakTime !== "--" || solarController.tomorrowSolarKwh !== "--") ? (" • Tomorrow: " + solarController.tomorrowSolarKwh) : ""))
                                          : ((solarController.tomorrowPeakTime !== "--" || solarController.tomorrowSolarKwh !== "--") ? ("Tomorrow: " + solarController.tomorrowSolarKwh) : "Power Station")
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                visible: solarController.hasBattery
                                Layout.preferredWidth: battBadgeLbl.implicitWidth + 12
                                Layout.preferredHeight: 18
                                radius: 6
                                color: solarController.batteryPercentage <= 15
                                       ? Qt.rgba(0.94, 0.27, 0.27, 0.22)
                                       : Qt.rgba(0.0, 0.90, 0.64, 0.18)
                                border.width: 1
                                border.color: solarController.batteryPercentage <= 15
                                              ? "#ef4444"
                                              : Qt.rgba(0.0, 0.90, 0.64, 0.45)

                                Label {
                                    id: battBadgeLbl
                                    anchors.centerIn: parent
                                    color: solarController.batteryPercentage <= 15 ? "#ef4444" : "#00e5a3"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    text: solarController.batteryPercentage + "%"
                                }
                            }
                        }

                        // Telemetry Row: In and Out power side-by-side
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.25)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Label {
                                        font.pixelSize: 10
                                        text: "⚡"
                                    }

                                    Label {
                                        color: "#38bdf8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        text: solarController.bluettiInputPowerText
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.25)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Label {
                                        font.pixelSize: 10
                                        text: "🔌"
                                    }

                                    Label {
                                        color: "#f59e0b"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        text: solarController.bluettiOutputPowerText
                                    }
                                }
                            }
                        }

                        // Inverter Toggles Row: AC and DC Inverters
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            // AC Inverter Button
                            Rectangle {
                                id: acInverterBtn
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: 6
                                color: acMouse.pressed
                                       ? Qt.rgba(0.0, 0.90, 0.64, 0.35)
                                       : (iotController.bluettiAcOn
                                          ? Qt.rgba(0.0, 0.90, 0.64, 0.22)
                                          : (acBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)))
                                border.width: 1
                                border.color: iotController.bluettiAcOn
                                              ? "#00e5a3"
                                              : (acBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10))

                                HoverHandler { id: acBtnHover }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: iotController.bluettiAcOn ? "#00e5a3" : "#64748b"
                                    }

                                    Label {
                                        text: "AC Inverter"
                                        font.pixelSize: 10
                                        font.weight: iotController.bluettiAcOn ? Font.DemiBold : Font.Normal
                                        color: iotController.bluettiAcOn ? "#00e5a3" : "#f8fafc"
                                    }
                                }

                                MouseArea {
                                    id: acMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: iotController.toggleBluettiAc(!iotController.bluettiAcOn)
                                }
                            }

                            // DC Inverter Button
                            Rectangle {
                                id: dcInverterBtn
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: 6
                                color: dcMouse.pressed
                                       ? Qt.rgba(0.0, 0.90, 0.64, 0.35)
                                       : (iotController.bluettiDcOn
                                          ? Qt.rgba(0.0, 0.90, 0.64, 0.22)
                                          : (dcBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)))
                                border.width: 1
                                border.color: iotController.bluettiDcOn
                                              ? "#00e5a3"
                                              : (dcBtnHover.hovered ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10))

                                HoverHandler { id: dcBtnHover }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Rectangle {
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        color: iotController.bluettiDcOn ? "#00e5a3" : "#64748b"
                                    }

                                    Label {
                                        text: "DC Inverter"
                                        font.pixelSize: 10
                                        font.weight: iotController.bluettiDcOn ? Font.DemiBold : Font.Normal
                                        color: iotController.bluettiDcOn ? "#00e5a3" : "#f8fafc"
                                    }
                                }

                                MouseArea {
                                    id: dcMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: iotController.toggleBluettiDc(!iotController.bluettiDcOn)
                                }
                            }
                        }
                    }
                }

                // Card 2: Smart Switches Container (Desk Lamp, Power Outlet, etc.)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 136
                    spacing: 8

                    Repeater {
                        model: root.switchDevices

                        delegate: Rectangle {
                            id: switchTile
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: switchMouse.pressed
                                   ? Qt.rgba(0.0, 0.90, 0.64, 0.18)
                                   : (switchHover.hovered ? Qt.rgba(0.18, 0.20, 0.28, 0.88) : Qt.rgba(0.14, 0.14, 0.22, 0.72))
                            border.width: 1
                            border.color: switchHover.hovered
                                          ? "#00e5a3"
                                          : (switchTile.modelData.state ? Qt.rgba(0.0, 0.90, 0.64, 0.35) : Qt.rgba(1, 1, 1, 0.10))

                            HoverHandler { id: switchHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Label {
                                    font.pixelSize: 20
                                    text: switchTile.modelData.icon
                                }

                                ColumnLayout {
                                    spacing: 1
                                    Label {
                                        text: switchTile.modelData.label
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: switchHover.hovered ? "#00e5a3" : "#f8fafc"
                                    }

                                    Label {
                                        text: switchTile.modelData.subtitle
                                        font.pixelSize: 10
                                        color: "#94a3b8"
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Interactive State Badge / Toggle Pill
                                Rectangle {
                                    Layout.preferredWidth: 62
                                    Layout.preferredHeight: 24
                                    radius: 7
                                    color: switchTile.modelData.state
                                           ? Qt.rgba(0.0, 0.90, 0.64, 0.20)
                                           : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1
                                    border.color: switchTile.modelData.state
                                                  ? "#00e5a3"
                                                  : Qt.rgba(1, 1, 1, 0.15)

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Rectangle {
                                            Layout.preferredWidth: 6
                                            Layout.preferredHeight: 6
                                            radius: 3
                                            color: switchTile.modelData.state ? "#00e5a3" : "#64748b"
                                        }

                                        Label {
                                            text: switchTile.modelData.state ? "ON" : "OFF"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: switchTile.modelData.state ? "#00e5a3" : "#94a3b8"
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: switchMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (switchTile.modelData.deviceId === "office_lamp") {
                                        root.lampState = !root.lampState
                                    } else if (switchTile.modelData.deviceId === "office_outlet") {
                                        root.outletState = !root.outletState
                                    } else if (switchTile.modelData.deviceId === "office_fan") {
                                        root.fanState = !root.fanState
                                    }
                                    iotController.triggerDevice(switchTile.modelData.deviceId)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
