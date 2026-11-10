pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Unified Search tab supporting both nucleo local file indexing (via catchypillsd)
 * and DuckDuckGo web search in the default desktop browser.
 */
Item {
    id: root

    property int searchMode: 0 // 0 = Local Files, 1 = Web Search
    readonly property bool inputFocused: searchInput.activeFocus
    signal collapseRequested()
    signal collapseImmediatelyRequested()

    function focusInput() {
        searchInput.forceActiveFocus()
    }

    function setSearchMode(mode) {
        if (searchMode === mode) {
            return
        }
        searchMode = mode
        if (searchMode === 0) {
            daemonClient.searchFiles(searchInput.text)
        }
        searchInput.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Persistent Tab Guidance + Segmented Local / Web Switch
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: "#94a3b8"
                font.pixelSize: 11
                text: "Unified Search • Fuzzy search indexed home files or query the web"
            }

            Rectangle {
                implicitWidth: modeRow.implicitWidth + 6
                implicitHeight: 26
                radius: 13
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)

                RowLayout {
                    id: modeRow
                    anchors.centerIn: parent
                    spacing: 2

                    Rectangle {
                        implicitWidth: localLbl.implicitWidth + 12
                        implicitHeight: 20
                        radius: 10
                        color: root.searchMode === 0 ? Qt.rgba(0.22, 0.74, 0.97, 0.25) : "transparent"

                        Label {
                            id: localLbl
                            anchors.centerIn: parent
                            color: root.searchMode === 0 ? "#7dd3fc" : "#94a3b8"
                            font.pixelSize: 10
                            font.weight: root.searchMode === 0 ? Font.DemiBold : Font.Normal
                            text: "Local Files"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSearchMode(0)
                        }
                    }

                    Rectangle {
                        implicitWidth: webLbl.implicitWidth + 12
                        implicitHeight: 20
                        radius: 10
                        color: root.searchMode === 1 ? Qt.rgba(0.98, 0.45, 0.20, 0.26) : "transparent"

                        Label {
                            id: webLbl
                            anchors.centerIn: parent
                            color: root.searchMode === 1 ? "#fdba74" : "#94a3b8"
                            font.pixelSize: 10
                            font.weight: root.searchMode === 1 ? Font.DemiBold : Font.Normal
                            text: "Web Search"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSearchMode(1)
                        }
                    }
                }
            }
        }

        TextField {
            id: searchInput
            Layout.fillWidth: true
            placeholderText: root.searchMode === 0
                             ? "Fuzzy search $HOME files (powered by nucleo)..."
                             : "Type a query and press Enter to search DuckDuckGo..."
            placeholderTextColor: "#64748b"
            color: "#f8fafc"
            background: Rectangle {
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.07)
                border.width: 1
                border.color: searchInput.activeFocus
                              ? (root.searchMode === 0
                                 ? Qt.rgba(0.22, 0.74, 0.97, 0.7)
                                 : Qt.rgba(0.98, 0.45, 0.20, 0.75))
                              : Qt.rgba(1, 1, 1, 0.12)
            }
            onTextChanged: {
                if (root.searchMode === 0) {
                    daemonClient.searchFiles(text)
                }
            }
            onAccepted: {
                if (root.searchMode === 1 && text.trim().length > 0) {
                    appController.openWebSearch(text)
                    text = ""
                    root.collapseImmediatelyRequested()
                }
            }
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
                visible: root.searchMode === 0
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

            // Centered Local Empty / No-Matches OR Web Search State
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 380)
                visible: root.searchMode === 1 || searchList.count === 0
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 26
                    color: root.searchMode === 1
                           ? Qt.rgba(0.98, 0.45, 0.20, 0.14)
                           : Qt.rgba(0.65, 0.55, 0.98, 0.12)
                    border.width: 1
                    border.color: root.searchMode === 1
                                  ? Qt.rgba(0.98, 0.45, 0.20, 0.45)
                                  : Qt.rgba(0.65, 0.55, 0.98, 0.35)

                    Canvas {
                        id: searchIconCanvas
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        property int mode: root.searchMode
                        onModeChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = mode === 1 ? "#fb923c" : "#c4b5fd"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"

                            if (mode === 1) {
                                // Globe / Web icon
                                ctx.beginPath()
                                ctx.arc(12, 12, 8.5, 0, Math.PI * 2)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.ellipse(8.2, 3.5, 7.6, 17)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(3.8, 12)
                                ctx.lineTo(20.2, 12)
                                ctx.stroke()
                            } else {
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
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    color: "#e2e8f0"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    text: root.searchMode === 1
                          ? "DuckDuckGo Web Search"
                          : (searchInput.text.trim().length === 0 ? "Instant File Search" : "No Matches")
                }

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#94a3b8"
                    font.pixelSize: 12
                    text: root.searchMode === 1
                          ? "Press Enter to search DuckDuckGo in browser"
                          : (searchInput.text.trim().length === 0
                             ? "Start typing to instantly search your files and folders across your system."
                             : "No files matched \"" + searchInput.text.trim() + "\".")
                }
            }
        }
    }
}
