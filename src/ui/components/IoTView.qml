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
        { deviceId: "office_ac", label: "Gree AC", subtitle: "Office Climate", icon: "❄️", accent: "#38bdf8" },
        { deviceId: "office_fan", label: "Arlec Fan", subtitle: "Airflow", icon: "🌀", accent: "#2dd4bf" },
        { deviceId: "office_outlet", label: "Power Outlet", subtitle: "Grid Socket", icon: "🔌", accent: "#f59e0b" },
        { deviceId: "office_lamp", label: "Desk Lamp", subtitle: "Olamp", icon: "💡", accent: "#00e5a3" }
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

        // 2x2 Glassmorphism Office IoT Toggle Grid
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            Repeater {
                model: root.devices

                delegate: Rectangle {
                    id: iotTile
                    required property var modelData
                    readonly property bool isClimateTile: iotTile.modelData.deviceId === "office_ac"
                    property int currentTemp: 22
                    property string currentMode: "cool"
                    readonly property bool isLastTriggered:
                        iotController.lastTriggeredDevice === iotTile.modelData.deviceId
                        || (iotTile.isClimateTile && (iotController.lastTriggeredDevice.indexOf("ac") !== -1 || iotController.lastTriggeredDevice.indexOf("climate") !== -1))

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 14
                    color: (!iotTile.isClimateTile && tileMouse.pressed)
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
                        spacing: iotTile.isClimateTile ? 6 : 4

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                font.pixelSize: 18
                                text: iotTile.modelData.icon
                            }

                            ColumnLayout {
                                spacing: 1
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

                            Item { Layout.fillWidth: true }

                            // Action / Toggle Badge (only on non-climate tiles)
                            Rectangle {
                                visible: !iotTile.isClimateTile
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

                        // Climate Advanced Controls (Mode Row & Temp Stepper)
                        ColumnLayout {
                            visible: iotTile.isClimateTile
                            Layout.fillWidth: true
                            spacing: 6

                            // Mode Icon Row: ❄️ (cool), ☀️ (heat), 💧 (dry), ⏻ (off)
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
                                        readonly property bool isActive: iotTile.currentMode === modeBtn.modelData.mode
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
                                                iotTile.currentMode = modeBtn.modelData.mode
                                                iotController.setClimateMode("climate.gree_ac", modeBtn.modelData.mode)
                                            }
                                        }
                                    }
                                }
                            }

                            // Precise Temperature Control Stepper: [ - ] 22°C [ + ]
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
                                            if (iotTile.currentTemp > 16) {
                                                iotTile.currentTemp -= 1
                                                iotController.setClimateTemperature("climate.gree_ac", iotTile.currentTemp)
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
                                        text: iotTile.currentTemp + "°C"
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
                                            if (iotTile.currentTemp < 30) {
                                                iotTile.currentTemp += 1
                                                iotController.setClimateTemperature("climate.gree_ac", iotTile.currentTemp)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            visible: !iotTile.isClimateTile
                            Layout.fillHeight: true
                        }
                    }

                    // MouseArea covering the tile for standard 1-click toggle devices
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        enabled: !iotTile.isClimateTile
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: iotController.triggerDevice(iotTile.modelData.deviceId)
                    }
                }
            }
        }
    }
}
