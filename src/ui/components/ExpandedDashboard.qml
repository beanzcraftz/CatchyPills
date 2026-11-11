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

    property int activeTab: 0 // 0 = Clipboard, 1 = IoT, 2 = Media, 3 = Notes, 4 = Search, 5 = Capture, 6 = ITSM
    readonly property bool searchInputFocused: searchPaletteView.inputFocused || notesView.inputFocused || itsmView.inputFocused
    readonly property bool weatherPopupOpen: forecastPopup.opened

    Connections {
        target: configManager
        function onEnableIoTChanged() {
            if (!configManager.enableIoT && root.activeTab === 1) {
                root.activeTab = 0
            }
        }
        function onEnableITSMChanged() {
            if (!configManager.enableITSM && root.activeTab === 6) {
                root.activeTab = 0
            }
        }
    }

    signal collapseRequested()
    signal collapseImmediatelyRequested()

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
            spacing: 4

            Repeater {
                model: [
                    { label: "Clipboard", tip: "Recent clipboard history captured securely over Wayland" },
                    { label: "IoT", tip: "Trigger Alexa & workshop smart device controls" },
                    { label: "Media", tip: "SpotiBar MPRIS2 playback controls & animated equalizer" },
                    { label: "Notes", tip: "Quick persistent SQLite To-Do notes & thoughts" },
                    { label: "Search", tip: "Search indexed local files or query DuckDuckGo on the web" },
                    { label: "Capture", tip: "OmniShot region screenshots, annotations & screen recording" },
                    { label: "ITSM", tip: "ServiceNow KB HTML template prompt generator" }
                ]

                delegate: Item {
                    id: tabItem
                    required property int index
                    required property var modelData
                    readonly property bool selected: root.activeTab === index

                    visible: (index === 1 && configManager.enableIoT)
                             || (index === 6 && configManager.enableITSM)
                             || (index !== 1 && index !== 6)
                    implicitWidth: tabLabel.implicitWidth + 14
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
                                } else if (tabItem.index === 6) {
                                    itsmView.focusInput()
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Dual-inverter Solar Telemetry Readout (only when enableSolar is active)
            Item {
                id: solarPillItem
                visible: configManager.enableSolar
                implicitWidth: solarRow.implicitWidth + 16
                implicitHeight: 32

                readonly property color telemetryColor:
                    solarController.exceedingConsumption ? "#00e5a3" : "#f59e0b"

                RectangularShadow {
                    anchors.fill: solarPill
                    radius: solarPill.radius
                    offset: Qt.vector2d(0, 2)
                    blur: 6
                    color: Qt.rgba(0, 0, 0, 0.35)
                }

                Rectangle {
                    id: solarPill
                    anchors.fill: parent
                    radius: 12
                    color: solarHover.hovered
                           ? Qt.rgba(1, 1, 1, 0.12)
                           : Qt.rgba(0.16, 0.16, 0.24, 0.72)
                    border.width: 1
                    border.color: solarController.exceedingConsumption
                                  ? Qt.rgba(0.0, 0.90, 0.64, solarHover.hovered ? 0.65 : 0.35)
                                  : Qt.rgba(0.96, 0.62, 0.04, solarHover.hovered ? 0.65 : 0.35)

                    HoverHandler { id: solarHover }

                    ToolTip.visible: solarHover.hovered
                    ToolTip.delay: 300
                    ToolTip.text: solarController.available
                                  ? ((solarController.exceedingConsumption ? "Exporting surplus to grid" : "Drawing power from grid")
                                     + "\nGen: " + solarController.generationText
                                     + " • Use: " + solarController.consumptionText
                                     + (solarController.lastUpdatedText !== "" ? ("\nUpdated " + solarController.lastUpdatedText) : ""))
                                  : (solarController.configured
                                     ? "Waiting for dual-inverter telemetry...\nClick to retry"
                                     : "Set SOLAR_API_URL in ~/.config/catchypills/.env")

                    Row {
                        id: solarRow
                        anchors.centerIn: parent
                        spacing: 6

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            color: solarPillItem.telemetryColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            text: "☀️ " + solarController.generationText
                        }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            color: solarPillItem.telemetryColor
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            text: "🏠 " + solarController.consumptionText
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: solarController.refresh()
                    }
                }
            }

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

        // Main Content Area (Optional Worklog Sidebar + Tab Stack)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // Bespoke Worklog Punch-Clock Sidebar
            Rectangle {
                id: worklogSidebar
                visible: configManager.enableWorklog
                Layout.preferredWidth: 152
                Layout.fillHeight: true
                radius: 14
                color: Qt.rgba(0.14, 0.14, 0.22, 0.72)
                border.width: 1
                border.color: worklogController.punchedIn
                              ? Qt.rgba(0.0, 0.90, 0.64, 0.45)
                              : Qt.rgba(1, 1, 1, 0.10)

                property real nowSecs: Math.floor(Date.now() / 1000)

                function formatElapsed(startEpoch, currentEpoch) {
                    if (!worklogController.punchedIn || startEpoch <= 0) {
                        return "00:00:00"
                    }
                    var total = Math.max(0, Math.floor(currentEpoch) - startEpoch)
                    var hrs = Math.floor(total / 3600)
                    var mins = Math.floor((total % 3600) / 60)
                    var secs = total % 60
                    var pad = function(n) { return n < 10 ? "0" + n : "" + n }
                    return pad(hrs) + ":" + pad(mins) + ":" + pad(secs)
                }

                Connections {
                    target: worklogController
                    function onStateChanged() {
                        worklogSidebar.nowSecs = Math.floor(Date.now() / 1000)
                    }
                }

                Timer {
                    id: worklogTickTimer
                    interval: 1000
                    repeat: true
                    triggeredOnStart: true
                    running: configManager.enableWorklog && worklogController.punchedIn
                    onTriggered: worklogSidebar.nowSecs = Math.floor(Date.now() / 1000)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            radius: 4
                            color: worklogController.punchedIn ? "#00e5a3" : "#64748b"
                        }

                        Label {
                            color: "#94a3b8"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                            text: "WORKLOG"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "monospace"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: worklogController.punchedIn ? "#00e5a3" : "#94a3b8"
                        text: worklogSidebar.formatElapsed(worklogController.activeStartEpoch, worklogSidebar.nowSecs)
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: "#cbd5e1"
                        font.pixelSize: 10
                        text: worklogController.punchedIn
                              ? ("In at " + worklogController.startedAtText)
                              : (worklogController.lastDurationText !== ""
                                 ? ("Last: " + worklogController.lastDurationText)
                                 : worklogController.statusText)
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        id: punchBtn
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 10
                        enabled: !worklogController.busy
                        color: worklogController.punchedIn
                               ? (punchMouse.pressed
                                  ? Qt.rgba(0.96, 0.62, 0.04, 0.30)
                                  : (punchHover.hovered ? Qt.rgba(0.96, 0.62, 0.04, 0.22) : Qt.rgba(0.96, 0.62, 0.04, 0.14)))
                               : (punchMouse.pressed ? Qt.darker("#00e5a3", 1.12) : (punchHover.hovered ? "#22f3b5" : "#00e5a3"))
                        border.width: 1
                        border.color: worklogController.punchedIn ? "#f59e0b" : Qt.rgba(1, 1, 1, 0.35)

                        HoverHandler { id: punchHover }

                        Label {
                            anchors.centerIn: parent
                            color: worklogController.punchedIn ? "#f59e0b" : "#091216"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            text: worklogController.punchedIn ? "Punch Out" : "Punch In"
                        }

                        MouseArea {
                            id: punchMouse
                            anchors.fill: parent
                            enabled: !worklogController.busy
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: worklogController.togglePunchClock()
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

                // 1. Bespoke IoT Control Grid
                IoTView {
                    id: iotView
                    visible: configManager.enableIoT
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

            // 6. Bespoke ServiceNow ITSM Template Prompt Generator
            ITSMView {
                id: itsmView
                visible: configManager.enableITSM
                onCollapseRequested: root.collapseRequested()
            }
        }
        }
    }
}
