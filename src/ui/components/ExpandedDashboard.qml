import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Tabbed expanded Dynamic Island workspace rendered over KWin's
 * ext_background_effect_v1 translucent blur mask (driven by LayerSurfaceController).
 */
Item {
    id: root

    property int activeTab: 0 // 0 = Clipboard, 1 = File Shelf, 2 = Search, 3 = Capture
    readonly property bool searchInputFocused: searchInput.activeFocus

    signal collapseRequested()

    // In-memory staging model for Wayland drag-and-drop File Shelf items.
    ListModel {
        id: shelfModel
    }

    function focusSearch() {
        activeTab = 2
        searchInput.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Glassmorphic Tab Strip + Capture Status
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { label: "Clipboard", icon: "📋" },
                    { label: "Shelf", icon: "📁" },
                    { label: "Search", icon: "🔍" },
                    { label: "Capture", icon: "📸" }
                ]

                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    readonly property bool selected: root.activeTab === index

                    implicitWidth: tabLabel.implicitWidth + 20
                    height: 30
                    radius: 15
                    color: selected
                           ? Qt.rgba(0.22, 0.74, 0.97, 0.22)
                           : tabHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: selected
                                  ? Qt.rgba(0.22, 0.74, 0.97, 0.65)
                                  : Qt.rgba(1, 1, 1, 0.10)

                    HoverHandler { id: tabHover }

                    Label {
                        id: tabLabel
                        anchors.centerIn: parent
                        color: selected ? "#f8fafc" : "#cbd5e1"
                        font.pixelSize: 12
                        font.weight: selected ? Font.DemiBold : Font.Normal
                        text: modelData.label
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.activeTab = index
                            if (index === 0) {
                                daemonClient.refreshClips()
                            } else if (index === 2) {
                                searchInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                color: "#94a3b8"
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.maximumWidth: 180
                text: captureCoordinator.lastStatus
            }
        }

        // Main Tab Body
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.activeTab

            // -----------------------------------------------------------------
            // 0. ClipboardView (populated via D-Bus from catchypillsd)
            // -----------------------------------------------------------------
            Item {
                ListView {
                    id: clipboardList
                    anchors.fill: parent
                    clip: true
                    spacing: 6
                    model: daemonClient.recentClips

                    delegate: Rectangle {
                        required property var modelData
                        width: clipboardList.width
                        height: 44
                        radius: 11
                        color: clipHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.08)

                        HoverHandler { id: clipHover }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Rectangle {
                                width: 46
                                height: 20
                                radius: 6
                                color: modelData.kind === "image"
                                       ? Qt.rgba(0.65, 0.55, 0.98, 0.22)
                                       : Qt.rgba(0.22, 0.74, 0.97, 0.20)
                                Label {
                                    anchors.centerIn: parent
                                    color: modelData.kind === "image" ? "#c4b5fd" : "#38bdf8"
                                    font.pixelSize: 10
                                    font.bold: true
                                    text: modelData.kind.toUpperCase()
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: "#f1f5f9"
                                font.pixelSize: 12
                                text: modelData.preview
                            }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: clipboardList.count === 0
                        color: "#64748b"
                        font.pixelSize: 12
                        text: "Waiting for Wayland clipboard events via catchypillsd..."
                    }
                }
            }

            // -----------------------------------------------------------------
            // 1. FileShelfView (Wayland wl_data_device drag-and-drop dropzone)
            // -----------------------------------------------------------------
            Item {
                Rectangle {
                    id: shelfDropZone
                    anchors.fill: parent
                    radius: 14
                    color: dropArea.containsDrag
                           ? Qt.rgba(0.22, 0.74, 0.97, 0.14)
                           : Qt.rgba(1, 1, 1, 0.03)
                    border.width: 1
                    border.color: dropArea.containsDrag
                                  ? Qt.rgba(0.22, 0.74, 0.97, 0.75)
                                  : Qt.rgba(1, 1, 1, 0.10)

                    DropArea {
                        id: dropArea
                        anchors.fill: parent
                        onEntered: function(drag) {
                            drag.acceptProposedAction()
                        }
                        onDropped: function(drop) {
                            if (drop.hasUrls) {
                                for (var i = 0; i < drop.urls.length; ++i) {
                                    var urlStr = drop.urls[i].toString()
                                    var parts = urlStr.split("/")
                                    shelfModel.append({
                                        name: parts[parts.length - 1] || urlStr,
                                        uri: urlStr,
                                        kind: "FILE"
                                    })
                                }
                                drop.acceptProposedAction()
                            } else if (drop.hasText && drop.text.trim().length > 0) {
                                shelfModel.append({
                                    name: drop.text.trim().slice(0, 64),
                                    uri: drop.text,
                                    kind: "TEXT"
                                })
                                drop.acceptProposedAction()
                            }
                        }
                    }

                    ListView {
                        id: shelfList
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        spacing: 6
                        model: shelfModel

                        delegate: Rectangle {
                            required property int index
                            required property string name
                            required property string uri
                            required property string kind
                            width: shelfList.width
                            height: 40
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.08)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                Label {
                                    color: "#34d399"
                                    font.pixelSize: 10
                                    font.bold: true
                                    text: kind
                                }
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                    color: "#e2e8f0"
                                    font.pixelSize: 12
                                    text: name
                                }
                                Button {
                                    text: "×"
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    onClicked: shelfModel.remove(index)
                                }
                            }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: shelfModel.count === 0
                        color: "#64748b"
                        font.pixelSize: 12
                        text: "Drag & drop files, URLs, or snippets here to stage on shelf"
                    }
                }
            }

            // -----------------------------------------------------------------
            // 2. SearchPaletteView (nucleo fuzzy search via catchypillsd)
            // -----------------------------------------------------------------
            ColumnLayout {
                spacing: 8

                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    placeholderText: "Fuzzy search $HOME files (powered by nucleo)..."
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

                ListView {
                    id: searchList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: daemonClient.searchResults

                    delegate: Rectangle {
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
                                text: modelData.name
                            }
                            Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                color: "#94a3b8"
                                font.pixelSize: 11
                                text: modelData.path
                            }
                            Label {
                                color: "#38bdf8"
                                font.pixelSize: 10
                                text: modelData.score
                            }
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // 3. Capture & GIF Recording Controls (ScreenShot2 + KPipeWire)
            // -----------------------------------------------------------------
            ColumnLayout {
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        Layout.fillWidth: true
                        text: "Region Snip (Annotate)"
                        highlighted: true
                        onClicked: captureCoordinator.prepareRegionCapture(false)
                    }
                    Button {
                        Layout.fillWidth: true
                        text: "Full Workspace (3840×1080)"
                        onClicked: captureCoordinator.captureWorkspace(false)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Button {
                        Layout.fillWidth: true
                        text: captureCoordinator.recording ? "Stop Recording" : "Record GIF (15 fps)"
                        onClicked: {
                            if (captureCoordinator.recording) {
                                captureCoordinator.stopRecording()
                            } else {
                                captureCoordinator.startRecording(0)
                            }
                        }
                    }
                    Button {
                        Layout.fillWidth: true
                        text: "Record MP4 (60 fps)"
                        enabled: !captureCoordinator.recording
                        onClicked: captureCoordinator.startRecording(1)
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
