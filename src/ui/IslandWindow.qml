import QtQuick
import QtQuick.Effects
import "components"

Window {
    id: root
    // Fixed transparent canvas sized to maximum expanded island bounds + shadow margin.
    // Animating pillContainer inside this fixed LayerShell surface avoids KWin
    // zwlr_layer_surface_v1 configure/ack resize roundtrips per animation frame.
    width: 760
    height: 460
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint

    readonly property bool hasLayer: typeof layerController !== "undefined" && layerController !== null
    property bool dragActive: false

    onDragActiveChanged: {
        if (dragActive) {
            hoverExpandDelay.stop()
            collapseDelay.stop()
        }
        if (hasLayer) {
            layerController.setDragActive(dragActive)
        }
    }

    onVisibleChanged: {
        if (visible) {
            pillContainer.syncMask()
        }
    }

    // Collapse the island cleanly when OmniShot CaptureOverlay opens or workflow completes.
    Connections {
        target: captureCoordinator
        function onRegionOverlayRequested() {
            dragExitLock.stop()
            hoverExpandDelay.stop()
            root.dragActive = false
            pillContainer.state = "collapsed"
            if (root.hasLayer) {
                layerController.setKeyboardInteractive(false)
            }
        }
        function onCaptureWorkflowFinished() {
            dragExitLock.stop()
            hoverExpandDelay.stop()
            collapseDelay.stop()
            root.dragActive = false
            pillContainer.state = "collapsed"
            if (root.hasLayer) {
                layerController.setKeyboardInteractive(false)
            }
        }
        function onSaveDialogOpenChanged(open) {
            if (open) {
                dragExitLock.stop()
                hoverExpandDelay.stop()
                collapseDelay.stop()
                root.dragActive = false
                pillContainer.state = "collapsed"
                if (root.hasLayer) {
                    layerController.setKeyboardInteractive(false)
                }
            }
        }
    }

    // Coalesce compositor margin commits (~2 vblanks) so stale pre-commit
    // Wayland pointer coordinates do not accumulate or ping-pong during drags.
    Timer {
        id: dragThrottle
        interval: 32
        repeat: false
    }

    // Debounce Wayland DropArea exit transitions so animation geometry shifts
    // and inner FileShelfView DropArea handoffs never flicker dragActive off.
    Timer {
        id: dragExitLock
        interval: 140
        repeat: false
        onTriggered: {
            if (!masterDropArea.containsDrag && !dashboard.shelfContainsDrag) {
                root.dragActive = false
                if (!islandHover.hovered && !dashboard.searchInputFocused) {
                    collapseDelay.restart()
                }
            }
        }
    }

    // Master Wayland DropArea spanning the entire 760x460 canvas so external file
    // drags arriving on the collapsed pill lock dragActive = true and unlock the
    // full surface mask without wl_data_device.leave collapse loops.
    DropArea {
        id: masterDropArea
        anchors.fill: parent

        onEntered: function(drag) {
            drag.acceptProposedAction()
            dragExitLock.stop()
            hoverExpandDelay.stop()
            collapseDelay.stop()
            root.dragActive = true
            dashboard.activeTab = 1
            pillContainer.state = "expanded"
        }

        onPositionChanged: function(drag) {
            drag.acceptProposedAction()
        }

        onExited: {
            if (!dashboard.shelfContainsDrag) {
                dragExitLock.restart()
            }
        }

        onDropped: function(drop) {
            dragExitLock.stop()
            dashboard.acceptShelfDrop(drop)
            root.dragActive = false
        }

        RectangularShadow {
            id: pillShadow
            x: pillContainer.x
            y: pillContainer.y
            width: pillContainer.width
            height: pillContainer.height
            offset: Qt.vector2d(0, 5)
            blur: pillContainer.state === "expanded" ? 22 : 14
            spread: 1
            color: root.dragActive ? Qt.rgba(0.0, 0.90, 0.64, 0.26) : Qt.rgba(0, 0, 0, 0.58)
            topLeftRadius: pillContainer.topLeftRadius
            topRightRadius: pillContainer.topRightRadius
            bottomLeftRadius: pillContainer.bottomLeftRadius
            bottomRightRadius: pillContainer.bottomRightRadius
        }

        Rectangle {
            id: pillContainer
            state: "collapsed"

            readonly property int collapsedX: root.hasLayer ? layerController.pillCanvasX : 220
            readonly property int collapsedY: root.hasLayer ? layerController.pillCanvasY : 0
            readonly property int expandedX: Math.max(0, Math.min(collapsedX - Math.round((660 - collapsedHud.implicitWidth) / 2), root.width - 660))
            readonly property int expandedY: Math.min(collapsedY, root.height - 390)
            readonly property bool detachedFromTop: root.hasLayer && layerController.pillY > 4

            x: collapsedX
            y: collapsedY
            width: collapsedHud.implicitWidth
            height: 36
            topLeftRadius: detachedFromTop ? 16 : 0
            topRightRadius: detachedFromTop ? 16 : 0
            bottomLeftRadius: 16
            bottomRightRadius: 16
            // Cohesive #1E1E2E dark glassmorphism with #00E5A3 neon emerald rim glow
            // backed by KWin's ext_background_effect_v1 blur region.
            color: Qt.rgba(0.118, 0.118, 0.180, 0.88)
            property color alarmPulseColor: "#f59e0b"
            SequentialAnimation on alarmPulseColor {
                running: notesModel.hasActiveAlarm
                loops: Animation.Infinite
                ColorAnimation { from: "#f59e0b"; to: "#00e5a3"; duration: 550 }
                ColorAnimation { from: "#00e5a3"; to: "#f59e0b"; duration: 550 }
            }
            border.width: notesModel.hasActiveAlarm ? 2 : 1
            border.color: notesModel.hasActiveAlarm
                          ? alarmPulseColor
                          : ((root.dragActive || state === "expanded")
                             ? Qt.rgba(0.0, 0.90, 0.64, 0.50)
                             : Qt.rgba(0.0, 0.90, 0.64, 0.30))
            clip: true

            // Update Wayland wl_surface.set_input_region via QWindow::setMask() on every
            // geometry change so pixels outside the visible pill stay click-through.
            onXChanged: syncMask()
            onYChanged: syncMask()
            onWidthChanged: syncMask()
            onHeightChanged: syncMask()

            function syncMask() {
                if (root.hasLayer) {
                    layerController.updateInputRegion(
                        Qt.rect(Math.round(x), Math.round(y), Math.round(width), Math.round(height)),
                        bottomLeftRadius
                    )
                }
            }

            // HoverHandler tracks pointer presence cleanly across child controls without
            // triggering spurious leave events when moving over internal TextFields/Buttons.
            HoverHandler {
                id: islandHover
                onHoveredChanged: {
                    if (hovered) {
                        collapseDelay.stop()
                        if (!collapsedHud.repositioning && !root.dragActive && pillContainer.state !== "expanded") {
                            hoverExpandDelay.restart()
                        }
                    } else {
                        hoverExpandDelay.stop()
                        if (!root.dragActive && !collapsedHud.repositioning) {
                            collapseDelay.restart()
                        }
                    }
                }
            }

            // Brief hover settle distinguishes intentional rest-to-open from right-click drag.
            Timer {
                id: hoverExpandDelay
                interval: 180
                onTriggered: {
                    if (islandHover.hovered && !collapsedHud.repositioning && !root.dragActive) {
                        pillContainer.state = "expanded"
                        if (root.hasLayer) {
                            layerController.setKeyboardInteractive(true)
                        }
                    }
                }
            }

            Timer {
                id: collapseDelay
                interval: configManager.collapseDelayMs
                onTriggered: {
                    if (!islandHover.hovered && !dashboard.searchInputFocused && !collapsedHud.repositioning && !root.dragActive) {
                        pillContainer.state = "collapsed"
                        if (root.hasLayer) {
                            layerController.setKeyboardInteractive(false)
                        }
                    }
                }
            }

            states: [
                State {
                    name: "collapsed"
                    PropertyChanges {
                        pillContainer.x: pillContainer.collapsedX
                        pillContainer.y: pillContainer.collapsedY
                        pillContainer.width: collapsedHud.implicitWidth
                        pillContainer.height: 36
                        pillContainer.topLeftRadius: pillContainer.detachedFromTop ? 16 : 0
                        pillContainer.topRightRadius: pillContainer.detachedFromTop ? 16 : 0
                        pillContainer.bottomLeftRadius: 16
                        pillContainer.bottomRightRadius: 16
                    }
                },
                State {
                    name: "expanded"
                    PropertyChanges {
                        pillContainer.x: pillContainer.expandedX
                        pillContainer.y: pillContainer.expandedY
                        pillContainer.width: 660
                        pillContainer.height: 390
                        pillContainer.topLeftRadius: pillContainer.detachedFromTop ? 22 : 0
                        pillContainer.topRightRadius: pillContainer.detachedFromTop ? 22 : 0
                        pillContainer.bottomLeftRadius: 22
                        pillContainer.bottomRightRadius: 22
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "collapsed"
                    to: "expanded"
                    ParallelAnimation {
                        SpringAnimation {
                            properties: "x,y,width,height"
                            spring: 4.5
                            damping: 0.34
                        }
                        NumberAnimation {
                            properties: "topLeftRadius,topRightRadius,bottomLeftRadius,bottomRightRadius"
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                },
                Transition {
                    from: "expanded"
                    to: "collapsed"
                    ParallelAnimation {
                        NumberAnimation {
                            properties: "x,y,width,height,topLeftRadius,topRightRadius,bottomLeftRadius,bottomRightRadius"
                            duration: 190
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            ]

            CollapsedPill {
                id: collapsedHud
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                visible: pillContainer.height < 64
                opacity: pillContainer.state === "collapsed" ? 1.0 : 0.0
                recordingActive: captureCoordinator.recording
                daemonOnline: appController.daemonOnline
                externalDragActive: root.dragActive
                alarmActive: notesModel.hasActiveAlarm
                alarmText: notesModel.activeAlarmText

                onSnoozeAlarmRequested: notesModel.snoozeAlarm(notesModel.activeAlarmNoteId, 10)
                onDismissAlarmRequested: notesModel.dismissAlarm(notesModel.activeAlarmNoteId)

                onDragPressed: {
                    hoverExpandDelay.stop()
                    collapseDelay.stop()
                }
                onDragStarted: {
                    if (root.dragActive) {
                        return
                    }
                    hoverExpandDelay.stop()
                    collapseDelay.stop()
                    pillContainer.state = "collapsed"
                    if (root.hasLayer) {
                        layerController.setKeyboardInteractive(false)
                    }
                }
                onDragMoved: function(dx, dy, anchorX, anchorY) {
                    if (!root.hasLayer || root.dragActive || dragThrottle.running) {
                        return
                    }
                    var stepX = Math.round(dx)
                    var stepY = Math.round(dy)
                    if (stepX === 0 && stepY === 0) {
                        return
                    }
                    var prevSurfX = layerController.surfaceX
                    var prevSurfY = layerController.surfaceY
                    var prevScreen = layerController.currentScreenName
                    layerController.dragBy(
                        stepX,
                        stepY,
                        Math.round(anchorX),
                        Math.round(anchorY)
                    )
                    if (layerController.currentScreenName === prevScreen
                        && (layerController.surfaceX !== prevSurfX || layerController.surfaceY !== prevSurfY)) {
                        dragThrottle.restart()
                    }
                }
                onDragFinished: {
                    dragThrottle.stop()
                    if (root.hasLayer) {
                        configManager.setMonitorAndPosition(
                            layerController.currentScreenName,
                            layerController.pillX,
                            layerController.pillY
                        )
                    }
                }
                onClicked: {
                    if (collapsedHud.repositioning || root.dragActive) {
                        return
                    }
                    hoverExpandDelay.stop()
                    collapseDelay.stop()
                    pillContainer.state = "expanded"
                    if (root.hasLayer) {
                        layerController.setKeyboardInteractive(true)
                    }
                }
            }

            ExpandedDashboard {
                id: dashboard
                anchors.fill: parent
                visible: pillContainer.height >= 96
                opacity: pillContainer.state === "expanded" ? 1.0 : 0.0
                onCollapseRequested: {
                    if (!root.dragActive) {
                        collapseDelay.restart()
                    }
                }
                onCollapseImmediatelyRequested: {
                    hoverExpandDelay.stop()
                    collapseDelay.stop()
                    pillContainer.state = "collapsed"
                    if (root.hasLayer) {
                        layerController.setKeyboardInteractive(false)
                    }
                }
                onShelfDropCompleted: {
                    dragExitLock.stop()
                    root.dragActive = false
                }
                onShelfDragHoverChanged: {
                    if (masterDropArea.containsDrag || dashboard.shelfContainsDrag) {
                        dragExitLock.stop()
                        hoverExpandDelay.stop()
                        collapseDelay.stop()
                        root.dragActive = true
                        pillContainer.state = "expanded"
                    } else {
                        dragExitLock.restart()
                    }
                }

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }
        }
    }
}
