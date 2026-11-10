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
    readonly property bool weatherPopupOpen: forecastPopup.opened
    readonly property bool shelfContainsDrag: fileShelfView.containsDrag

    signal collapseRequested()
    signal collapseImmediatelyRequested()
    signal shelfDropCompleted()
    signal shelfDragHoverChanged()

    function acceptShelfDrop(drop) {
        return fileShelfView.acceptDrop(drop)
    }

    function closePopups() {
        forecastPopup.close()
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

            // Cached 30-min Open-Meteo weather badge + 7-day forecast popup
            Item {
                id: weatherPillItem
                implicitWidth: weatherRow.implicitWidth + 18
                implicitHeight: 32

                RectangularShadow {
                    anchors.fill: weatherPill
                    radius: weatherPill.radius
                    offset: Qt.vector2d(0, 2)
                    blur: 6
                    color: Qt.rgba(0, 0, 0, 0.35)
                }

                Rectangle {
                    id: weatherPill
                    anchors.fill: parent
                    radius: 12
                    color: (weatherHover.hovered || forecastPopup.opened)
                           ? Qt.rgba(1, 1, 1, 0.12)
                           : Qt.rgba(0.16, 0.16, 0.24, 0.72)
                    border.width: 1
                    border.color: (weatherHover.hovered || forecastPopup.opened)
                                  ? Qt.rgba(0.0, 0.90, 0.64, 0.45)
                                  : Qt.rgba(1, 1, 1, 0.10)

                    HoverHandler { id: weatherHover }

                    ToolTip.visible: weatherHover.hovered && !forecastPopup.opened
                    ToolTip.delay: 300
                    ToolTip.text: weatherController.conditionSummary
                                  + (weatherController.lastUpdatedText !== ""
                                     ? "\nUpdated " + weatherController.lastUpdatedText + " • Click for 7-day forecast"
                                     : "\nClick for 7-day forecast")

                    Row {
                        id: weatherRow
                        anchors.centerIn: parent
                        spacing: 5

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 13
                            text: weatherController.conditionIcon
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#e2e8f0"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            text: weatherController.temperatureText
                        }
                    }

                    MouseArea {
                        id: weatherMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        property bool popupWasOpenOnPress: false
                        onPressed: popupWasOpenOnPress = forecastPopup.opened
                        onClicked: {
                            if (!popupWasOpenOnPress) {
                                weatherController.refresh(false)
                                forecastPopup.open()
                            }
                        }
                    }
                }

                Popup {
                    id: forecastPopup
                    x: weatherPillItem.width + 38 - width
                    y: weatherPillItem.height + 8
                    width: 264
                    padding: 12
                    modal: false
                    focus: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                    background: Item {
                        RectangularShadow {
                            anchors.fill: forecastBg
                            radius: forecastBg.radius
                            offset: Qt.vector2d(0, 8)
                            blur: 20
                            spread: 1
                            color: Qt.rgba(0, 0, 0, 0.62)
                        }

                        Rectangle {
                            id: forecastBg
                            anchors.fill: parent
                            radius: 14
                            color: Qt.rgba(0.118, 0.118, 0.180, 0.96)
                            border.width: 1
                            border.color: Qt.rgba(0.0, 0.90, 0.64, 0.35)
                        }
                    }

                    contentItem: ColumnLayout {
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Label {
                                Layout.fillWidth: true
                                color: "#f8fafc"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                text: "7-Day Forecast"
                            }

                            Rectangle {
                                implicitWidth: 22
                                implicitHeight: 22
                                radius: 7
                                color: refreshHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

                                HoverHandler { id: refreshHover }

                                ToolTip.visible: refreshHover.hovered
                                ToolTip.delay: 300
                                ToolTip.text: "Refresh weather now"

                                Label {
                                    anchors.centerIn: parent
                                    color: refreshHover.hovered ? "#00e5a3" : "#94a3b8"
                                    font.pixelSize: 12
                                    text: "↻"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: weatherController.refresh(true)
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: "#94a3b8"
                            font.pixelSize: 10
                            text: weatherController.conditionSummary
                                  + (weatherController.lastUpdatedText !== ""
                                     ? " • Updated " + weatherController.lastUpdatedText
                                     : "")
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Qt.rgba(1, 1, 1, 0.08)
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: weatherController.forecastData.length === 0
                            horizontalAlignment: Text.AlignHCenter
                            color: "#64748b"
                            font.pixelSize: 11
                            text: "Loading 7-day forecast..."
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: weatherController.forecastData.length > 0
                            spacing: 6

                            Repeater {
                                model: weatherController.forecastData

                                delegate: RowLayout {
                                    id: forecastDayRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Label {
                                        Layout.preferredWidth: 40
                                        color: "#e2e8f0"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        text: forecastDayRow.modelData.dayOfWeek
                                    }

                                    Label {
                                        Layout.preferredWidth: 24
                                        horizontalAlignment: Text.AlignHCenter
                                        font.pixelSize: 13
                                        text: forecastDayRow.modelData.icon
                                    }

                                    Item { Layout.fillWidth: true }

                                    Label {
                                        color: "#94a3b8"
                                        font.pixelSize: 11
                                        font.family: "monospace"
                                        text: forecastDayRow.modelData.minTemp + "°"
                                    }

                                    Label {
                                        color: "#64748b"
                                        font.pixelSize: 10
                                        text: "-"
                                    }

                                    Label {
                                        color: "#00e5a3"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        font.family: "monospace"
                                        text: forecastDayRow.modelData.maxTemp + "°"
                                    }
                                }
                            }
                        }
                    }
                }
            }

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
                            width: Math.min(parent.width - 40, 520)
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

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 10

                                Item {
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
                                        implicitWidth: Math.max(btnLabel.implicitWidth + 32, 188)
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

                                Item {
                                    implicitWidth: colorPickerBtn.implicitWidth
                                    implicitHeight: 44

                                    RectangularShadow {
                                        anchors.fill: colorPickerBtn
                                        radius: colorPickerBtn.radius
                                        offset: Qt.vector2d(0, 4)
                                        blur: 12
                                        color: Qt.rgba(0, 0, 0, 0.38)
                                    }

                                    Rectangle {
                                        id: colorPickerBtn
                                        implicitWidth: Math.max(colorBtnRow.implicitWidth + 28, 188)
                                        implicitHeight: 44
                                        radius: 12
                                        color: colorMouse.pressed
                                               ? Qt.rgba(1, 1, 1, 0.16)
                                               : (colorHover.hovered
                                                  ? Qt.rgba(1, 1, 1, 0.11)
                                                  : Qt.rgba(0.18, 0.18, 0.27, 0.88))
                                        border.width: 1
                                        border.color: colorHover.hovered
                                                      ? "#00e5a3"
                                                      : Qt.rgba(1, 1, 1, 0.16)

                                        HoverHandler { id: colorHover }

                                        Row {
                                            id: colorBtnRow
                                            anchors.centerIn: parent
                                            spacing: 7

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: "#00e5a3"
                                                border.width: 1
                                                border.color: Qt.rgba(1, 1, 1, 0.45)
                                            }

                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: "#f8fafc"
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                text: "Pick Screen Color (HEX)"
                                            }
                                        }

                                        MouseArea {
                                            id: colorMouse
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.collapseImmediatelyRequested()
                                                captureCoordinator.pickScreenColor()
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
