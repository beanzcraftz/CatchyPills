import QtQuick

Item {
    id: root
    implicitWidth: 260
    implicitHeight: 36

    property string tickerText: "CatchyPills"
    property bool recordingActive: false
    property bool daemonOnline: true

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
