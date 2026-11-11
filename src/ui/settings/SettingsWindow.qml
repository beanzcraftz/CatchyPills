import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Window {
    id: root
    width: 560
    height: 680
    minimumWidth: 500
    minimumHeight: 560
    title: "CatchyPills Settings"
    color: "#1e1e2e"

    property bool revealIotKey: false
    property bool revealSolarKey: false
    property bool revealWorklogKey: false
    property string envFeedbackText: ""

    function syncEnvFields() {
        iotWebhookField.text = configManager.envValue("IOT_WEBHOOK_BASE")
        iotKeyField.text = configManager.envValue("IOT_API_KEY")
        solarUrlField.text = configManager.envValue("SOLAR_API_URL")
        solarKeyField.text = configManager.envValue("SOLAR_API_KEY")
        var pollMs = parseInt(configManager.envValue("SOLAR_POLL_INTERVAL_MS", "15000"), 10)
        solarIntervalField.text = isNaN(pollMs) || pollMs <= 0
                                  ? "15"
                                  : Math.max(2, Math.round(pollMs / 1000)).toString()
        worklogDbField.text = configManager.envValue("WORKLOG_DB_PATH")
        worklogTableField.text = configManager.envValue("WORKLOG_DB_TABLE")
        worklogApiUrlField.text = configManager.envValue("WORKLOG_API_URL")
        worklogApiKeyField.text = configManager.envValue("WORKLOG_API_KEY")
    }

    function saveEnvFields() {
        var secs = parseInt(solarIntervalField.text, 10)
        var intervalMs = (!isNaN(secs) && secs >= 2) ? (secs * 1000).toString() : ""
        var ok = configManager.saveIntegrationEnv({
            "IOT_WEBHOOK_BASE": iotWebhookField.text,
            "IOT_API_KEY": iotKeyField.text,
            "SOLAR_API_URL": solarUrlField.text,
            "SOLAR_API_KEY": solarKeyField.text,
            "SOLAR_POLL_INTERVAL_MS": intervalMs,
            "WORKLOG_DB_PATH": worklogDbField.text,
            "WORKLOG_DB_TABLE": worklogTableField.text,
            "WORKLOG_API_URL": worklogApiUrlField.text,
            "WORKLOG_API_KEY": worklogApiKeyField.text
        })
        envFeedbackText = ok
            ? "Saved & applied to " + configManager.envFilePath
            : "Failed writing " + configManager.envFilePath
        if (ok) {
            envFeedbackReset.restart()
        }
    }

    Component.onCompleted: syncEnvFields()
    onVisibleChanged: if (visible) syncEnvFields()

    Timer {
        id: envFeedbackReset
        interval: 3500
        onTriggered: root.envFeedbackText = ""
    }

    FolderDialog {
        id: screenshotsFolderDialog
        title: "Choose Default Screenshots Folder"
        currentFolder: "file://" + configManager.screenshotsDir
        onAccepted: configManager.setScreenshotsDirFromUrl(selectedFolder)
    }

    FileDialog {
        id: worklogDbDialog
        title: "Select Worklog SQLite Database"
        nameFilters: ["SQLite databases (*.db *.db3 *.sqlite *.sqlite3)", "All files (*)"]
        onAccepted: worklogDbField.text = configManager.urlToLocalPath(selectedFile)
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 18
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: "CatchyPills Preferences"
                    color: "#f8fafc"
                    font.pixelSize: 18
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: appController.daemonStatusText
                    color: appController.daemonOnline ? "#00e5a3" : "#f59e0b"
                    font.pixelSize: 11
                }
            }

            // -----------------------------------------------------------------
            // 1. Display & Position
            // -----------------------------------------------------------------
            GroupBox {
                id: displayGroup
                Layout.fillWidth: true
                title: "Display & Position"

                background: Rectangle {
                    y: displayGroup.topPadding - displayGroup.bottomPadding
                    width: displayGroup.width
                    height: displayGroup.height - displayGroup.topPadding + displayGroup.bottomPadding
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.preferredWidth: 160
                            color: "#e2e8f0"
                            text: "Target Monitor"
                        }
                        ComboBox {
                            id: monitorCombo
                            Layout.fillWidth: true
                            model: configManager.availableMonitors
                            currentIndex: Math.max(0, configManager.availableMonitors.indexOf(configManager.targetMonitor))
                            onActivated: configManager.targetMonitor = currentText
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                color: "#e2e8f0"
                                text: "Horizontal Offset: " + configManager.horizontalOffset + " px"
                            }
                            Item { Layout.fillWidth: true }
                            Button {
                                text: "Center (0)"
                                onClicked: configManager.horizontalOffset = 0
                            }
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: -1000
                            to: 1000
                            stepSize: 10
                            value: configManager.horizontalOffset
                            onMoved: configManager.horizontalOffset = Math.round(value)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            color: "#e2e8f0"
                            text: "Top Margin: " + configManager.topMargin + " px"
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: 64
                            stepSize: 1
                            value: configManager.topMargin
                            onMoved: configManager.topMargin = Math.round(value)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label {
                            color: "#e2e8f0"
                            text: "Collapse Hover Delay: " + configManager.collapseDelayMs + " ms"
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 100
                            to: 1000
                            stepSize: 20
                            value: configManager.collapseDelayMs
                            onMoved: configManager.collapseDelayMs = Math.round(value)
                        }
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "Auto-hide on Fullscreen Apps & Games"
                        checked: configManager.autoHideFullscreen
                        onToggled: configManager.autoHideFullscreen = checked
                    }
                }
            }

            // -----------------------------------------------------------------
            // 2. Clipboard
            // -----------------------------------------------------------------
            GroupBox {
                id: clipboardGroup
                Layout.fillWidth: true
                title: "Clipboard"

                background: Rectangle {
                    y: clipboardGroup.topPadding - clipboardGroup.bottomPadding
                    width: clipboardGroup.width
                    height: clipboardGroup.height - clipboardGroup.topPadding + clipboardGroup.bottomPadding
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Switch {
                        Layout.fillWidth: true
                        text: "Pause Clipboard Capture"
                        checked: configManager.clipboardPaused
                        onToggled: configManager.clipboardPaused = checked
                    }
                }
            }

            // -----------------------------------------------------------------
            // 3. OmniShot Capture & System
            // -----------------------------------------------------------------
            GroupBox {
                id: captureGroup
                Layout.fillWidth: true
                title: "OmniShot Capture & System"

                background: Rectangle {
                    y: captureGroup.topPadding - captureGroup.bottomPadding
                    width: captureGroup.width
                    height: captureGroup.height - captureGroup.topPadding + captureGroup.bottomPadding
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label {
                            color: "#e2e8f0"
                            text: "Default Screenshots Save Folder"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: configManager.screenshotsDir
                                onEditingFinished: configManager.screenshotsDir = text
                            }
                            Button {
                                text: "Browse..."
                                onClicked: screenshotsFolderDialog.open()
                            }
                        }
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "Auto-copy Capture to Wayland Clipboard"
                        checked: configManager.autoCopyCapture
                        onToggled: configManager.autoCopyCapture = checked
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "Start with System (KDE Autostart)"
                        checked: configManager.startWithSystem
                        onToggled: configManager.startWithSystem = checked
                    }
                }
            }

            // -----------------------------------------------------------------
            // 4. Weather
            // -----------------------------------------------------------------
            GroupBox {
                id: weatherGroup
                Layout.fillWidth: true
                title: "Weather"

                background: Rectangle {
                    y: weatherGroup.topPadding - weatherGroup.bottomPadding
                    width: weatherGroup.width
                    height: weatherGroup.height - weatherGroup.topPadding + weatherGroup.bottomPadding
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label {
                                color: "#e2e8f0"
                                text: "Latitude (-90 to 90)"
                            }
                            TextField {
                                id: latField
                                Layout.fillWidth: true
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator {
                                    bottom: -90.0
                                    top: 90.0
                                    decimals: 4
                                    notation: DoubleValidator.StandardNotation
                                }
                                text: configManager.weatherLatitude.toString()
                                onEditingFinished: {
                                    var parsed = parseFloat(text)
                                    if (!isNaN(parsed)) {
                                        configManager.weatherLatitude = parsed
                                    } else {
                                        text = configManager.weatherLatitude.toString()
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label {
                                color: "#e2e8f0"
                                text: "Longitude (-180 to 180)"
                            }
                            TextField {
                                id: lonField
                                Layout.fillWidth: true
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator {
                                    bottom: -180.0
                                    top: 180.0
                                    decimals: 4
                                    notation: DoubleValidator.StandardNotation
                                }
                                text: configManager.weatherLongitude.toString()
                                onEditingFinished: {
                                    var parsed = parseFloat(text)
                                    if (!isNaN(parsed)) {
                                        configManager.weatherLongitude = parsed
                                    } else {
                                        text = configManager.weatherLongitude.toString()
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.fillWidth: true
                            color: "#94a3b8"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            text: "Updates the Open-Meteo 7-day forecast immediately when coordinates change."
                        }
                        Button {
                            text: "Apply"
                            onClicked: {
                                var latVal = parseFloat(latField.text)
                                var lonVal = parseFloat(lonField.text)
                                if (!isNaN(latVal)) {
                                    configManager.weatherLatitude = latVal
                                }
                                if (!isNaN(lonVal)) {
                                    configManager.weatherLongitude = lonVal
                                }
                            }
                        }
                        Button {
                            text: "Default"
                            onClicked: {
                                configManager.weatherLatitude = -27.82
                                configManager.weatherLongitude = 152.96
                                latField.text = configManager.weatherLatitude.toString()
                                lonField.text = configManager.weatherLongitude.toString()
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // 5. Bespoke Integrations (Advanced)
            // -----------------------------------------------------------------
            GroupBox {
                id: bespokeGroup
                Layout.fillWidth: true
                title: "Bespoke Integrations (Advanced)"

                background: Rectangle {
                    y: bespokeGroup.topPadding - bespokeGroup.bottomPadding
                    width: bespokeGroup.width
                    height: bespokeGroup.height - bespokeGroup.topPadding + bespokeGroup.bottomPadding
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    Label {
                        Layout.fillWidth: true
                        color: "#94a3b8"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        text: "Secrets & endpoints save locally to " + configManager.envFilePath + " (0600, excluded from git). Toggle a module on to configure its endpoint."
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "ServiceNow ITSM Prompt Generator"
                        checked: configManager.enableITSM
                        onToggled: configManager.enableITSM = checked
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "IoT & Smart Device Controls"
                        checked: configManager.enableIoT
                        onToggled: configManager.enableIoT = checked
                    }

                    Rectangle {
                        visible: configManager.enableIoT
                        Layout.fillWidth: true
                        Layout.preferredHeight: iotCfgCol.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(0.118, 0.118, 0.180, 0.72)
                        border.width: 1
                        border.color: Qt.rgba(0.0, 0.90, 0.64, 0.25)

                        ColumnLayout {
                            id: iotCfgCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                text: "IoT Webhook Base URL (IOT_WEBHOOK_BASE)"
                            }

                            TextField {
                                id: iotWebhookField
                                Layout.fillWidth: true
                                placeholderText: "e.g. http://192.168.1.200:8123/api/webhook or ...?device={device}"
                            }

                            Label {
                                Layout.fillWidth: true
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                text: "Bearer Token / API Key (IOT_API_KEY, optional)"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                TextField {
                                    id: iotKeyField
                                    Layout.fillWidth: true
                                    echoMode: root.revealIotKey ? TextInput.Normal : TextInput.Password
                                    placeholderText: "Optional Authorization Bearer token"
                                }

                                Button {
                                    text: root.revealIotKey ? "Hide" : "Show"
                                    onClicked: root.revealIotKey = !root.revealIotKey
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                color: "#94a3b8"
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                                text: "Tile IDs: shed_ac, front_gate, office_lights, shed_lights, air_compressor, all_off (per-device IOT_WEBHOOK_<ID> overrides also supported in .env)."
                            }
                        }
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "Solar & Energy Telemetry"
                        checked: configManager.enableSolar
                        onToggled: configManager.enableSolar = checked
                    }

                    Rectangle {
                        visible: configManager.enableSolar
                        Layout.fillWidth: true
                        Layout.preferredHeight: solarCfgCol.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(0.118, 0.118, 0.180, 0.72)
                        border.width: 1
                        border.color: Qt.rgba(0.0, 0.90, 0.64, 0.25)

                        ColumnLayout {
                            id: solarCfgCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                text: "Solar Telemetry JSON Endpoint (SOLAR_API_URL)"
                            }

                            TextField {
                                id: solarUrlField
                                Layout.fillWidth: true
                                placeholderText: "e.g. http://192.168.1.200:8000/api/solar"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Label {
                                        color: "#e2e8f0"
                                        font.pixelSize: 11
                                        text: "API Key (SOLAR_API_KEY, optional)"
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        TextField {
                                            id: solarKeyField
                                            Layout.fillWidth: true
                                            echoMode: root.revealSolarKey ? TextInput.Normal : TextInput.Password
                                            placeholderText: "Optional Bearer token"
                                        }

                                        Button {
                                            text: root.revealSolarKey ? "Hide" : "Show"
                                            onClicked: root.revealSolarKey = !root.revealSolarKey
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: 110
                                    spacing: 4

                                    Label {
                                        color: "#e2e8f0"
                                        font.pixelSize: 11
                                        text: "Poll (sec)"
                                    }

                                    TextField {
                                        id: solarIntervalField
                                        Layout.fillWidth: true
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 2; top: 300 }
                                        placeholderText: "15"
                                    }
                                }
                            }
                        }
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "Worklog & Timesheet Sync"
                        checked: configManager.enableWorklog
                        onToggled: configManager.enableWorklog = checked
                    }

                    Rectangle {
                        visible: configManager.enableWorklog
                        Layout.fillWidth: true
                        Layout.preferredHeight: worklogCfgCol.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(0.118, 0.118, 0.180, 0.72)
                        border.width: 1
                        border.color: Qt.rgba(0.0, 0.90, 0.64, 0.25)

                        ColumnLayout {
                            id: worklogCfgCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Label {
                                Layout.fillWidth: true
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                text: "Local/Mounted SQLite Database (WORKLOG_DB_PATH)"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                TextField {
                                    id: worklogDbField
                                    Layout.fillWidth: true
                                    placeholderText: "Leave blank for ~/.local/share/CatchyPills/worklog.db3"
                                }

                                Button {
                                    text: "Browse..."
                                    onClicked: worklogDbDialog.open()
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                text: "SQLite Table Name (WORKLOG_DB_TABLE, optional)"
                            }

                            TextField {
                                id: worklogTableField
                                Layout.fillWidth: true
                                placeholderText: "Auto-detects shifts/worklog or creates worklog_shifts"
                            }

                            Label {
                                Layout.fillWidth: true
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                text: "HTTP Endpoint Fallback (WORKLOG_API_URL, used when DB path is blank)"
                            }

                            TextField {
                                id: worklogApiUrlField
                                Layout.fillWidth: true
                                placeholderText: "e.g. http://192.168.1.200:8501/api/worklog"
                            }

                            Label {
                                Layout.fillWidth: true
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                text: "HTTP Bearer Token (WORKLOG_API_KEY, optional)"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                TextField {
                                    id: worklogApiKeyField
                                    Layout.fillWidth: true
                                    echoMode: root.revealWorklogKey ? TextInput.Normal : TextInput.Password
                                    placeholderText: "Optional Bearer token"
                                }

                                Button {
                                    text: root.revealWorklogKey ? "Hide" : "Show"
                                    onClicked: root.revealWorklogKey = !root.revealWorklogKey
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: root.envFeedbackText.startsWith("Failed") ? "#f59e0b" : "#00e5a3"
                            font.pixelSize: 11
                            text: root.envFeedbackText
                        }

                        Button {
                            text: "Reload .env"
                            onClicked: {
                                configManager.reloadEnv()
                                root.syncEnvFields()
                                root.envFeedbackText = "Reloaded from .env"
                                envFeedbackReset.restart()
                            }
                        }

                        Button {
                            text: "Open .env"
                            onClicked: appController.openEnvFile()
                        }

                        Button {
                            text: "Save & Apply"
                            highlighted: true
                            onClicked: root.saveEnvFields()
                        }
                    }
                }
            }
        }
    }
}
