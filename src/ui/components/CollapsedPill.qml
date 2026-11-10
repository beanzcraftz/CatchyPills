import QtQuick

Item {
    id: root
    implicitWidth: 260
    implicitHeight: 36

    property string tickerText: "CatchyPills"
    property bool recordingActive: false
    property bool daemonOnline: true
    property bool externalDragActive: false
    readonly property bool dragging: dragArea.dragging

    signal dragPressed()
    signal dragStarted()
    signal dragMoved(real dx, real dy)
    signal dragFinished()
    signal clicked()

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: !root.externalDragActive
        acceptedButtons: Qt.LeftButton
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
            pressX = mouse.x
            pressY = mouse.y
            dragging = false
            root.dragPressed()
        }

        onPositionChanged: function(mouse) {
            if (!pressed) {
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
            root.dragMoved(dx, dy)
        }

        onReleased: function(mouse) {
            if (dragging) {
                dragging = false
                root.dragFinished()
            } else if (mouse.x >= 0 && mouse.x <= width && mouse.y >= 0 && mouse.y <= height) {
                root.clicked()
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
        anchors.centerIn: parent
        spacing: 8

        // Status indicator dot: red pulse when recording, amber when daemon offline, cyan when ready.
        Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: root.recordingActive
                   ? "#ef4444"
                   : (root.daemonOnline ? "#38bdf8" : "#f59e0b")

            SequentialAnimation on opacity {
                running: root.recordingActive
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 480 }
                NumberAnimation { to: 1.0; duration: 480 }
            }
        }

        // Subtle offline indicator icon shown whenever catchypillsd D-Bus is unreachable.
        Canvas {
            id: offlineIcon
            visible: !root.daemonOnline && !root.recordingActive
            width: 14
            height: 14
            anchors.verticalCenter: parent.verticalCenter

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#f59e0b"
                ctx.lineWidth = 1.6
                ctx.lineCap = "round"

                // Subtle disconnected link slash icon
                ctx.beginPath()
                ctx.arc(4.5, 9.5, 2.5, Math.PI * 0.25, Math.PI * 1.25)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(9.5, 4.5, 2.5, Math.PI * 1.25, Math.PI * 0.25)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(2.5, 2.5)
                ctx.lineTo(11.5, 11.5)
                ctx.stroke()
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 184)
            elide: Text.ElideRight
            color: (!root.daemonOnline && !root.recordingActive) ? "#fcd34d" : "#f1f5f9"
            font.pixelSize: 12
            font.weight: Font.Medium
            text: root.recordingActive
                  ? "Recording active..."
                  : (!root.daemonOnline ? "Daemon offline" : root.tickerText)
        }
    }
}
