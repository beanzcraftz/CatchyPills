pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Tabbed expanded Dynamic Island workspace rendered over KWin's
 * ext_background_effect_v1 translucent blur mask (driven by LayerSurfaceController).
 */
Item {
    id: root

    property int activeTab: 0 // 0 = Clipboard, 1 = Shelf, 2 = Media, 3 = Notes, 4 = Search, 5 = Capture
    readonly property bool searchInputFocused: searchPaletteView.inputFocused || notesView.inputFocused
    readonly property bool shelfContainsDrag: fileShelfView.containsDrag

    signal collapseRequested()
    signal collapseImmediatelyRequested()
    signal shelfDropCompleted()
    signal shelfDragHoverChanged()

    function acceptShelfDrop(drop) {
        return fileShelfView.acceptDrop(drop)
    }

    function focusSearch() {
        activeTab = 4
        searchPaletteView.focusInput()
    }

    component CaptureTile : ColumnLayout {
        id: tile
        property string buttonText: ""
        property string subtitle: ""
        property bool primary: false
        property bool buttonEnabled: true
        signal activated()

        Layout.fillWidth: true
        Layout.minimumWidth: Math.max(btn.implicitWidth, 240)
        Layout.preferredWidth: 300
        spacing: 5

        Button {
            id: btn
            Layout.fillWidth: true
            Layout.minimumWidth: implicitWidth
            Layout.preferredHeight: 42
            enabled: tile.buttonEnabled
            hoverEnabled: true
            leftPadding: 14
            rightPadding: 14
            text: tile.buttonText

            ToolTip.visible: hovered && tile.subtitle.length > 0
            ToolTip.delay: 450
            ToolTip.text: tile.subtitle

            contentItem: Text {
                text: btn.text
                font.pixelSize: 13
                font.weight: tile.primary ? Font.DemiBold : Font.Medium
                color: !btn.enabled
                       ? "#64748b"
                       : (tile.primary ? "#f8fafc" : "#e2e8f0")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideNone
            }

            background: Rectangle {
                radius: 12
                color: !btn.enabled
                       ? Qt.rgba(1, 1, 1, 0.03)
                       : (tile.primary
                          ? (btn.down ? Qt.rgba(0.14, 0.56, 0.85, 0.90)
                                      : (btn.hovered ? Qt.rgba(0.22, 0.74, 0.97, 0.88)
                                                     : Qt.rgba(0.18, 0.65, 0.92, 0.76)))
                          : (btn.down ? Qt.rgba(1, 1, 1, 0.14)
                                      : (btn.hovered ? Qt.rgba(1, 1, 1, 0.12)
                                                     : Qt.rgba(1, 1, 1, 0.07))))
                border.width: 1
                border.color: tile.primary
                              ? Qt.rgba(0.49, 0.85, 1.0, 0.75)
                              : Qt.rgba(1, 1, 1, 0.14)
            }

            onClicked: tile.activated()
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: "#94a3b8"
            font.pixelSize: 11
            text: tile.subtitle
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Glassmorphic Tab Strip + Capture Status
        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                model: [
                    { label: "Clipboard", tip: "Recent clipboard history captured securely over Wayland" },
                    { label: "Shelf", tip: "Temporary drop inbox for files, thumbnails & URLs" },
                    { label: "Media", tip: "SpotiBar MPRIS2 playback controls & animated equalizer" },
                    { label: "Notes", tip: "Quick persistent SQLite To-Do notes & thoughts" },
                    { label: "Search", tip: "Search indexed local files or query DuckDuckGo on the web" },
                    { label: "Capture", tip: "OmniShot region screenshots, annotations & screen recording" }
                ]

                delegate: Rectangle {
                    id: tabButton
                    required property int index
                    required property var modelData
                    readonly property bool selected: root.activeTab === index

                    implicitWidth: tabLabel.implicitWidth + 16
                    height: 30
                    radius: 15
                    color: selected
                           ? Qt.rgba(0.22, 0.74, 0.97, 0.22)
                           : tabHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: selected
                                  ? Qt.rgba(0.22, 0.74, 0.97, 0.65)
                                  : Qt.rgba(1, 1, 1, 0.10)

                    HoverHandler { id: tabHover }

                    ToolTip.visible: tabHover.hovered
                    ToolTip.delay: 450
                    ToolTip.text: tabButton.modelData.tip

                    Label {
                        id: tabLabel
                        anchors.centerIn: parent
                        color: tabButton.selected ? "#f8fafc" : "#cbd5e1"
                        font.pixelSize: 12
                        font.weight: tabButton.selected ? Font.DemiBold : Font.Normal
                        text: tabButton.modelData.label
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.activeTab = tabButton.index
                            if (tabButton.index === 0) {
                                daemonClient.refreshClips()
                            } else if (tabButton.index === 2) {
                                mprisController.refresh()
                            } else if (tabButton.index === 3) {
                                notesView.focusInput()
                            } else if (tabButton.index === 4) {
                                searchPaletteView.focusInput()
                            }
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.minimumWidth: 40
                horizontalAlignment: Text.AlignRight
                color: "#94a3b8"
                font.pixelSize: 11
                elide: Text.ElideRight
                text: captureCoordinator.lastStatus
            }

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: 15
                color: gearHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                HoverHandler { id: gearHover }

                ToolTip.visible: gearHover.hovered
                ToolTip.delay: 450
                ToolTip.text: "Open CatchyPills settings"

                Label {
                    anchors.centerIn: parent
                    color: "#e2e8f0"
                    font.pixelSize: 14
                    text: "⚙"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appController.openSettings()
                }
            }
        }

        // Main Tab Body
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.activeTab

            // 0. ClipboardView
            ClipboardView {
                id: clipboardView
            }

            // 1. FileShelfView
            FileShelfView {
                id: fileShelfView
                onDropCompleted: root.shelfDropCompleted()
                onDragHoverChanged: root.shelfDragHoverChanged()
            }

            // 2. SpotiBar MediaView
            MediaView {
                id: mediaView
            }

            // 3. Persistent NotesView
            NotesView {
                id: notesView
                onCollapseRequested: root.collapseRequested()
            }

            // 4. Unified SearchPaletteView (Local Files | Web Search)
            SearchPaletteView {
                id: searchPaletteView
                onCollapseRequested: root.collapseRequested()
                onCollapseImmediatelyRequested: root.collapseImmediatelyRequested()
            }

            // 5. OmniShot Capture & KPipeWire Recording Controls
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: "#94a3b8"
                    font.pixelSize: 11
                    text: "OmniShot Capture • Region snip, annotation canvas, and screen recording"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 14
                    rowSpacing: 16

                    CaptureTile {
                        buttonText: "Region Snip (Annotate)"
                        subtitle: "Draw arrows and redact text before saving"
                        primary: true
                        onActivated: captureCoordinator.prepareRegionCapture(false)
                    }

                    CaptureTile {
                        buttonText: "Full Workspace (3840×1080)"
                        subtitle: "Snap the entire 32:9 desktop to clipboard & disk"
                        onActivated: captureCoordinator.captureWorkspace(false)
                    }

                    CaptureTile {
                        buttonText: captureCoordinator.recording ? "Stop Recording" : "Record GIF (15 fps)"
                        subtitle: "Capture a compact animated clip via KPipeWire"
                        onActivated: {
                            if (captureCoordinator.recording) {
                                captureCoordinator.stopRecording()
                            } else {
                                captureCoordinator.startRecording(0)
                            }
                        }
                    }

                    CaptureTile {
                        buttonText: "Record MP4 (60 fps)"
                        subtitle: "Record smooth high-framerate desktop video"
                        buttonEnabled: !captureCoordinator.recording
                        onActivated: captureCoordinator.startRecording(1)
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
