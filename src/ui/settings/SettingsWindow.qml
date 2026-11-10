import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Window {
    id: root
    width: 540
    height: 620
    minimumWidth: 480
    minimumHeight: 540
    title: "CatchyPills Settings"
    color: "#1e1e2e"

    FolderDialog {
        id: screenshotsFolderDialog
        title: "Choose Default Screenshots Folder"
        currentFolder: "file://" + configManager.screenshotsDir
        onAccepted: configManager.setScreenshotsDirFromUrl(selectedFolder)
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
            // 2. Clipboard & File Shelf
            // -----------------------------------------------------------------
            GroupBox {
                id: clipboardGroup
                Layout.fillWidth: true
                title: "Clipboard & File Shelf"

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

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            Layout.preferredWidth: 160
                            color: "#e2e8f0"
                            text: "File Shelf Auto-Clear"
                        }
                        ComboBox {
                            id: retentionCombo
                            Layout.fillWidth: true
                            readonly property var options: [
                                { label: "1 Hour", hours: 1 },
                                { label: "24 Hours", hours: 24 },
                                { label: "7 Days", hours: 168 },
                                { label: "Never", hours: 0 }
                            ]
                            model: options
                            textRole: "label"
                            valueRole: "hours"
                            currentIndex: {
                                for (var i = 0; i < options.length; ++i) {
                                    if (options[i].hours === configManager.shelfRetentionHours) {
                                        return i
                                    }
                                }
                                return 1
                            }
                            onActivated: configManager.shelfRetentionHours = currentValue
                        }
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
                        text: "Personal workflow modules driven by ~/.config/catchypills/.env (excluded from git). Disabled by default for clean shared installs."
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

                    Switch {
                        Layout.fillWidth: true
                        text: "Solar & Energy Telemetry"
                        checked: configManager.enableSolar
                        onToggled: configManager.enableSolar = checked
                    }

                    Switch {
                        Layout.fillWidth: true
                        text: "Worklog & Timesheet Sync"
                        checked: configManager.enableWorklog
                        onToggled: configManager.enableWorklog = checked
                    }
                }
            }
        }
    }
}
