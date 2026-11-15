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

    property double refreshTimestamp: Date.now()
    property bool carportFallback: false

    readonly property string carportUrl: {
        var ent = root.carportFallback ? "camera.outside_carport" : "camera.carport"
        var url = root.haBaseUrl + "/api/camera_proxy/" + ent + "?t=" + root.refreshTimestamp
        if (root.haToken !== "") {
            url += "&token=" + encodeURIComponent(root.haToken)
        }
        return url
    }

    readonly property string drivewayUrl: {
        var url = root.haBaseUrl + "/api/camera_proxy/camera.driveway?t=" + root.refreshTimestamp
        if (root.haToken !== "") {
            url += "&token=" + encodeURIComponent(root.haToken)
        }
        return url
    }

    function refreshCameras() {
        refreshTimestamp = Date.now()
    }

    Timer {
        interval: 15000
        running: root.visible
        repeat: true
        onTriggered: root.refreshCameras()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Top Control Header Bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            radius: 12
            color: Qt.rgba(0.12, 0.14, 0.20, 0.72)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Label {
                    font.pixelSize: 18
                    text: "📹"
                }

                ColumnLayout {
                    spacing: 1

                    Label {
                        color: "#f8fafc"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        text: "Acreage Surveillance"
                    }

                    Label {
                        color: "#94a3b8"
                        font.pixelSize: 10
                        text: "Live Home Assistant camera proxy (Carport & Driveway)"
                    }
                }

                Item { Layout.fillWidth: true }

                // Prominent Refresh Button
                Rectangle {
                    id: refreshBtn
                    Layout.preferredWidth: 146
                    Layout.preferredHeight: 30
                    radius: 8
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
                        spacing: 6

                        Label {
                            color: refreshBtnHover.hovered ? "#00e5a3" : "#e2e8f0"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            text: "🔄 Refresh Cameras"
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
            spacing: 12

            // Container 1: Carport
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: Qt.rgba(0.10, 0.12, 0.18, 0.76)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Feed Top Strip
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: carportImg.status === Image.Ready ? "#00e5a3" : "#f59e0b"
                        }

                        Label {
                            color: "#f8fafc"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            text: "Carport"
                        }

                        Label {
                            color: "#64748b"
                            font.pixelSize: 10
                            text: root.carportFallback ? "(camera.outside_carport)" : "(camera.carport)"
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            color: "#94a3b8"
                            font.pixelSize: 10
                            font.family: "monospace"
                            text: carportImg.status === Image.Ready ? "LIVE" : "STANDBY"
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

                            onStatusChanged: {
                                if (carportImg.status === Image.Error && !root.carportFallback) {
                                    root.carportFallback = true
                                }
                            }
                        }

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: carportImg.status === Image.Loading
                            visible: running
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: carportImg.status === Image.Error || carportImg.status === Image.Null
                            spacing: 6

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: 32
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
                                font.pixelSize: 10
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
                radius: 14
                color: Qt.rgba(0.10, 0.12, 0.18, 0.76)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    // Feed Top Strip
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: drivewayImg.status === Image.Ready ? "#00e5a3" : "#f59e0b"
                        }

                        Label {
                            color: "#f8fafc"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            text: "Driveway"
                        }

                        Label {
                            color: "#64748b"
                            font.pixelSize: 10
                            text: "(camera.driveway)"
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            color: "#94a3b8"
                            font.pixelSize: 10
                            font.family: "monospace"
                            text: drivewayImg.status === Image.Ready ? "LIVE" : "STANDBY"
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
                            running: drivewayImg.status === Image.Loading
                            visible: running
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: drivewayImg.status === Image.Error || drivewayImg.status === Image.Null
                            spacing: 6

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                font.pixelSize: 32
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
                                font.pixelSize: 10
                                text: "Click Refresh to wake camera proxy"
                            }
                        }
                    }
                }
            }
        }
    }
}
