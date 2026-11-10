import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

/**
 * Fullscreen Wayland zwlr_layer_shell_v1 region-selection overlay (attached in
 * main.cpp with LayerOverlay, all 4 edge anchors, exclusiveZone = -1, and
 * KeyboardInteractivityExclusive so it covers the entire 3840x1080 monitor).
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
    property rect selectionRect: Qt.rect(0, 0, 0, 0)

    onVisibleChanged: {
        if (visible) {
            resetState()
            overlayScope.forceActiveFocus()
        }
    }

    function resetState() {
        isSelecting = false
        hasSelection = false
        selectionRect = Qt.rect(0, 0, 0, 0)
        annotationCanvas.activeTool = "none"
        annotationCanvas.clear()
    }

    function cancelOverlay() {
        resetState()
        root.visible = false
    }

    function commitCapture(saveFile, copyClipboard) {
        if (!hasSelection || selectionRect.width < 4 || selectionRect.height < 4) {
            return
        }
        // Snapshot geometry & annotations before hiding so KWin unmaps the overlay
        // surface cleanly before ScreenShot2::CaptureArea grabs fresh pixels.
        pendingCrop.action = "image"
        pendingCrop.x = Math.round(selectionRect.x)
        pendingCrop.y = Math.round(selectionRect.y)
        pendingCrop.w = Math.round(selectionRect.width)
        pendingCrop.h = Math.round(selectionRect.height)
        pendingCrop.annotations = annotationCanvas.exportAnnotations()
        pendingCrop.saveFile = saveFile
        pendingCrop.copyClipboard = copyClipboard

        root.visible = false
        finalizeTimer.restart()
    }

    function commitRecording(preset) {
        if (!hasSelection || selectionRect.width < 8 || selectionRect.height < 8) {
            return
        }
        pendingCrop.action = "record"
        pendingCrop.x = Math.round(selectionRect.x)
        pendingCrop.y = Math.round(selectionRect.y)
        pendingCrop.w = Math.round(selectionRect.width)
        pendingCrop.h = Math.round(selectionRect.height)
        pendingCrop.recordPreset = preset

        root.visible = false
        finalizeTimer.restart()
    }

    QtObject {
        id: pendingCrop
        property string action: "image"
        property int x: 0
        property int y: 0
        property int w: 0
        property int h: 0
        property var annotations: []
        property bool saveFile: true
        property bool copyClipboard: true
        property int recordPreset: 0
    }

    Timer {
        id: finalizeTimer
        interval: 60
        onTriggered: {
            if (pendingCrop.action === "record") {
                captureCoordinator.startRecording(
                    pendingCrop.recordPreset,
                    Qt.rect(pendingCrop.x, pendingCrop.y, pendingCrop.w, pendingCrop.h)
                )
            } else {
                captureCoordinator.finalizeRegionCapture(
                    pendingCrop.x,
                    pendingCrop.y,
                    pendingCrop.w,
                    pendingCrop.h,
                    pendingCrop.annotations,
                    false,
                    pendingCrop.saveFile,
                    pendingCrop.copyClipboard
                )
            }
            root.resetState()
        }
    }

    Item {
        id: overlayScope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.cancelOverlay()
        Keys.onReturnPressed: root.commitCapture(true, configManager.autoCopyCapture)
        Keys.onEnterPressed: root.commitCapture(true, configManager.autoCopyCapture)
        Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Z) {
                annotationCanvas.undo()
                event.accepted = true
            }
        }

        // Frozen desktop backdrop supplied by CaptureImageProvider (ScreenShot2)
        // so the loupe magnifier can inspect real desktop pixels under Wayland.
        Image {
            id: backdropImage
            anchors.fill: parent
            cache: false
            fillMode: Image.PreserveAspectCrop
            source: captureCoordinator.backdropRevision > 0
                    ? "image://capture/backdrop?" + captureCoordinator.backdropRevision
                    : ""
        }

        // 4-part dimming mask around selectionRect (keeps crop crisp at 100% brightness).
        Rectangle {
            visible: !root.hasSelection && !root.isSelecting
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Item {
            visible: root.hasSelection || root.isSelecting
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

        // Region drag MouseArea (active when no annotation tool is selected).
        MouseArea {
            id: selectorMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !annotationCanvas.drawingEnabled
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
            border.color: "#00e5a3"

            AnnotationCanvas {
                id: annotationCanvas
                anchors.fill: parent
            }
        }

        // Dimension readout badge above/inside selection.
        Rectangle {
            visible: selectionFrame.visible
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
            visible: backdropImage.status === Image.Ready && (root.isSelecting || !root.hasSelection)
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

                // Precision crosshair
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

        // Subtle DropShadow behind the floating capture toolbar.
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

        // Floating Annotation & Capture Action Toolbar anchored directly beneath selectionRect.
        Rectangle {
            id: actionBar
            visible: root.hasSelection && !root.isSelecting
            width: barCol.implicitWidth + 24
            height: barCol.implicitHeight + 18
            radius: 16
            color: Qt.rgba(0.118, 0.118, 0.180, 0.95)
            border.width: 1
            border.color: Qt.rgba(0.0, 0.90, 0.64, 0.45)

            x: Math.max(12, Math.min(parent.width - width - 12,
                                     root.selectionRect.x + (root.selectionRect.width - width) / 2))
            y: root.selectionRect.y + root.selectionRect.height + height + 16 < parent.height
               ? root.selectionRect.y + root.selectionRect.height + 12
               : Math.max(12, root.selectionRect.y - height - 12)

            component ToolbarActionBtn : Rectangle {
                id: actBtn
                property string label: ""
                property string iconKind: "save"
                property bool primary: false
                property bool btnEnabled: true
                signal triggered()

                implicitWidth: btnContent.implicitWidth + 20
                implicitHeight: 34
                radius: 10
                opacity: btnEnabled ? 1.0 : 0.45
                color: primary
                       ? (actMouse.pressed ? Qt.darker("#00e5a3", 1.15)
                                           : (actHover.hovered ? "#22f3b5" : "#00e5a3"))
                       : (actMouse.pressed ? Qt.rgba(1, 1, 1, 0.16)
                                           : (actHover.hovered ? Qt.rgba(1, 1, 1, 0.12)
                                                               : Qt.rgba(1, 1, 1, 0.06)))
                border.width: 1
                border.color: primary
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
                            ctx.strokeStyle = actBtn.primary ? "#091216" : "#e2e8f0"
                            ctx.fillStyle = actBtn.primary ? "#091216" : "#e2e8f0"
                            ctx.lineWidth = 1.5
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            if (actBtn.iconKind === "save") {
                                ctx.beginPath()
                                ctx.moveTo(7, 2)
                                ctx.lineTo(7, 9.5)
                                ctx.moveTo(4, 6.5)
                                ctx.lineTo(7, 9.8)
                                ctx.lineTo(10, 6.5)
                                ctx.moveTo(2.5, 11.5)
                                ctx.lineTo(11.5, 11.5)
                                ctx.stroke()
                            } else if (actBtn.iconKind === "copy") {
                                ctx.beginPath()
                                ctx.rect(4.5, 4.5, 7, 7.5)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(2.5, 9)
                                ctx.lineTo(2.5, 2.5)
                                ctx.lineTo(9, 2.5)
                                ctx.stroke()
                            } else if (actBtn.iconKind === "gif") {
                                ctx.beginPath()
                                ctx.rect(2, 3, 10, 8)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(5.8, 5.2)
                                ctx.lineTo(9.2, 7)
                                ctx.lineTo(5.8, 8.8)
                                ctx.closePath()
                                ctx.fill()
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
                        color: actBtn.primary ? "#091216" : "#f1f5f9"
                        font.pixelSize: 12
                        font.weight: actBtn.primary ? Font.DemiBold : Font.Medium
                        text: actBtn.label
                    }
                }

                MouseArea {
                    id: actMouse
                    anchors.fill: parent
                    enabled: actBtn.btnEnabled
                    cursorShape: Qt.PointingHandCursor
                    onClicked: actBtn.triggered()
                }
            }

            ColumnLayout {
                id: barCol
                anchors.centerIn: parent
                spacing: 8

                // Annotation micro-tools row
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

                // Primary Capture & Recording Action Buttons directly beneath selection
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    ToolbarActionBtn {
                        label: "Save Image"
                        iconKind: "save"
                        primary: true
                        onTriggered: root.commitCapture(true, configManager.autoCopyCapture)
                    }
                    ToolbarActionBtn {
                        label: "Copy Image"
                        iconKind: "copy"
                        onTriggered: root.commitCapture(false, true)
                    }
                    ToolbarActionBtn {
                        label: "Record GIF"
                        iconKind: "gif"
                        onTriggered: root.commitRecording(0)
                    }
                    ToolbarActionBtn {
                        label: "Record MP4"
                        iconKind: "mp4"
                        onTriggered: root.commitRecording(1)
                    }
                    ToolbarActionBtn {
                        label: "Cancel"
                        iconKind: "cancel"
                        onTriggered: root.cancelOverlay()
                    }
                }
            }
        }
    }
}
