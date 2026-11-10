import QtQuick
import QtQuick.Controls

Item {
    id: root
    implicitWidth: Math.max(320, Math.ceil(pillRow.implicitWidth) + 28)
    implicitHeight: 36

    property bool recordingActive: false
    property bool daemonOnline: true
    property bool externalDragActive: false
    readonly property bool dragging: dragArea.dragging
    readonly property bool repositioning: dragArea.pressed || dragArea.dragging
    readonly property bool hasSysMon: typeof sysMonController !== "undefined" && sysMonController !== null
    readonly property int cpuUsage: hasSysMon ? sysMonController.cpuPercent : 0
    readonly property int ramUsage: hasSysMon ? sysMonController.ramPercent : 0
    readonly property var cpuSamples: hasSysMon ? sysMonController.cpuHistory : []

    signal dragPressed()
    signal dragStarted()
    signal dragMoved(real dx, real dy, real anchorX, real anchorY)
    signal dragFinished()
    signal clicked()

    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: !root.externalDragActive && !dragArea.pressed && !dragArea.dragging
        onTapped: root.clicked()
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: !root.externalDragActive
        acceptedButtons: Qt.RightButton
        hoverEnabled: false
        cursorShape: (pressed || dragging) ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        onEnabledChanged: {
            if (!enabled) {
                dragging = false
            }
        }

        property real pressX: 0
        property real pressY: 0
        property bool dragging: false

        onPressed: function(mouse) {
            if (mouse.button !== Qt.RightButton) {
                mouse.accepted = false
                return
            }
            pressX = mouse.x
            pressY = mouse.y
            dragging = false
            root.dragPressed()
        }

        onPositionChanged: function(mouse) {
            if (!pressed || !(mouse.buttons & Qt.RightButton)) {
                return
            }
            var dx = mouse.x - pressX
            var dy = mouse.y - pressY
            if (!dragging) {
                if (Math.hypot(dx, dy) < 5) {
                    return
                }
                dragging = true
                root.dragStarted()
            }
            root.dragMoved(dx, dy, pressX, pressY)
        }

        onReleased: {
            if (dragging) {
                dragging = false
                root.dragFinished()
            }
        }

        onCanceled: {
            if (dragging) {
                dragging = false
                root.dragFinished()
            }
        }
    }

    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: 8

        Image {
            id: pillLogo
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            source: "qrc:/assets/logo.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        // Brand wordmark & live status
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            visible: !root.recordingActive && root.daemonOnline

            Text {
                color: "#f8fafc"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                text: "Catchy"
            }

            Text {
                color: "#00e5a3"
                font.pixelSize: 13
                font.weight: Font.Bold
                text: "Pills"
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.recordingActive || !root.daemonOnline
            color: root.recordingActive ? "#fca5a5" : "#fcd34d"
            font.pixelSize: 12
            font.weight: Font.Medium
            text: root.recordingActive ? "Recording active..." : "Daemon offline"
        }

        // Status indicator dot: red pulse when recording, amber when daemon offline, neon emerald when ready.
        Rectangle {
            width: 7
            height: 7
            radius: 3.5
            anchors.verticalCenter: parent.verticalCenter
            color: root.recordingActive
                   ? "#ef4444"
                   : (root.daemonOnline ? "#00e5a3" : "#f59e0b")

            SequentialAnimation on opacity {
                running: root.recordingActive
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 480 }
                NumberAnimation { to: 1.0; duration: 480 }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            color: Qt.rgba(1, 1, 1, 0.14)
        }

        // Compact CPU sparkline + CPU/RAM monospace readout
        Item {
            id: sysMonCluster
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: sysMonRow.implicitWidth
            implicitHeight: 24

            HoverHandler { id: sysMonHover }

            ToolTip.visible: sysMonHover.hovered && !root.repositioning
            ToolTip.delay: 250
            ToolTip.text: "CPU: " + root.cpuUsage + "% | RAM: " + root.ramUsage + "%"

            Row {
                id: sysMonRow
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 18
                    radius: 5
                    color: Qt.rgba(0.0, 0.0, 0.0, 0.22)
                    border.width: 1
                    border.color: Qt.rgba(0.0, 0.90, 0.64, 0.20)

                    Canvas {
                        id: sparklineCanvas
                        anchors.centerIn: parent
                        width: 44
                        height: 14

                        Connections {
                            target: root.hasSysMon ? sysMonController : null
                            function onCpuHistoryChanged() {
                                sparklineCanvas.requestPaint()
                            }
                        }

                        Component.onCompleted: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)

                            var samples = root.cpuSamples
                            if (!samples || samples.length === 0) {
                                return
                            }

                            var n = samples.length
                            var padY = 1.5
                            var drawH = height - padY * 2
                            var stepX = n > 1 ? (width / (n - 1)) : width

                            ctx.beginPath()
                            if (n === 1) {
                                var v0 = Math.max(0, Math.min(100, Number(samples[0])))
                                var y0 = padY + drawH * (1.0 - v0 / 100.0)
                                ctx.moveTo(0, y0)
                                ctx.lineTo(width, y0)
                            } else {
                                for (var i = 0; i < n; ++i) {
                                    var val = Math.max(0, Math.min(100, Number(samples[i])))
                                    var px = i * stepX
                                    var py = padY + drawH * (1.0 - val / 100.0)
                                    if (i === 0) {
                                        ctx.moveTo(px, py)
                                    } else {
                                        ctx.lineTo(px, py)
                                    }
                                }
                            }

                            ctx.strokeStyle = "#00e5a3"
                            ctx.lineWidth = 1.5
                            ctx.lineJoin = "round"
                            ctx.lineCap = "round"
                            ctx.stroke()

                            // Subtle translucent emerald area fill under the sparkline
                            ctx.lineTo(width, height)
                            ctx.lineTo(0, height)
                            ctx.closePath()
                            var grad = ctx.createLinearGradient(0, 0, 0, height)
                            grad.addColorStop(0.0, "rgba(0, 229, 163, 0.28)")
                            grad.addColorStop(1.0, "rgba(0, 229, 163, 0.03)")
                            ctx.fillStyle = grad
                            ctx.fill()
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -1

                    Text {
                        color: "#00e5a3"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        font.family: "monospace"
                        text: "CPU " + root.cpuUsage + "%"
                    }

                    Text {
                        color: "#94a3b8"
                        font.pixelSize: 9
                        font.family: "monospace"
                        text: "RAM " + root.ramUsage + "%"
                    }
                }
            }
        }
    }
}
