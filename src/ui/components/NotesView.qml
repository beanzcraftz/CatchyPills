pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Persistent To-Do & Quick Notes tab backed by SQLite ($XDG_DATA_HOME/CatchyPills/catchypills.db3).
 */
Item {
    id: root

    readonly property bool inputFocused: noteInput.activeFocus
    signal collapseRequested()

    function focusInput() {
        noteInput.forceActiveFocus()
    }

    function submitNote() {
        if (notesModel.addNote(noteInput.text)) {
            noteInput.text = ""
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Persistent Header Guidance
        Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            color: "#94a3b8"
            font.pixelSize: 11
            text: "Quick Notes • Persistent tasks & thoughts saved locally to SQLite"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: noteInput
                Layout.fillWidth: true
                placeholderText: "Type a thought or quick task and hit Enter..."
                placeholderTextColor: "#64748b"
                color: "#f8fafc"
                background: Rectangle {
                    radius: 12
                    color: Qt.rgba(0.16, 0.16, 0.24, 0.72)
                    border.width: 1
                    border.color: noteInput.activeFocus
                                  ? "#00e5a3"
                                  : Qt.rgba(1, 1, 1, 0.12)
                }
                onAccepted: root.submitNote()
                onActiveFocusChanged: {
                    if (!activeFocus) {
                        root.collapseRequested()
                    }
                }
            }

            Button {
                text: "Add"
                implicitHeight: 34
                enabled: noteInput.text.trim().length > 0
                onClicked: root.submitNote()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: notesList
                anchors.fill: parent
                clip: true
                spacing: 6
                model: notesModel

                delegate: Rectangle {
                    id: noteDelegate
                    required property var noteId
                    required property string content
                    required property string createdAt
                    width: notesList.width
                    height: Math.max(54, noteRowLayout.implicitHeight + 24)
                    radius: 12
                    color: noteHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.10) : Qt.rgba(0.16, 0.16, 0.24, 0.62)
                    border.width: 1
                    border.color: noteHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.45) : Qt.rgba(1, 1, 1, 0.08)

                    HoverHandler { id: noteHover }

                    RowLayout {
                        id: noteRowLayout
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        spacing: 12

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: tsLabel.implicitWidth + 14
                            implicitHeight: 24
                            radius: 8
                            color: Qt.rgba(0.0, 0.90, 0.64, 0.14)
                            border.width: 1
                            border.color: Qt.rgba(0.0, 0.90, 0.64, 0.35)

                            Label {
                                id: tsLabel
                                anchors.centerIn: parent
                                color: "#00e5a3"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                text: noteDelegate.createdAt
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            wrapMode: Text.WordWrap
                            color: "#f1f5f9"
                            font.pixelSize: 12
                            text: noteDelegate.content
                        }

                        Button {
                            Layout.alignment: Qt.AlignTop
                            text: "×"
                            implicitWidth: 26
                            implicitHeight: 26
                            ToolTip.visible: hovered
                            ToolTip.delay: 450
                            ToolTip.text: "Delete note"
                            onClicked: notesModel.deleteNote(noteDelegate.noteId)
                        }
                    }
                }
            }

            // Centered Onboarding Empty State
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 380)
                visible: notesList.count === 0
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

                            ctx.beginPath()
                            ctx.moveTo(6, 4.5)
                            ctx.lineTo(15, 4.5)
                            ctx.lineTo(19, 8.5)
                            ctx.lineTo(19, 19.5)
                            ctx.lineTo(6, 19.5)
                            ctx.closePath()
                            ctx.stroke()

                            ctx.beginPath()
                            ctx.moveTo(9, 11.5)
                            ctx.lineTo(15.5, 11.5)
                            ctx.moveTo(9, 15.5)
                            ctx.lineTo(13.5, 15.5)
                            ctx.stroke()
                        }
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    text: "Quick Notes & Tasks"
                }

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#94a3b8"
                    font.pixelSize: 12
                    text: "Type a thought or quick task above and hit Enter to save it persistently."
                }
            }
        }
    }
}
