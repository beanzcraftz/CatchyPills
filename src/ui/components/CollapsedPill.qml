import QtQuick

Item {
    id: root
    implicitWidth: 260
    implicitHeight: 36

    property bool recordingActive: false
    property bool daemonOnline: true
    property bool externalDragActive: false
    readonly property bool dragging: dragArea.dragging

    signal dragPressed()
    signal dragStarted()
    signal dragMoved(real dx, real dy, real anchorX, real anchorY)
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
            root.dragMoved(dx, dy, pressX, pressY)
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
    }
}
