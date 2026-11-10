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

    function commitCapture() {
        if (!hasSelection || selectionRect.width < 4 || selectionRect.height < 4) {
            return
        }
        // Snapshot geometry & annotations before hiding so KWin unmaps the overlay
        // surface cleanly before ScreenShot2::CaptureArea grabs fresh pixels.
        pendingCrop.x = Math.round(selectionRect.x)
        pendingCrop.y = Math.round(selectionRect.y)
        pendingCrop.w = Math.round(selectionRect.width)
        pendingCrop.h = Math.round(selectionRect.height)
        pendingCrop.annotations = annotationCanvas.exportAnnotations()

        root.visible = false
        finalizeTimer.restart()
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
        id: finalizeTimer
        interval: 60
        onTriggered: {
            captureCoordinator.finalizeRegionCapture(
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

        Keys.onEscapePressed: root.cancelOverlay()
        Keys.onReturnPressed: root.commitCapture()
        Keys.onEnterPressed: root.commitCapture()
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
            border.color: "#38bdf8"

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
            width: dimLabel.implicitWidth + 16
            height: 24
            radius: 6
            color: Qt.rgba(0.06, 0.08, 0.11, 0.9)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)

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
                    border.color: "#38bdf8"
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
                radius: 4
                color: Qt.rgba(0.05, 0.07, 0.1, 0.9)

                Label {
                    id: coordText
                    anchors.centerIn: parent
                    color: "#e2e8f0"
                    font.pixelSize: 10
                    text: Math.round(root.cursorPos.x) + ", " + Math.round(root.cursorPos.y)
                }
            }
        }

        // Floating Annotation & Confirm Toolbar anchored below (or above) selectionRect.
        Rectangle {
            id: actionBar
            visible: root.hasSelection && !root.isSelecting
            width: barRow.implicitWidth + 16
            height: 44
            radius: 22
            color: Qt.rgba(0.07, 0.09, 0.12, 0.94)
            border.width: 1
            border.color: Qt.rgba(0.22, 0.74, 0.97, 0.5)

            x: Math.max(12, Math.min(parent.width - width - 12,
                                     root.selectionRect.x + (root.selectionRect.width - width) / 2))
            y: root.selectionRect.y + root.selectionRect.height + 56 < parent.height
               ? root.selectionRect.y + root.selectionRect.height + 12
               : Math.max(12, root.selectionRect.y - height - 12)

            RowLayout {
                id: barRow
                anchors.centerIn: parent
                spacing: 6

                Button {
                    text: "Select"
                    checked: annotationCanvas.activeTool === "none"
                    onClicked: annotationCanvas.activeTool = "none"
                }
                Button {
                    text: "Arrow"
                    checked: annotationCanvas.activeTool === "arrow"
                    onClicked: annotationCanvas.activeTool = "arrow"
                }
                Button {
                    text: "Rect"
                    checked: annotationCanvas.activeTool === "rect"
                    onClicked: annotationCanvas.activeTool = "rect"
                }
                Button {
                    text: "Blur"
                    checked: annotationCanvas.activeTool === "blur"
                    onClicked: annotationCanvas.activeTool = "blur"
                }
                Button {
                    text: "Undo"
                    enabled: annotationCanvas.annotations.length > 0
                    onClicked: annotationCanvas.undo()
                }
                Button {
                    text: "Capture (Enter)"
                    highlighted: true
                    onClicked: root.commitCapture()
                }
                Button {
                    text: "Cancel"
                    onClicked: root.cancelOverlay()
                }
            }
        }
    }
}
