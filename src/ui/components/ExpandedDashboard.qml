pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Glassmorphic Floating Tab Strip
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { label: "Clipboard", tip: "Recent clipboard history captured securely over Wayland" },
                    { label: "Shelf", tip: "Temporary drop inbox for files, thumbnails & URLs" },
                    { label: "Media", tip: "SpotiBar MPRIS2 playback controls & animated equalizer" },
                    { label: "Notes", tip: "Quick persistent SQLite To-Do notes & thoughts" },
                    { label: "Search", tip: "Search indexed local files or query DuckDuckGo on the web" },
                    { label: "Capture", tip: "OmniShot region screenshots, annotations & screen recording" }
                ]

                delegate: Item {
                    id: tabItem
                    required property int index
                    required property var modelData
                    readonly property bool selected: root.activeTab === index

                    implicitWidth: tabLabel.implicitWidth + 20
                    implicitHeight: 32

                    RectangularShadow {
                        anchors.fill: tabPill
                        radius: tabPill.radius
                        offset: Qt.vector2d(0, 2)
                        blur: tabItem.selected ? 12 : 6
                        spread: 0
                        color: tabItem.selected
                               ? Qt.rgba(0.0, 0.90, 0.64, 0.22)
                               : Qt.rgba(0, 0, 0, 0.35)
                    }

                    Rectangle {
                        id: tabPill
                        anchors.fill: parent
                        radius: 12
                        color: tabItem.selected
                               ? Qt.rgba(0.0, 0.90, 0.64, 0.16)
                               : (tabHover.hovered
                                  ? Qt.rgba(1, 1, 1, 0.10)
                                  : Qt.rgba(0.16, 0.16, 0.24, 0.72))
                        border.width: 1
                        border.color: tabItem.selected
                                      ? "#00e5a3"
                                      : (tabHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.40) : Qt.rgba(1, 1, 1, 0.10))

                        HoverHandler { id: tabHover }

                        ToolTip.visible: tabHover.hovered
                        ToolTip.delay: 450
                        ToolTip.text: tabItem.modelData.tip

                        Label {
                            id: tabLabel
                            anchors.centerIn: parent
                            color: tabItem.selected ? "#00e5a3" : "#cbd5e1"
                            font.pixelSize: 12
                            font.weight: tabItem.selected ? Font.DemiBold : Font.Normal
                            text: tabItem.modelData.label
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.activeTab = tabItem.index
                                if (tabItem.index === 0) {
                                    daemonClient.refreshClips()
                                } else if (tabItem.index === 2) {
                                    mprisController.refresh()
                                } else if (tabItem.index === 3) {
                                    notesView.focusInput()
                                } else if (tabItem.index === 4) {
                                    searchPaletteView.focusInput()
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Item {
                implicitWidth: 32
                implicitHeight: 32

                RectangularShadow {
                    anchors.fill: gearPill
                    radius: gearPill.radius
                    offset: Qt.vector2d(0, 2)
                    blur: 6
                    color: Qt.rgba(0, 0, 0, 0.35)
                }

                Rectangle {
                    id: gearPill
                    anchors.fill: parent
                    radius: 12
                    color: gearHover.hovered
                           ? Qt.rgba(1, 1, 1, 0.12)
                           : Qt.rgba(0.16, 0.16, 0.24, 0.72)
                    border.width: 1
                    border.color: gearHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.45) : Qt.rgba(1, 1, 1, 0.10)

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

            // 5. OmniShot Capture & Region Recording Workflow
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

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    RectangularShadow {
                        anchors.fill: captureCard
                        radius: captureCard.radius
                        offset: Qt.vector2d(0, 6)
                        blur: 18
                        color: Qt.rgba(0, 0, 0, 0.45)
                    }

                    Rectangle {
                        id: captureCard
                        anchors.fill: parent
                        radius: 16
                        color: Qt.rgba(0.16, 0.16, 0.24, 0.62)
                        border.width: 1
                        border.color: captureCoordinator.recording
                                      ? Qt.rgba(0.94, 0.27, 0.27, 0.55)
                                      : Qt.rgba(0.0, 0.90, 0.64, 0.30)

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 56, 420)
                            spacing: 14

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 52
                                implicitHeight: 52
                                radius: 16
                                color: captureCoordinator.recording
                                       ? Qt.rgba(0.94, 0.27, 0.27, 0.18)
                                       : Qt.rgba(0.0, 0.90, 0.64, 0.14)
                                border.width: 1
                                border.color: captureCoordinator.recording ? "#ef4444" : "#00e5a3"

                                Canvas {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.strokeStyle = "#00e5a3"
                                        ctx.lineWidth = 1.8
                                        ctx.lineCap = "round"

                                        // Precision crosshair reticle
                                        ctx.beginPath()
                                        ctx.arc(12, 12, 6, 0, Math.PI * 2)
                                        ctx.moveTo(12, 2.5)
                                        ctx.lineTo(12, 6.5)
                                        ctx.moveTo(12, 17.5)
                                        ctx.lineTo(12, 21.5)
                                        ctx.moveTo(2.5, 12)
                                        ctx.lineTo(6.5, 12)
                                        ctx.moveTo(17.5, 12)
                                        ctx.lineTo(21.5, 12)
                                        ctx.stroke()
                                    }
                                }
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                color: "#f8fafc"
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                text: captureCoordinator.recording
                                      ? "Recording In Progress"
                                      : "Interactive Region Capture"
                            }

                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                color: "#94a3b8"
                                font.pixelSize: 12
                                text: captureCoordinator.recording
                                      ? "KPipeWire stream is actively capturing your selected desktop region."
                                      : "Drag across any area of your display to hand off a Screenshot to OmniShot or Record MP4."
                            }

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: primaryCaptureBtn.implicitWidth
                                implicitHeight: 44

                                RectangularShadow {
                                    anchors.fill: primaryCaptureBtn
                                    radius: primaryCaptureBtn.radius
                                    offset: Qt.vector2d(0, 4)
                                    blur: 14
                                    color: captureCoordinator.recording
                                           ? Qt.rgba(0.94, 0.27, 0.27, 0.35)
                                           : Qt.rgba(0.0, 0.90, 0.64, 0.32)
                                }

                                Rectangle {
                                    id: primaryCaptureBtn
                                    implicitWidth: Math.max(btnLabel.implicitWidth + 44, 236)
                                    implicitHeight: 44
                                    radius: 12
                                    color: captureCoordinator.saving
                                           ? Qt.rgba(0.28, 0.33, 0.41, 0.85)
                                           : (captureCoordinator.recording
                                              ? (ctaMouse.pressed ? "#dc2626" : (ctaHover.hovered ? "#f87171" : "#ef4444"))
                                              : (ctaMouse.pressed ? Qt.darker("#00e5a3", 1.12)
                                                                  : (ctaHover.hovered ? "#22f3b5" : "#00e5a3")))
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, captureCoordinator.saving ? 0.16 : 0.35)
                                    opacity: captureCoordinator.saving ? 0.72 : 1.0

                                    HoverHandler {
                                        id: ctaHover
                                        enabled: !captureCoordinator.saving
                                    }

                                    Label {
                                        id: btnLabel
                                        anchors.centerIn: parent
                                        color: captureCoordinator.saving
                                               ? "#e2e8f0"
                                               : (captureCoordinator.recording ? "#ffffff" : "#091216")
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        text: captureCoordinator.saving
                                              ? "Saving..."
                                              : (captureCoordinator.recording
                                                 ? "Stop Recording"
                                                 : "Select Region / Capture")
                                    }

                                    MouseArea {
                                        id: ctaMouse
                                        anchors.fill: parent
                                        enabled: !captureCoordinator.saving
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (captureCoordinator.recording) {
                                                captureCoordinator.stopRecording()
                                            } else {
                                                captureCoordinator.prepareRegionCapture(false)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
