pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Instant fuzzy file & folder search view powered by nucleo via catchypillsd.
 */
Item {
    id: root

    readonly property bool inputFocused: searchInput.activeFocus
    signal collapseRequested()

    function focusInput() {
        searchInput.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        TextField {
            id: searchInput
            Layout.fillWidth: true
            placeholderText: "Fuzzy search $HOME files (powered by nucleo)..."
            placeholderTextColor: "#64748b"
            color: "#f8fafc"
            background: Rectangle {
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.07)
                border.width: 1
                border.color: searchInput.activeFocus
                              ? Qt.rgba(0.22, 0.74, 0.97, 0.7)
                              : Qt.rgba(1, 1, 1, 0.12)
            }
            onTextChanged: daemonClient.searchFiles(text)
            onActiveFocusChanged: {
                if (!activeFocus) {
                    root.collapseRequested()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: searchList
                anchors.fill: parent
                clip: true
                spacing: 4
                model: daemonClient.searchResults

                delegate: Rectangle {
                    id: resultDelegate
                    required property var modelData
                    width: searchList.width
                    height: 36
                    radius: 9
                    color: searchHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)

                    HoverHandler { id: searchHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Label {
                            color: "#e2e8f0"
                            font.pixelSize: 12
                            font.bold: true
                            text: resultDelegate.modelData.name
                        }
                        Label {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            color: "#94a3b8"
                            font.pixelSize: 11
                            text: resultDelegate.modelData.path
                        }
                        Label {
                            color: "#38bdf8"
                            font.pixelSize: 10
                            text: resultDelegate.modelData.score
                        }
                    }
                }
            }

            // Centered Onboarding / No-Results State
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 380)
                visible: searchList.count === 0
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 26
                    color: Qt.rgba(0.65, 0.55, 0.98, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(0.65, 0.55, 0.98, 0.35)

                    Canvas {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = "#c4b5fd"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"

                            ctx.beginPath()
                            ctx.arc(10.5, 10.5, 6.0, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.beginPath()
                            ctx.moveTo(15.0, 15.0)
                            ctx.lineTo(20.0, 20.0)
                            ctx.stroke()
                        }
                    }
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    text: searchInput.text.trim().length === 0 ? "Instant File Search" : "No Matches"
                }

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#94a3b8"
                    font.pixelSize: 12
                    text: searchInput.text.trim().length === 0
                          ? "Start typing to instantly search your files and folders across your system."
                          : "No files matched \"" + searchInput.text.trim() + "\"."
                }
            }
        }
    }
}
