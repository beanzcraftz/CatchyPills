pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Acreage Camera Tab displaying Cedar Vale Carport and Driveway
 * camera feeds routed through Home Assistant's camera proxy.
 */
Item {
    id: root

    readonly property string haBaseUrl: {
        var base = (typeof configManager !== "undefined" && configManager)
            ? configManager.envValue("IOT_WEBHOOK_BASE", "http://192.168.1.244:8123")
            : "http://192.168.1.244:8123"
        return base.replace(/\/+$/, "")
    }
    readonly property string haToken: (typeof configManager !== "undefined" && configManager)
        ? configManager.envValue("IOT_API_KEY", "")
        : ""

    readonly property string carportEntity: (typeof configManager !== "undefined" && configManager)
        ? configManager.envValue("CAM_CARPORT_ENTITY", "camera.outside_carport")
        : "camera.outside_carport"
    readonly property string drivewayEntity: (typeof configManager !== "undefined" && configManager)
        ? configManager.envValue("CAM_DRIVEWAY_ENTITY", "camera.driveway")
        : "camera.driveway"

    property double refreshTimestamp: Date.now()
    property bool refreshing: false
    property string carportBattery: ""
    property string drivewayBattery: ""
    property bool carportSolarCharging: false
    property bool drivewaySolarCharging: false
    property bool carportMotion: false
    property bool drivewayMotion: false
    property string lastUpdatedText: ""

    readonly property string carportUrl: root.haBaseUrl + "/api/camera_proxy/" + root.carportEntity + "?t=" + root.refreshTimestamp
    readonly property string drivewayUrl: root.haBaseUrl + "/api/camera_proxy/" + root.drivewayEntity + "?t=" + root.refreshTimestamp

    function refreshCameras() {
        if (root.refreshing) {
            return
        }
        root.refreshing = true
        root.refreshTimestamp = Date.now()

        // 1. Wake & capture live frame from both Eufy battery cameras via HA button press
        var xhr = new XMLHttpRequest()
        xhr.open("POST", root.haBaseUrl + "/api/services/button/press")
        xhr.setRequestHeader("Content-Type", "application/json")
        if (root.haToken !== "") {
            xhr.setRequestHeader("Authorization", "Bearer " + root.haToken)
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                // Settle and bust cache so the newly captured frame loads
                wakeSettleTimer.restart()
            }
        }
        xhr.send(JSON.stringify({
            "entity_id": [
                "button.outside_carport_capture_live_image",
                "button.driveway_capture_live_image"
            ]
        }))

        // 2. Query HA sensor states for battery, solar charging, and motion
        fetchTelemetry()
    }

    function fetchTelemetry() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", root.haBaseUrl + "/api/states")
        if (root.haToken !== "") {
            xhr.setRequestHeader("Authorization", "Bearer " + root.haToken)
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    for (var i = 0; i < data.length; ++i) {
                        var item = data[i]
                        if (item.entity_id === "sensor.outside_carport_battery") {
                            root.carportBattery = item.state
                        } else if (item.entity_id === "sensor.driveway_battery") {
                            root.drivewayBattery = item.state
                        } else if (item.entity_id === "binary_sensor.outside_carport_solar_charging") {
                            root.carportSolarCharging = (item.state === "on")
                        } else if (item.entity_id === "binary_sensor.driveway_solar_charging") {
                            root.drivewaySolarCharging = (item.state === "on")
                        } else if (item.entity_id === "binary_sensor.outside_carport_motion") {
                            root.carportMotion = (item.state === "on")
                        } else if (item.entity_id === "binary_sensor.driveway_motion") {
                            root.drivewayMotion = (item.state === "on")
                        }
                    }
                    var now = new Date()
                    var h = now.getHours()
                    var m = now.getMinutes()
                    var s = now.getSeconds()
                    var pad = function(n) { return n < 10 ? "0" + n : "" + n }
                    root.lastUpdatedText = pad(h) + ":" + pad(m) + ":" + pad(s)
                } catch (e) {
                    console.warn("Failed to parse HA camera telemetry:", e)
                }
            }
        }
        xhr.send()
    }

    Timer {
        id: wakeSettleTimer
        interval: 1800
        repeat: false
        onTriggered: {
            root.refreshTimestamp = Date.now()
            root.refreshing = false
        }
    }

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.refreshCameras()
    }

    Component.onCompleted: {
        root.refreshCameras()
    }

    onVisibleChanged: {
        if (visible) {
            root.refreshCameras()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Top Control Header Bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            radius: 10
            color: Qt.rgba(0.12, 0.14, 0.20, 0.72)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Label {
                    font.pixelSize: 16
                    text: "📹"
                }

                ColumnLayout {
                    spacing: 0

                    Label {
                        color: "#f8fafc"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        text: "Acreage Surveillance"
                    }

                    Label {
                        color: "#94a3b8"
                        font.pixelSize: 9
                        text: root.lastUpdatedText !== ""
                              ? "Live HA camera proxy • Updated " + root.lastUpdatedText
                              : "Live Home Assistant camera proxy (Carport & Driveway)"
                    }
                }

                Item { Layout.fillWidth: true }

                // Prominent Refresh Button
                Rectangle {
                    id: refreshBtn
                    Layout.preferredWidth: 144
                    Layout.preferredHeight: 26
                    radius: 7
                    color: refreshBtnHover.hovered
                           ? Qt.rgba(0.0, 0.90, 0.64, 0.22)
                           : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    border.color: refreshBtnHover.hovered
                                  ? Qt.rgba(0.0, 0.90, 0.64, 0.60)
                                  : Qt.rgba(1, 1, 1, 0.15)

                    HoverHandler { id: refreshBtnHover }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        Label {
                            font.pixelSize: 11
                            text: root.refreshing ? "⏳" : "🔄"
                        }

                        Label {
                            color: refreshBtnHover.hovered ? "#00e5a3" : "#e2e8f0"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            text: root.refreshing ? "Capturing..." : "Refresh Cameras"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshCameras()
                    }
                }
            }
        }

        // Camera Feed Display Grid (Carport & Driveway)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // Container 1: Carport
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Qt.rgba(0.10, 0.12, 0.18, 0.76)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // Feed Top Strip
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: 3.5
                            color: carportImg.status === Image.Ready ? "#00e5a3" : "#f59e0b"
                        }

                        Label {
                            color: "#f8fafc"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            text: "Carport"
                        }

                        Label {
                            visible: root.carportMotion
                            color: "#f59e0b"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            text: "🚶 MOTION"
                        }

                        Item { Layout.fillWidth: true }

                        // Telemetry badge (solar & battery)
                        Rectangle {
                            implicitWidth: carportMetaRow.implicitWidth + 8
                            implicitHeight: 18
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)

                            RowLayout {
                                id: carportMetaRow
                                anchors.centerIn: parent
                                spacing: 4

                                Label {
                                    font.pixelSize: 9
                                    color: "#00e5a3"
                                    text: "☀️ CHG"
                                    visible: root.carportSolarCharging
                                }

                                Label {
                                    font.pixelSize: 9
                                    color: {
                                        var b = parseInt(root.carportBattery)
                                        if (isNaN(b) || b > 20) return "#94a3b8"
                                        return "#ff4c4c"
                                    }
                                    text: "🔋 " + (root.carportBattery !== "" ? root.carportBattery + "%" : "--%")
                                }
                            }
                        }

                        Label {
                            color: "#94a3b8"
                            font.pixelSize: 9
                            font.family: "monospace"
                            text: root.refreshing ? "REFRESHING" : (carportImg.status === Image.Ready ? "LIVE" : "STANDBY")
                        }
                    }

                    // Feed Viewport
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "#070a0e"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        clip: true

                        Image {
                            id: carportImg
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            source: root.carportUrl
                        }

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: carportImg.status === Image.Loading || root.refreshing
                            visible: running
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: carportImg.status === Image.Error || carportImg.status === Image.Null
                            spacing: 4

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: 28
                                text: "🚗"
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                color: "#94a3b8"
                                font.pixelSize: 11
                                text: "Carport Feed Standby"
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                color: "#64748b"
                                font.pixelSize: 9
                                text: "Click Refresh to wake camera proxy"
                            }
                        }
                    }
                }
            }

            // Container 2: Driveway
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: Qt.rgba(0.10, 0.12, 0.18, 0.76)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    // Feed Top Strip
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            implicitWidth: 7
                            implicitHeight: 7
                            radius: 3.5
                            color: drivewayImg.status === Image.Ready ? "#00e5a3" : "#f59e0b"
                        }

                        Label {
                            color: "#f8fafc"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            text: "Driveway"
                        }

                        Label {
                            visible: root.drivewayMotion
                            color: "#f59e0b"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            text: "🚶 MOTION"
                        }

                        Item { Layout.fillWidth: true }

                        // Telemetry badge (solar & battery)
                        Rectangle {
                            implicitWidth: drivewayMetaRow.implicitWidth + 8
                            implicitHeight: 18
                            radius: 5
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.10)

                            RowLayout {
                                id: drivewayMetaRow
                                anchors.centerIn: parent
                                spacing: 4

                                Label {
                                    font.pixelSize: 9
                                    color: "#00e5a3"
                                    text: "☀️ CHG"
                                    visible: root.drivewaySolarCharging
                                }

                                Label {
                                    font.pixelSize: 9
                                    color: {
                                        var b = parseInt(root.drivewayBattery)
                                        if (isNaN(b) || b > 20) return "#94a3b8"
                                        return "#ff4c4c"
                                    }
                                    text: "🔋 " + (root.drivewayBattery !== "" ? root.drivewayBattery + "%" : "--%")
                                }
                            }
                        }

                        Label {
                            color: "#94a3b8"
                            font.pixelSize: 9
                            font.family: "monospace"
                            text: root.refreshing ? "REFRESHING" : (drivewayImg.status === Image.Ready ? "LIVE" : "STANDBY")
                        }
                    }

                    // Feed Viewport
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: "#070a0e"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)
                        clip: true

                        Image {
                            id: drivewayImg
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            source: root.drivewayUrl
                        }

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: drivewayImg.status === Image.Loading || root.refreshing
                            visible: running
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: drivewayImg.status === Image.Error || drivewayImg.status === Image.Null
                            spacing: 4

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: 28
                                text: "🛣️"
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                color: "#94a3b8"
                                font.pixelSize: 11
                                text: "Driveway Feed Standby"
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                color: "#64748b"
                                font.pixelSize: 9
                                text: "Click Refresh to wake camera proxy"
                            }
                        }
                    }
                }
            }
        }
    }
}
