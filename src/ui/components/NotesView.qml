pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Persistent To-Do & Quick Notes tab with action alarms backed by SQLite
 * ($XDG_DATA_HOME/CatchyPills/catchypills.db3).
 */
Item {
    id: root

    property int selectedPresetMinutes: 0 // 0 = None, >0 = preset mins, -1 = custom HH:MM
    property bool customTimeInvalid: false
    readonly property bool inputFocused: noteInput.activeFocus || customAlarmInput.activeFocus
    signal collapseRequested()

    function focusInput() {
        noteInput.forceActiveFocus()
    }

    function submitNote() {
        if (noteInput.text.trim().length === 0) {
            return
        }

        var alarmEpoch = 0
        if (selectedPresetMinutes === -1) {
            alarmEpoch = notesModel.computeAlarmEpochFromHHMM(customAlarmInput.text)
            if (alarmEpoch < 0) {
                customTimeInvalid = true
                customAlarmInput.forceActiveFocus()
                return
            }
        } else if (selectedPresetMinutes > 0) {
            alarmEpoch = Math.floor(Date.now() / 1000) + selectedPresetMinutes * 60
        }

        if (notesModel.addNote(noteInput.text, alarmEpoch)) {
            noteInput.text = ""
            customAlarmInput.text = ""
            selectedPresetMinutes = 0
            customTimeInvalid = false
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
            text: "Quick Notes • Persistent tasks & timed reminders saved locally to SQLite"
        }

        // Input bar + Quick Alarm Picker chips + HH:MM custom input
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            TextField {
                id: noteInput
                Layout.fillWidth: true
                Layout.minimumWidth: 160
                placeholderText: "Add note or task..."
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
                    if (!noteInput.activeFocus && !customAlarmInput.activeFocus) {
                        root.collapseRequested()
                    }
                }
            }

            Rectangle {
                implicitWidth: alarmPickerRow.implicitWidth + 10
                implicitHeight: 34
                radius: 12
                color: Qt.rgba(0.14, 0.14, 0.22, 0.75)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.10)

                RowLayout {
                    id: alarmPickerRow
                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: [
                            { label: "None", mins: 0 },
                            { label: "+15m", mins: 15 },
                            { label: "+30m", mins: 30 },
                            { label: "+1h", mins: 60 },
                            { label: "+2h", mins: 120 }
                        ]

                        delegate: Rectangle {
                            id: presetChip
                            required property var modelData
                            readonly property bool active: root.selectedPresetMinutes === modelData.mins

                            implicitWidth: chipText.implicitWidth + 10
                            implicitHeight: 24
                            radius: 8
                            color: active
                                   ? (modelData.mins === 0 ? Qt.rgba(0.0, 0.90, 0.64, 0.18) : Qt.rgba(0.96, 0.62, 0.04, 0.22))
                                   : (chipHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                            border.width: 1
                            border.color: active
                                          ? (modelData.mins === 0 ? "#00e5a3" : "#f59e0b")
                                          : "transparent"

                            HoverHandler { id: chipHover }

                            Label {
                                id: chipText
                                anchors.centerIn: parent
                                color: presetChip.active
                                       ? (presetChip.modelData.mins === 0 ? "#00e5a3" : "#fcd34d")
                                       : "#cbd5e1"
                                font.pixelSize: 10
                                font.weight: presetChip.active ? Font.DemiBold : Font.Normal
                                text: presetChip.modelData.label
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedPresetMinutes = presetChip.modelData.mins
                                    root.customTimeInvalid = false
                                    if (presetChip.modelData.mins >= 0) {
                                        customAlarmInput.text = ""
                                    }
                                }
                            }
                        }
                    }

                    TextField {
                        id: customAlarmInput
                        implicitWidth: 56
                        implicitHeight: 24
                        topPadding: 2
                        bottomPadding: 2
                        leftPadding: 4
                        rightPadding: 4
                        horizontalAlignment: Text.AlignHCenter
                        placeholderText: "HH:MM"
                        placeholderTextColor: "#64748b"
                        maximumLength: 5
                        color: root.selectedPresetMinutes === -1 ? "#fcd34d" : "#e2e8f0"
                        font.pixelSize: 10
                        font.family: "monospace"
                        background: Rectangle {
                            radius: 8
                            color: root.selectedPresetMinutes === -1
                                   ? Qt.rgba(0.96, 0.62, 0.04, 0.16)
                                   : Qt.rgba(1, 1, 1, 0.05)
                            border.width: 1
                            border.color: root.customTimeInvalid
                                          ? "#ef4444"
                                          : ((customAlarmInput.activeFocus || root.selectedPresetMinutes === -1)
                                             ? "#f59e0b"
                                             : Qt.rgba(1, 1, 1, 0.12))
                        }
                        ToolTip.visible: hovered || root.customTimeInvalid
                        ToolTip.delay: 250
                        ToolTip.text: root.customTimeInvalid
                                      ? "Use 24-hour HH:MM (e.g. 14:30)"
                                      : "Custom 24-hour alarm time (HH:MM)"
                        onTextEdited: {
                            root.customTimeInvalid = false
                            if (text.trim().length > 0) {
                                root.selectedPresetMinutes = -1
                            } else if (root.selectedPresetMinutes === -1) {
                                root.selectedPresetMinutes = 0
                            }
                        }
                        onAccepted: root.submitNote()
                        onActiveFocusChanged: {
                            if (!noteInput.activeFocus && !customAlarmInput.activeFocus) {
                                root.collapseRequested()
                            }
                        }
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
                    required property var alarmAt
                    required property string alarmTimeText
                    required property bool hasPendingAlarm
                    required property bool alarmTriggered
                    width: notesList.width
                    height: Math.max(54, noteRowLayout.implicitHeight + 24)
                    radius: 12
                    color: noteDelegate.alarmTriggered
                           ? Qt.rgba(0.96, 0.62, 0.04, 0.14)
                           : (noteHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.10) : Qt.rgba(0.16, 0.16, 0.24, 0.62))
                    border.width: 1
                    border.color: noteDelegate.alarmTriggered
                                  ? "#f59e0b"
                                  : (noteHover.hovered ? Qt.rgba(0.0, 0.90, 0.64, 0.45) : Qt.rgba(1, 1, 1, 0.08))

                    HoverHandler { id: noteHover }

                    RowLayout {
                        id: noteRowLayout
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        spacing: 8

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

                        // Glowing alarm badge for scheduled/triggered reminders
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            visible: noteDelegate.hasPendingAlarm || noteDelegate.alarmTriggered
                            implicitWidth: alarmBadgeLbl.implicitWidth + 14
                            implicitHeight: 24
                            radius: 8
                            color: noteDelegate.alarmTriggered
                                   ? Qt.rgba(0.96, 0.62, 0.04, 0.28)
                                   : Qt.rgba(0.96, 0.62, 0.04, 0.14)
                            border.width: 1
                            border.color: noteDelegate.alarmTriggered ? "#fbbf24" : Qt.rgba(0.96, 0.62, 0.04, 0.55)

                            Label {
                                id: alarmBadgeLbl
                                anchors.centerIn: parent
                                color: "#fcd34d"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                text: noteDelegate.alarmTriggered
                                      ? "⏰ Due"
                                      : ("⏰ " + noteDelegate.alarmTimeText)
                            }
                        }

                        // Snooze +10m button visible once alarm triggers
                        Rectangle {
                            id: snoozeBtn
                            Layout.alignment: Qt.AlignVCenter
                            visible: noteDelegate.alarmTriggered
                            implicitWidth: snoozeLbl.implicitWidth + 12
                            implicitHeight: 24
                            radius: 8
                            color: snoozeHover.hovered
                                   ? Qt.rgba(0.0, 0.90, 0.64, 0.28)
                                   : Qt.rgba(0.0, 0.90, 0.64, 0.16)
                            border.width: 1
                            border.color: "#00e5a3"

                            HoverHandler { id: snoozeHover }

                            ToolTip.visible: snoozeHover.hovered
                            ToolTip.delay: 300
                            ToolTip.text: "Snooze alarm for 10 minutes"

                            Label {
                                id: snoozeLbl
                                anchors.centerIn: parent
                                color: "#00e5a3"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                text: "+10m"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notesModel.snoozeAlarm(noteDelegate.noteId, 10)
                            }
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
                    text: "Type a task above, optionally pick an alarm preset or HH:MM time, and hit Enter."
                }
            }
        }
    }
}
