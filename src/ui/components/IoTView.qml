pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Bespoke IoT device trigger grid backed by IOT_WEBHOOK_BASE / IOT_WEBHOOK_*
 * loaded from ~/.config/catchypills/.env.
 */
Item {
    id: root

    readonly property var devices: [
        { deviceId: "shed_ac", label: "Shed AC", subtitle: "Workshop Climate", icon: "❄️", accent: "#38bdf8" },
        { deviceId: "front_gate", label: "Front Gate", subtitle: "Driveway Entry", icon: "🚧", accent: "#f59e0b" },
        { deviceId: "office_lights", label: "Office Lights", subtitle: "Desk & Ceiling", icon: "💡", accent: "#00e5a3" },
        { deviceId: "shed_lights", label: "Shed Lights", subtitle: "Workshop Bays", icon: "🔆", accent: "#facc15" },
        { deviceId: "air_compressor", label: "Compressor", subtitle: "Shop Air Supply", icon: "💨", accent: "#a78bfa" },
        { deviceId: "all_off", label: "All Zones Off", subtitle: "Shutdown Scene", icon: "🌙", accent: "#2dd4bf" }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Webhook status strip
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
                    radius: 4
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

        // 3x2 Glassmorphism IoT Toggle Grid
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: root.devices

                delegate: Rectangle {
                    id: iotTile
                    required property var modelData
                    readonly property bool isLastTriggered:
                        iotController.lastTriggeredDevice === iotTile.modelData.deviceId

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 14
                    color: tileMouse.pressed
                           ? Qt.rgba(0.0, 0.90, 0.64, 0.18)
                           : (tileHover.hovered
                              ? Qt.rgba(0.20, 0.21, 0.31, 0.85)
                              : Qt.rgba(0.14, 0.14, 0.22, 0.72))
                    border.width: 1
                    border.color: tileHover.hovered
                                  ? "#00e5a3"
                                  : (isLastTriggered ? Qt.rgba(0.0, 0.90, 0.64, 0.45) : Qt.rgba(1, 1, 1, 0.10))

                    HoverHandler { id: tileHover }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                font.pixelSize: 18
                                text: iotTile.modelData.icon
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredWidth: actionBadgeLbl.implicitWidth + 12
                                Layout.preferredHeight: 18
                                radius: 6
                                color: iotTile.isLastTriggered
                                       ? Qt.rgba(0.0, 0.90, 0.64, 0.18)
                                       : Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                border.color: iotTile.isLastTriggered
                                              ? Qt.rgba(0.0, 0.90, 0.64, 0.45)
                                              : Qt.rgba(1, 1, 1, 0.10)

                                Label {
                                    id: actionBadgeLbl
                                    anchors.centerIn: parent
                                    color: iotTile.isLastTriggered ? "#00e5a3" : "#94a3b8"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    text: iotTile.isLastTriggered ? "Sent" : "Toggle"
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: tileHover.hovered ? "#00e5a3" : "#f8fafc"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            text: iotTile.modelData.label
                        }

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: "#94a3b8"
                            font.pixelSize: 10
                            text: iotTile.modelData.subtitle
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: iotController.triggerDevice(iotTile.modelData.deviceId)
                    }
                }
            }
        }
    }
}
