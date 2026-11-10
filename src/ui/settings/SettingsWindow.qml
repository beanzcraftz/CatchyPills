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
    color: "#0b0f17"

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
                    color: appController.daemonOnline ? "#34d399" : "#f59e0b"
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
        }
    }
}
