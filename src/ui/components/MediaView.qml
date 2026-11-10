pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * SpotiBar-inspired MPRIS2 Media Controller adapted for standalone QtQuick/LayerShellQt,
 * featuring CachyCyberWave (#00e5a3 neon emerald) & NativePlasmaBreeze styling,
 * glowing Play/Pause transport, album artwork, and a live 4-bar equalizer.
 */
Item {
    id: root

    property bool cyberWaveStyle: true

    readonly property color accentColor: cyberWaveStyle ? "#00e5a3" : "#38bdf8"
    readonly property color glowColor: cyberWaveStyle
                                       ? Qt.rgba(0.0, 0.90, 0.64, 0.24)
                                       : Qt.rgba(0.22, 0.74, 0.97, 0.22)

    component EqualizerBar : Rectangle {
        id: eqBar
        property bool active: false
        property int barDuration: 340
        property real peakHeight: 18

        implicitWidth: 4
        implicitHeight: 4
        height: 4
        radius: 2
        color: root.accentColor

        SequentialAnimation on height {
            running: eqBar.active
            loops: Animation.Infinite
            NumberAnimation {
                to: eqBar.peakHeight
                duration: eqBar.barDuration
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                to: 4
                duration: eqBar.barDuration
                easing.type: Easing.InOutQuad
            }
        }

        onActiveChanged: {
            if (!active) {
                height = 4
            }
        }

        Behavior on height {
            enabled: !eqBar.active
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // Persistent Tab Guidance + SpotiBar Theme Toggle
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: "#94a3b8"
                font.pixelSize: 11
                text: "Now Playing • Control Spotify & MPRIS2 playback"
            }

            Rectangle {
                visible: mprisController.hasPlayer
                implicitWidth: playerTag.implicitWidth + 14
                implicitHeight: 22
                radius: 11
                color: root.glowColor
                border.width: 1
                border.color: root.accentColor

                Label {
                    id: playerTag
                    anchors.centerIn: parent
                    color: "#f8fafc"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    text: mprisController.playerName.length > 0 ? mprisController.playerName : "MPRIS2"
                }
            }

            // Segmented CyberWave / Breeze style pill
            Rectangle {
                implicitWidth: styleRow.implicitWidth + 6
                implicitHeight: 24
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                RowLayout {
                    id: styleRow
                    anchors.centerIn: parent
                    spacing: 2

                    Rectangle {
                        implicitWidth: cyberLbl.implicitWidth + 10
                        implicitHeight: 18
                        radius: 9
                        color: root.cyberWaveStyle ? Qt.rgba(0.0, 0.90, 0.64, 0.25) : "transparent"

                        Label {
                            id: cyberLbl
                            anchors.centerIn: parent
                            color: root.cyberWaveStyle ? "#00e5a3" : "#94a3b8"
                            font.pixelSize: 10
                            font.weight: root.cyberWaveStyle ? Font.DemiBold : Font.Normal
                            text: "CyberWave"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cyberWaveStyle = true
                        }
                    }

                    Rectangle {
                        implicitWidth: breezeLbl.implicitWidth + 10
                        implicitHeight: 18
                        radius: 9
                        color: !root.cyberWaveStyle ? Qt.rgba(0.22, 0.74, 0.97, 0.25) : "transparent"

                        Label {
                            id: breezeLbl
                            anchors.centerIn: parent
                            color: !root.cyberWaveStyle ? "#7dd3fc" : "#94a3b8"
                            font.pixelSize: 10
                            font.weight: !root.cyberWaveStyle ? Font.DemiBold : Font.Normal
                            text: "Breeze"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cyberWaveStyle = false
                        }
                    }
                }
            }
        }

        // Main SpotiBar Playback Card
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 16
            color: root.cyberWaveStyle
                   ? Qt.rgba(0.14, 0.15, 0.21, 0.72)
                   : Qt.rgba(0.16, 0.16, 0.24, 0.62)
            border.width: 1
            border.color: mprisController.playing
                          ? root.accentColor
                          : Qt.rgba(1, 1, 1, 0.12)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                visible: mprisController.hasPlayer

                // Album Art Tile with Glow Border
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 112
                    implicitHeight: 112
                    radius: 14
                    clip: true
                    color: Qt.rgba(0, 0, 0, 0.42)
                    border.width: 1.5
                    border.color: mprisController.playing
                                  ? root.accentColor
                                  : Qt.rgba(1, 1, 1, 0.16)

                    Image {
                        id: albumArt
                        anchors.fill: parent
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 160
                        sourceSize.height: 160
                        source: mprisController.artUrl
                        visible: mprisController.artUrl.length > 0 && status === Image.Ready
                    }

                    Canvas {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        visible: !albumArt.visible
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = root.cyberWaveStyle ? "#00e5a3" : "#38bdf8"
                            ctx.lineWidth = 2.0
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            ctx.beginPath()
                            ctx.arc(12, 28, 5, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(27, 25, 5, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(17, 28)
                            ctx.lineTo(17, 10)
                            ctx.lineTo(32, 7)
                            ctx.lineTo(32, 25)
                            ctx.stroke()
                        }
                    }
                }

                // Track Info + Animated Equalizer + Transport
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: "#f8fafc"
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                text: mprisController.title.length > 0 ? mprisController.title : "Untitled Track"
                            }

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: root.accentColor
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                text: mprisController.artist.length > 0 ? mprisController.artist : mprisController.playerName
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: mprisController.album.length > 0
                                elide: Text.ElideRight
                                color: "#94a3b8"
                                font.pixelSize: 11
                                text: mprisController.album
                            }
                        }

                        // 4-Bar Animated Equalizer (rests smoothly when paused)
                        Item {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 25
                            implicitHeight: 20

                            Row {
                                anchors.fill: parent
                                spacing: 3

                                EqualizerBar {
                                    anchors.bottom: parent.bottom
                                    active: mprisController.playing
                                    barDuration: 320
                                    peakHeight: 18
                                }
                                EqualizerBar {
                                    anchors.bottom: parent.bottom
                                    active: mprisController.playing
                                    barDuration: 450
                                    peakHeight: 20
                                }
                                EqualizerBar {
                                    anchors.bottom: parent.bottom
                                    active: mprisController.playing
                                    barDuration: 270
                                    peakHeight: 15
                                }
                                EqualizerBar {
                                    anchors.bottom: parent.bottom
                                    active: mprisController.playing
                                    barDuration: 390
                                    peakHeight: 19
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Transport Controls
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: prevHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.14)

                            HoverHandler { id: prevHover }

                            Label {
                                anchors.centerIn: parent
                                color: "#e2e8f0"
                                font.pixelSize: 13
                                text: "⏮"
                            }

                            ToolTip.visible: prevHover.hovered
                            ToolTip.delay: 450
                            ToolTip.text: "Previous Track"

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mprisController.previous()
                            }
                        }

                        // Glowing Neon Emerald Play/Pause Button
                        Item {
                            implicitWidth: 50
                            implicitHeight: 50

                            Rectangle {
                                anchors.centerIn: parent
                                width: 50
                                height: 50
                                radius: 25
                                color: root.glowColor
                                visible: mprisController.playing || playHover.hovered

                                SequentialAnimation on scale {
                                    running: mprisController.playing
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 1.12; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.98; duration: 900; easing.type: Easing.InOutSine }
                                }
                            }

                            Rectangle {
                                id: playCore
                                anchors.centerIn: parent
                                width: 42
                                height: 42
                                radius: 21
                                color: playMouse.pressed
                                       ? Qt.darker(root.accentColor, 1.15)
                                       : root.accentColor
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.45)

                                HoverHandler { id: playHover }

                                Canvas {
                                    id: playGlyph
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    property bool isPlaying: mprisController.playing
                                    onIsPlayingChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.fillStyle = "#04161a"

                                        if (isPlaying) {
                                            ctx.fillRect(4, 3, 3.5, 12)
                                            ctx.fillRect(10.5, 3, 3.5, 12)
                                        } else {
                                            ctx.beginPath()
                                            ctx.moveTo(5, 2.5)
                                            ctx.lineTo(15.5, 9)
                                            ctx.lineTo(5, 15.5)
                                            ctx.closePath()
                                            ctx.fill()
                                        }
                                    }
                                }

                                ToolTip.visible: playHover.hovered
                                ToolTip.delay: 450
                                ToolTip.text: mprisController.playing ? "Pause Playback" : "Resume Playback"

                                MouseArea {
                                    id: playMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mprisController.playPause()
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: nextHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.14)

                            HoverHandler { id: nextHover }

                            Label {
                                anchors.centerIn: parent
                                color: "#e2e8f0"
                                font.pixelSize: 13
                                text: "⏭"
                            }

                            ToolTip.visible: nextHover.hovered
                            ToolTip.delay: 450
                            ToolTip.text: "Next Track"

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mprisController.next()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            color: mprisController.playing ? root.accentColor : "#64748b"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            text: mprisController.playbackStatus
                        }
                    }
                }
            }

            // Empty State when no MPRIS2 player is running
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 380)
                visible: !mprisController.hasPlayer
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 26
                    color: root.glowColor
                    border.width: 1
                    border.color: root.accentColor

                    Canvas {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = root.cyberWaveStyle ? "#00e5a3" : "#38bdf8"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            ctx.beginPath()
                            ctx.arc(8, 17, 3, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(17, 15, 3, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(11, 17)
                            ctx.lineTo(11, 5)
                            ctx.lineTo(20, 3.5)
                            ctx.lineTo(20, 15)
                            ctx.stroke()
                        }
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    text: "No Active Media Player"
                }

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#94a3b8"
                    font.pixelSize: 12
                    text: "Start Spotify, VLC, or browser media playback to see album art, equalizer waves, and MPRIS2 controls here."
                }
            }
        }
    }
}
