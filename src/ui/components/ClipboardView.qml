pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Clipboard History tab populated via D-Bus from catchypillsd.
 */
Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Persistent Header Guidance
        Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            color: "#94a3b8"
            font.pixelSize: 11
            text: "Recent Clips • Click to copy to active clipboard • Pin items to keep permanently"
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: clipboardList
                anchors.fill: parent
                clip: true
                spacing: 8
                model: daemonClient.recentClips

                delegate: Rectangle {
                    id: clipDelegate
                    required property var modelData
                    width: clipboardList.width
                    height: 52
                    radius: 12
                    color: clipHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.10) : Qt.rgba(0.16, 0.16, 0.24, 0.62)
                    border.width: 1
                    border.color: clipHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.45) : Qt.rgba(1, 1, 1, 0.08)

                    HoverHandler { id: clipHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Rectangle {
                            implicitWidth: 48
                            implicitHeight: 22
                            radius: 8
                            color: clipDelegate.modelData.kind === "image"
                                   ? Qt.rgba(0.65, 0.55, 0.98, 0.22)
                                   : Qt.rgba(0.0, 0.90, 0.64, 0.16)
                            Label {
                                anchors.centerIn: parent
                                color: clipDelegate.modelData.kind === "image" ? "#c4b5fd" : "#00e5a3"
                                font.pixelSize: 10
                                font.bold: true
                                text: clipDelegate.modelData.kind.toUpperCase()
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: "#f1f5f9"
                            font.pixelSize: 12
                            text: clipDelegate.modelData.preview
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: daemonClient.copyClipText(clipDelegate.modelData.preview)
                    }
                }
            }

            // Centered Onboarding Empty State
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 380)
                visible: clipboardList.count === 0
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 26
                    color: Qt.rgba(0.22, 0.74, 0.97, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(0.22, 0.74, 0.97, 0.35)

                    Canvas {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = "#38bdf8"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"

                            function strokeRoundRect(rx, ry, rw, rh, rad) {
                                ctx.beginPath()
                                ctx.moveTo(rx + rad, ry)
                                ctx.lineTo(rx + rw - rad, ry)
                                ctx.quadraticCurveTo(rx + rw, ry, rx + rw, ry + rad)
                                ctx.lineTo(rx + rw, ry + rh - rad)
                                ctx.quadraticCurveTo(rx + rw, ry + rh, rx + rw - rad, ry + rh)
                                ctx.lineTo(rx + rad, ry + rh)
                                ctx.quadraticCurveTo(rx, ry + rh, rx, ry + rh - rad)
                                ctx.lineTo(rx, ry + rad)
                                ctx.quadraticCurveTo(rx, ry, rx + rad, ry)
                                ctx.closePath()
                                ctx.stroke()
                            }

                            strokeRoundRect(5, 5, 14, 16, 2.5)
                            strokeRoundRect(9, 2.5, 6, 4, 1.2)
                            ctx.beginPath()
                            ctx.moveTo(8.5, 11)
                            ctx.lineTo(15.5, 11)
                            ctx.moveTo(8.5, 15)
                            ctx.lineTo(13.5, 15)
                            ctx.stroke()
                        }
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    text: "Clipboard History"
                }

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#94a3b8"
                    font.pixelSize: 12
                    text: "Clipboard is empty. Copy text, links, or images, and they will securely appear here."
                }
            }
        }
    }
}
