import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

/**
 * Fullscreen Wayland zwlr_layer_shell_v1 region-selection overlay (attached in
 * Application.cpp with LayerOverlay, all 4 edge anchors, exclusiveZone = -1, and
 * KeyboardInteractivityExclusive). Morphs into a lightweight click-through recording
 * border + floating Stop/Timer bar when MP4 recording starts.
 */
Window {
    id: root
    width: Screen.width
    height: Screen.height
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint

    property point dragStart: Qt.point(0, 0)
    property point cursorPos: Qt.point(0, 0)
    property bool isSelecting: false
    property bool hasSelection: false
    property bool isRecording: false
    property int elapsedSeconds: 0
    property rect selectionRect: Qt.rect(0, 0, 0, 0)

    readonly property bool hasOverlayLayer: typeof overlayLayerController !== "undefined"
                                            && overlayLayerController !== null

    function formatDuration(totalSecs) {
        var mins = Math.floor(totalSecs / 60)
        var secs = totalSecs % 60
        return (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    function syncRecordingMask() {
        if (!hasOverlayLayer || !isRecording) {
            return
        }
        overlayLayerController.setOverlayRecordingPassThrough(
            Qt.rect(Math.round(actionBar.x),
                    Math.round(actionBar.y),
                    Math.round(actionBar.width),
                    Math.round(actionBar.height)),
            actionBar.radius
        )
    }

    onVisibleChanged: {
        if (visible && !isRecording) {
            resetState()
            if (hasOverlayLayer) {
                overlayLayerController.restoreFullscreenOverlay()
            }
            overlayScope.forceActiveFocus()
        }
    }

    function resetState() {
        isSelecting = false
        hasSelection = false
        isRecording = false
        elapsedSeconds = 0
        selectionRect = Qt.rect(0, 0, 0, 0)
        annotationCanvas.activeTool = "none"
        annotationCanvas.clear()
    }

    function cancelOverlay() {
        if (isRecording) {
            captureCoordinator.stopRecording()
        }
        resetState()
        if (hasOverlayLayer) {
            overlayLayerController.restoreFullscreenOverlay()
        }
        root.visible = false
    }

    function commitOmniShot() {
        if (!hasSelection || selectionRect.width < 4 || selectionRect.height < 4) {
            return
        }
        // Snapshot geometry & annotations before hiding so KWin unmaps the overlay
        // surface cleanly before ScreenShot2::CaptureArea grabs region pixels for OmniShot.
        pendingCrop.x = Math.round(selectionRect.x)
        pendingCrop.y = Math.round(selectionRect.y)
        pendingCrop.w = Math.round(selectionRect.width)
        pendingCrop.h = Math.round(selectionRect.height)
        pendingCrop.annotations = annotationCanvas.exportAnnotations()

        root.visible = false
        handoffTimer.restart()
    }

    function beginRegionRecording() {
        if (!hasSelection || selectionRect.width < 8 || selectionRect.height < 8) {
            return
        }
        var rx = Math.round(selectionRect.x)
        var ry = Math.round(selectionRect.y)
        var rw = Math.round(selectionRect.width)
        var rh = Math.round(selectionRect.height)

        root.isSelecting = false
        root.elapsedSeconds = 0
        root.isRecording = true
        annotationCanvas.activeTool = "none"

        Qt.callLater(syncRecordingMask)
        captureCoordinator.startRegionRecording(rx, ry, rw, rh)
    }

    function stopRegionRecording() {
        captureCoordinator.stopRecording()
        resetState()
        if (hasOverlayLayer) {
            overlayLayerController.restoreFullscreenOverlay()
        }
        root.visible = false
    }

    Connections {
        target: captureCoordinator
        function onCaptureFailed() {
            if (root.visible || root.isRecording) {
                root.resetState()
                if (root.hasOverlayLayer) {
                    overlayLayerController.restoreFullscreenOverlay()
                }
                root.visible = false
            }
        }
        function onCaptureWorkflowFinished() {
            if (root.isRecording) {
                root.resetState()
                if (root.hasOverlayLayer) {
                    overlayLayerController.restoreFullscreenOverlay()
                }
                root.visible = false
            }
        }
    }

    Timer {
        id: recordingTimer
        interval: 1000
        repeat: true
        running: root.isRecording
        onTriggered: root.elapsedSeconds += 1
    }

    QtObject {
        id: pendingCrop
        property int x: 0
        property int y: 0
        property int w: 0
        property int h: 0
        property var annotations: []
    }

    Timer {
        id: handoffTimer
        interval: 60
        onTriggered: {
            captureCoordinator.captureToOmniShot(
                pendingCrop.x,
                pendingCrop.y,
                pendingCrop.w,
                pendingCrop.h,
                pendingCrop.annotations,
                false
            )
            root.resetState()
        }
    }

    Item {
        id: overlayScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: {
            if (!root.isRecording) {
                root.cancelOverlay()
            }
        }
        Keys.onReturnPressed: {
            if (!root.isRecording) {
                root.commitOmniShot()
            }
        }
        Keys.onEnterPressed: {
            if (!root.isRecording) {
                root.commitOmniShot()
            }
        }
        Keys.onPressed: function(event) {
            if (!root.isRecording && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
                annotationCanvas.undo()
                event.accepted = true
            }
        }

        // Frozen desktop backdrop supplied by CaptureImageProvider (ScreenShot2)
        // hidden immediately when live recording begins so desktop updates stay visible.
        Image {
            id: backdropImage
            anchors.fill: parent
            visible: !root.isRecording
            cache: false
            fillMode: Image.PreserveAspectCrop
            source: captureCoordinator.backdropRevision > 0
                    ? "image://capture/backdrop?" + captureCoordinator.backdropRevision
                    : ""
        }

        // 4-part dimming mask around selectionRect (hidden during live recording).
        Rectangle {
            visible: !root.isRecording && !root.hasSelection && !root.isSelecting
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Item {
            visible: !root.isRecording && (root.hasSelection || root.isSelecting)
            anchors.fill: parent

            Rectangle { // Top
                x: 0; y: 0
                width: parent.width
                height: Math.max(0, root.selectionRect.y)
                color: Qt.rgba(0, 0, 0, 0.45)
            }
            Rectangle { // Bottom
                x: 0; y: root.selectionRect.y + root.selectionRect.height
                width: parent.width
                height: Math.max(0, parent.height - y)
                color: Qt.rgba(0, 0, 0, 0.45)
            }
            Rectangle { // Left
                x: 0; y: root.selectionRect.y
                width: Math.max(0, root.selectionRect.x)
                height: root.selectionRect.height
                color: Qt.rgba(0, 0, 0, 0.45)
            }
            Rectangle { // Right
                x: root.selectionRect.x + root.selectionRect.width
                y: root.selectionRect.y
                width: Math.max(0, parent.width - x)
                height: root.selectionRect.height
                color: Qt.rgba(0, 0, 0, 0.45)
            }
        }

        // Region drag MouseArea (disabled when annotating or recording).
        MouseArea {
            id: selectorMouse
            anchors.fill: parent
            hoverEnabled: !root.isRecording
            enabled: !root.isRecording && !annotationCanvas.drawingEnabled
            cursorShape: Qt.CrossCursor

            onPressed: function(mouse) {
                root.isSelecting = true
                root.hasSelection = false
                root.dragStart = Qt.point(mouse.x, mouse.y)
                root.cursorPos = Qt.point(mouse.x, mouse.y)
                root.selectionRect = Qt.rect(mouse.x, mouse.y, 0, 0)
                annotationCanvas.clear()
            }

            onPositionChanged: function(mouse) {
                root.cursorPos = Qt.point(mouse.x, mouse.y)
                if (!root.isSelecting) {
                    return
                }
                var rx = Math.min(root.dragStart.x, mouse.x)
                var ry = Math.min(root.dragStart.y, mouse.y)
                var rw = Math.abs(mouse.x - root.dragStart.x)
                var rh = Math.abs(mouse.y - root.dragStart.y)
                root.selectionRect = Qt.rect(rx, ry, rw, rh)
            }

            onReleased: {
                root.isSelecting = false
                root.hasSelection = (root.selectionRect.width >= 8 && root.selectionRect.height >= 8)
                if (!root.hasSelection) {
                    root.selectionRect = Qt.rect(0, 0, 0, 0)
                }
            }
        }

        // Selection outline + embedded AnnotationCanvas inside crop bounds.
        Rectangle {
            id: selectionFrame
            visible: root.selectionRect.width > 1 && root.selectionRect.height > 1
            x: root.selectionRect.x
            y: root.selectionRect.y
            width: root.selectionRect.width
            height: root.selectionRect.height
            color: "transparent"
            border.width: 2
            border.color: root.isRecording ? "#ef4444" : "#00e5a3"

            AnnotationCanvas {
                id: annotationCanvas
                anchors.fill: parent
                visible: !root.isRecording
            }
        }

        // Dimension readout badge above/inside selection.
        Rectangle {
            visible: selectionFrame.visible && !root.isRecording
            x: Math.max(8, Math.min(parent.width - width - 8, root.selectionRect.x))
            y: root.selectionRect.y > 36 ? root.selectionRect.y - 32 : root.selectionRect.y + 8
            width: dimLabel.implicitWidth + 18
            height: 24
            radius: 12
            color: Qt.rgba(0.118, 0.118, 0.180, 0.92)
            border.width: 1
            border.color: Qt.rgba(0.0, 0.90, 0.64, 0.50)

            Label {
                id: dimLabel
                anchors.centerIn: parent
                color: "#f8fafc"
                font.pixelSize: 11
                font.bold: true
                text: Math.round(root.selectionRect.width) + " × " + Math.round(root.selectionRect.height) + " px"
            }
        }

        // 4x Pixel-Perfect Magnifier Loupe following cursor when selecting/positioning.
        Item {
            id: loupeRoot
            visible: !root.isRecording && backdropImage.status === Image.Ready && (root.isSelecting || !root.hasSelection)
            width: 120
            height: 142
            x: root.cursorPos.x + 26 + width > parent.width
               ? root.cursorPos.x - width - 22
               : root.cursorPos.x + 26
            y: root.cursorPos.y + 26 + height > parent.height
               ? root.cursorPos.y - height - 22
               : root.cursorPos.y + 26

            readonly property real scaleX: backdropImage.sourceSize.width / Math.max(1, parent.width)
            readonly property real scaleY: backdropImage.sourceSize.height / Math.max(1, parent.height)
            readonly property int sampleSize: 30

            Item {
                id: loupeCircleArea
                width: 120
                height: 120

                Image {
                    id: zoomedImage
                    anchors.fill: parent
                    visible: false
                    cache: false
                    smooth: false
                    source: backdropImage.source
                    sourceClipRect: Qt.rect(
                        Math.max(0, Math.round(root.cursorPos.x * loupeRoot.scaleX - loupeRoot.sampleSize / 2)),
                        Math.max(0, Math.round(root.cursorPos.y * loupeRoot.scaleY - loupeRoot.sampleSize / 2)),
                        loupeRoot.sampleSize,
                        loupeRoot.sampleSize
                    )
                }

                Rectangle {
                    id: circleMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: parent
                    source: zoomedImage
                    maskEnabled: true
                    maskSource: circleMask
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: "#00e5a3"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 1
                    color: "#ef4444"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 14
                    color: "#ef4444"
                }
            }

            Rectangle {
                anchors.top: loupeCircleArea.bottom
                anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: coordText.implicitWidth + 12
                height: 18
                radius: 8
                color: Qt.rgba(0.118, 0.118, 0.180, 0.92)

                Label {
                    id: coordText
                    anchors.centerIn: parent
                    color: "#e2e8f0"
                    font.pixelSize: 10
                    text: Math.round(root.cursorPos.x) + ", " + Math.round(root.cursorPos.y)
                }
            }
        }

        // Subtle DropShadow behind the floating capture / recording toolbar.
        RectangularShadow {
            visible: actionBar.visible
            x: actionBar.x
            y: actionBar.y
            width: actionBar.width
            height: actionBar.height
            radius: actionBar.radius
            offset: Qt.vector2d(0, 8)
            blur: 22
            spread: 1
            color: Qt.rgba(0, 0, 0, 0.65)
        }

        // Floating Toolbar directly beneath selectionRect (morphs into live REC MM:SS + Stop when recording).
        Rectangle {
            id: actionBar
            visible: (root.hasSelection && !root.isSelecting) || root.isRecording
            width: (root.isRecording ? liveRecRow.implicitWidth : barCol.implicitWidth) + 24
            height: (root.isRecording ? liveRecRow.implicitHeight : barCol.implicitHeight) + 18
            radius: 16
            color: Qt.rgba(0.118, 0.118, 0.180, 0.95)
            border.width: 1
            border.color: root.isRecording
                          ? Qt.rgba(0.94, 0.27, 0.27, 0.70)
                          : Qt.rgba(0.0, 0.90, 0.64, 0.45)

            x: Math.max(12, Math.min(parent.width - width - 12,
                                     root.selectionRect.x + (root.selectionRect.width - width) / 2))
            y: root.selectionRect.y + root.selectionRect.height + height + 16 < parent.height
               ? root.selectionRect.y + root.selectionRect.height + 12
               : Math.max(12, root.selectionRect.y - height - 12)

            onXChanged: if (root.isRecording) root.syncRecordingMask()
            onYChanged: if (root.isRecording) root.syncRecordingMask()
            onWidthChanged: if (root.isRecording) root.syncRecordingMask()
            onHeightChanged: if (root.isRecording) root.syncRecordingMask()

            component ToolbarActionBtn : Rectangle {
                id: actBtn
                property string label: ""
                property string iconKind: "shot"
                property bool primary: false
                property bool danger: false
                signal triggered()

                implicitWidth: btnContent.implicitWidth + 20
                implicitHeight: 34
                radius: 10
                color: danger
                       ? (actMouse.pressed ? "#dc2626" : (actHover.hovered ? "#f87171" : "#ef4444"))
                       : (primary
                          ? (actMouse.pressed ? Qt.darker("#00e5a3", 1.15)
                                              : (actHover.hovered ? "#22f3b5" : "#00e5a3"))
                          : (actMouse.pressed ? Qt.rgba(1, 1, 1, 0.16)
                                              : (actHover.hovered ? Qt.rgba(1, 1, 1, 0.12)
                                                                  : Qt.rgba(1, 1, 1, 0.06))))
                border.width: 1
                border.color: (primary || danger)
                              ? Qt.rgba(1, 1, 1, 0.35)
                              : (actHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.55) : Qt.rgba(1, 1, 1, 0.12))

                HoverHandler { id: actHover }

                Row {
                    id: btnContent
                    anchors.centerIn: parent
                    spacing: 6

                    Canvas {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: 14
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var fg = actBtn.primary ? "#091216" : (actBtn.danger ? "#ffffff" : "#e2e8f0")
                            ctx.strokeStyle = fg
                            ctx.fillStyle = fg
                            ctx.lineWidth = 1.5
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            if (actBtn.iconKind === "shot") {
                                ctx.beginPath()
                                ctx.rect(2, 3.5, 10, 7.5)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.arc(7, 7.25, 2, 0, Math.PI * 2)
                                ctx.stroke()
                            } else if (actBtn.iconKind === "mp4") {
                                ctx.beginPath()
                                ctx.rect(1.5, 3.5, 7.5, 7)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(9, 5.5)
                                ctx.lineTo(12.5, 3.8)
                                ctx.lineTo(12.5, 10.2)
                                ctx.lineTo(9, 8.5)
                                ctx.closePath()
                                ctx.stroke()
                            } else if (actBtn.iconKind === "stop") {
                                ctx.fillRect(3, 3, 8, 8)
                            } else {
                                ctx.beginPath()
                                ctx.moveTo(3.5, 3.5)
                                ctx.lineTo(10.5, 10.5)
                                ctx.moveTo(10.5, 3.5)
                                ctx.lineTo(3.5, 10.5)
                                ctx.stroke()
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: actBtn.primary ? "#091216" : (actBtn.danger ? "#ffffff" : "#f1f5f9")
                        font.pixelSize: 12
                        font.weight: (actBtn.primary || actBtn.danger) ? Font.DemiBold : Font.Medium
                        text: actBtn.label
                    }
                }

                MouseArea {
                    id: actMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: actBtn.triggered()
                }
            }

            // Selection Mode Toolbar (Annotation Tools + OmniShot Screenshot + Record MP4)
            ColumnLayout {
                id: barCol
                visible: !root.isRecording
                anchors.centerIn: parent
                spacing: 8

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "Select", tool: "none" },
                            { label: "Arrow", tool: "arrow" },
                            { label: "Rect", tool: "rect" },
                            { label: "Blur", tool: "blur" }
                        ]

                        delegate: Rectangle {
                            id: toolChip
                            required property var modelData
                            readonly property bool active: annotationCanvas.activeTool === modelData.tool

                            implicitWidth: toolText.implicitWidth + 16
                            implicitHeight: 24
                            radius: 8
                            color: active
                                   ? Qt.rgba(0.0, 0.90, 0.64, 0.22)
                                   : (toolHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04))
                            border.width: 1
                            border.color: active ? "#00e5a3" : Qt.rgba(1, 1, 1, 0.10)

                            HoverHandler { id: toolHover }

                            Text {
                                id: toolText
                                anchors.centerIn: parent
                                color: toolChip.active ? "#00e5a3" : "#cbd5e1"
                                font.pixelSize: 11
                                font.weight: toolChip.active ? Font.DemiBold : Font.Normal
                                text: toolChip.modelData.label
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: annotationCanvas.activeTool = toolChip.modelData.tool
                            }
                        }
                    }

                    Rectangle {
                        implicitWidth: undoLbl.implicitWidth + 16
                        implicitHeight: 24
                        radius: 8
                        opacity: annotationCanvas.annotations.length > 0 ? 1.0 : 0.40
                        color: undoHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.10)

                        HoverHandler { id: undoHover }

                        Text {
                            id: undoLbl
                            anchors.centerIn: parent
                            color: "#cbd5e1"
                            font.pixelSize: 11
                            text: "Undo"
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: annotationCanvas.annotations.length > 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: annotationCanvas.undo()
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    ToolbarActionBtn {
                        label: "Screenshot (OmniShot)"
                        iconKind: "shot"
                        primary: true
                        onTriggered: root.commitOmniShot()
                    }
                    ToolbarActionBtn {
                        label: "Record MP4"
                        iconKind: "mp4"
                        onTriggered: root.beginRegionRecording()
                    }
                    ToolbarActionBtn {
                        label: "Cancel"
                        iconKind: "cancel"
                        onTriggered: root.cancelOverlay()
                    }
                }
            }

            // Live Recording Mode Toolbar (Pulsing indicator + MM:SS Timer + Stop Recording)
            RowLayout {
                id: liveRecRow
                visible: root.isRecording
                anchors.centerIn: parent
                spacing: 12

                Rectangle {
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: "#ef4444"

                    SequentialAnimation on opacity {
                        running: root.isRecording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 480 }
                        NumberAnimation { to: 1.0; duration: 480 }
                    }
                }

                Text {
                    color: "#fca5a5"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    text: "REC"
                }

                Text {
                    color: "#f8fafc"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.family: "monospace"
                    text: root.formatDuration(root.elapsedSeconds)
                }

                ToolbarActionBtn {
                    label: "Stop Recording"
                    iconKind: "stop"
                    danger: true
                    onTriggered: root.stopRegionRecording()
                }
            }
        }
    }
}
