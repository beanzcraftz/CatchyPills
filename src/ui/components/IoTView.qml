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
        { deviceId: "bluetti_ac200", label: "Bluetti AC200", subtitle: "Power Station", icon: "🔋", accent: "#00e5a3" },
        { deviceId: "g502_mouse", label: "G502 X PLUS", subtitle: "Gaming Mouse", icon: "🖱️", accent: "#38bdf8" },
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

        // Glassmorphism Office IoT & Bluetti Toggle Grid
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: root.devices

                    delegate: Rectangle {
                        id: iotTile
                        required property var modelData
                        readonly property bool isClimateTile: iotTile.modelData.deviceId === "office_ac"
                        readonly property bool isBluettiTile: iotTile.modelData.deviceId === "bluetti_ac200"
                        readonly property bool isMouseTile: iotTile.modelData.deviceId === "g502_mouse"
                        readonly property bool isCustomTile: iotTile.isClimateTile || iotTile.isBluettiTile || iotTile.isMouseTile
                        property int currentTemp: 22
                        property string currentMode: "cool"
                        property string currentFanMode: "auto"
                        readonly property bool isLastTriggered:
                            iotController.lastTriggeredDevice === iotTile.modelData.deviceId
                            || (iotTile.isClimateTile && (iotController.lastTriggeredDevice.indexOf("ac") !== -1 || iotController.lastTriggeredDevice.indexOf("climate") !== -1))
                            || (iotTile.isBluettiTile && (iotController.lastTriggeredDevice.indexOf("bluetti") !== -1 || iotController.lastTriggeredDevice.indexOf("ac200") !== -1))

                        Layout.fillWidth: true
                        Layout.preferredHeight: iotTile.isCustomTile ? 136 : 64
                        radius: 14
                        color: (!iotTile.isCustomTile && tileMouse.pressed)
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
                            spacing: iotTile.isCustomTile ? 6 : 4

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
                                        text: iotTile.isBluettiTile && solarController.hasBattery
                                              ? (solarController.batteryPercentage + "% Battery")
                                              : (iotTile.isMouseTile
                                                 ? (peripheralController.connected ? peripheralController.statusText : "Logitech Lightspeed")
                                                 : iotTile.modelData.subtitle)
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Action / Toggle Badge (only on non-custom tiles)
                                Rectangle {
                                    visible: !iotTile.isCustomTile
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

                                // Battery badge for Bluetti AC200 tile
                                Rectangle {
                                    visible: iotTile.isBluettiTile && solarController.hasBattery
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

                                // Battery badge for G502 X PLUS tile
                                Rectangle {
                                    visible: iotTile.isMouseTile
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

                            // Climate Advanced Controls (Mode Row, Temp Stepper, Fan Speed)
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
                                            readonly property bool isActive: iotTile.currentFanMode === fanBtn.modelData.mode
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
                                                    iotTile.currentFanMode = fanBtn.modelData.mode
                                                    iotController.setClimateFanMode("climate.gree_ac", fanBtn.modelData.mode)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Bluetti AC200 Controls (Telemetry Readout + Inverter Toggles)
                            ColumnLayout {
                                visible: iotTile.isBluettiTile
                                Layout.fillWidth: true
                                spacing: 6

                                // Top half: Display real-time Input Power and Output Power side-by-side
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

                                // Bottom half: Create two toggle buttons side-by-side labelled "AC Inverter" and "DC Inverter"
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
                                                  : (acHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)))
                                        border.width: 1
                                        border.color: iotController.bluettiAcOn
                                                      ? "#00e5a3"
                                                      : (acHover.hovered ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10))

                                        HoverHandler { id: acHover }

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
                                                  : (dcHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)))
                                        border.width: 1
                                        border.color: iotController.bluettiDcOn
                                                      ? "#00e5a3"
                                                      : (dcHover.hovered ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.10))

                                        HoverHandler { id: dcHover }

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

                            // G502 X PLUS Telemetry (DPI and Battery)
                            ColumnLayout {
                                visible: iotTile.isMouseTile
                                Layout.fillWidth: true
                                spacing: 6

                                // Top half: Display DPI and Battery side-by-side
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

                                // Bottom half: Connection state and Refresh button
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

                            Item {
                                visible: !iotTile.isCustomTile
                                Layout.fillHeight: true
                            }
                        }

                        // MouseArea covering the tile for standard 1-click toggle devices
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            enabled: !iotTile.isCustomTile
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: iotController.triggerDevice(iotTile.modelData.deviceId)
                        }
                    }
                }
            }
        }
    }
}
