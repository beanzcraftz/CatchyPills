import QtQuick
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

    // Collapse the island cleanly when OmniShot CaptureOverlay opens.
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

        Rectangle {
            id: pillContainer
            state: "collapsed"

            readonly property int collapsedX: root.hasLayer ? layerController.pillCanvasX : 250
            readonly property int collapsedY: root.hasLayer ? layerController.pillCanvasY : 0
            readonly property int expandedX: Math.max(0, Math.min(collapsedX - 200, root.width - 660))
            readonly property int expandedY: Math.min(collapsedY, root.height - 390)
            readonly property bool detachedFromTop: root.hasLayer && layerController.pillY > 4

            x: collapsedX
            y: collapsedY
            width: 260
            height: 36
            topLeftRadius: detachedFromTop ? 18 : 0
            topRightRadius: detachedFromTop ? 18 : 0
            bottomLeftRadius: 18
            bottomRightRadius: 18
            // Translucent dark-glass surface backed by KWin's ext_background_effect_v1
            // blur region synchronized through LayerSurfaceController::updateInputRegion.
            color: Qt.rgba(0.06, 0.08, 0.11, 0.72)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
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
                        if (!collapsedHud.dragging && !root.dragActive && pillContainer.state !== "expanded") {
                            hoverExpandDelay.restart()
                        }
                    } else {
                        hoverExpandDelay.stop()
                        if (!root.dragActive) {
                            collapseDelay.restart()
                        }
                    }
                }
            }

            // Brief hover settle distinguishes intentional rest-to-open from click-and-drag.
            Timer {
                id: hoverExpandDelay
                interval: 180
                onTriggered: {
                    if (islandHover.hovered && !collapsedHud.dragging && !root.dragActive) {
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
                    if (!islandHover.hovered && !dashboard.searchInputFocused && !collapsedHud.dragging && !root.dragActive) {
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
                        pillContainer.width: 260
                        pillContainer.height: 36
                        pillContainer.topLeftRadius: pillContainer.detachedFromTop ? 18 : 0
                        pillContainer.topRightRadius: pillContainer.detachedFromTop ? 18 : 0
                        pillContainer.bottomLeftRadius: 18
                        pillContainer.bottomRightRadius: 18
                    }
                },
                State {
                    name: "expanded"
                    PropertyChanges {
                        pillContainer.x: pillContainer.expandedX
                        pillContainer.y: pillContainer.expandedY
                        pillContainer.width: 660
                        pillContainer.height: 390
                        pillContainer.topLeftRadius: pillContainer.detachedFromTop ? 28 : 0
                        pillContainer.topRightRadius: pillContainer.detachedFromTop ? 28 : 0
                        pillContainer.bottomLeftRadius: 28
                        pillContainer.bottomRightRadius: 28
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
                tickerText: daemonClient.latestClipPreview.length > 0
                            ? daemonClient.latestClipPreview
                            : "CatchyPills"

                onDragPressed: hoverExpandDelay.stop()
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
                onDragMoved: function(dx, dy) {
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
                    layerController.setAbsolutePosition(
                        layerController.pillX + stepX,
                        layerController.pillY + stepY
                    )
                    if (layerController.surfaceX !== prevSurfX || layerController.surfaceY !== prevSurfY) {
                        dragThrottle.restart()
                    }
                }
                onDragFinished: {
                    dragThrottle.stop()
                    if (root.hasLayer) {
                        configManager.setAbsolutePosition(layerController.pillX, layerController.pillY)
                    }
                }
                onClicked: {
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
