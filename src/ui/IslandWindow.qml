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

    onVisibleChanged: {
        if (visible) {
            pillContainer.syncMask()
        }
    }

    // Collapse the island cleanly when OmniShot CaptureOverlay opens.
    Connections {
        target: captureCoordinator
        function onRegionOverlayRequested() {
            pillContainer.state = "collapsed"
            if (typeof layerController !== "undefined" && layerController !== null) {
                layerController.setKeyboardInteractive(false)
            }
        }
    }

    Rectangle {
        id: pillContainer
        state: "collapsed"

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: 260
        height: 36
        topLeftRadius: 0
        topRightRadius: 0
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
            if (typeof layerController !== "undefined" && layerController !== null) {
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
                    pillContainer.state = "expanded"
                    layerController.setKeyboardInteractive(true)
                } else {
                    collapseDelay.restart()
                }
            }
        }

        Timer {
            id: collapseDelay
            interval: 220
            onTriggered: {
                if (!islandHover.hovered && !dashboard.searchInputFocused) {
                    pillContainer.state = "collapsed"
                    layerController.setKeyboardInteractive(false)
                }
            }
        }

        states: [
            State {
                name: "collapsed"
                PropertyChanges {
                    pillContainer.width: 260
                    pillContainer.height: 36
                    pillContainer.bottomLeftRadius: 18
                    pillContainer.bottomRightRadius: 18
                }
            },
            State {
                name: "expanded"
                PropertyChanges {
                    pillContainer.width: 660
                    pillContainer.height: 390
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
                        properties: "width,height"
                        spring: 4.5
                        damping: 0.34
                    }
                    NumberAnimation {
                        properties: "bottomLeftRadius,bottomRightRadius"
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
                        properties: "width,height,bottomLeftRadius,bottomRightRadius"
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
            tickerText: daemonClient.latestClipPreview.length > 0
                        ? daemonClient.latestClipPreview
                        : "CatchyPills"
        }

        ExpandedDashboard {
            id: dashboard
            anchors.fill: parent
            visible: pillContainer.height >= 96
            opacity: pillContainer.state === "expanded" ? 1.0 : 0.0
            onCollapseRequested: collapseDelay.restart()

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
    }
}
