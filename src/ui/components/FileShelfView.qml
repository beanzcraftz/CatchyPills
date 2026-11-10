import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * File Shelf drag-and-drop staging view (tab 1 of ExpandedDashboard).
 * Parses Wayland DropArea payloads (`drop.urls` / text snippets) and delegates
 * storage and retention expiry to the C++ FileShelfModel.
 */
Item {
    id: root

    readonly property bool containsDrag: dropArea.containsDrag

    signal dropCompleted()
    signal dragHoverChanged()

    function acceptDrop(drop) {
        if (!drop) {
            return false
        }

        if (drop.hasUrls && drop.urls && drop.urls.length > 0) {
            var parsedUrls = []
            for (var i = 0; i < drop.urls.length; ++i) {
                var urlStr = drop.urls[i].toString().trim()
                if (urlStr.length > 0) {
                    parsedUrls.push(urlStr)
                }
            }
            if (parsedUrls.length > 0) {
                fileShelfModel.addUrls(parsedUrls)
                drop.acceptProposedAction()
                root.dropCompleted()
                return true
            }
        }

        if (drop.hasText && drop.text.trim().length > 0) {
            var lines = drop.text.trim().split(/\r?\n/)
            var uriLines = []
            var allFileUris = lines.length > 0
            for (var j = 0; j < lines.length; ++j) {
                var line = lines[j].trim()
                if (line.indexOf("file://") === 0) {
                    uriLines.push(line)
                } else if (line.length > 0) {
                    allFileUris = false
                    break
                }
            }

            if (allFileUris && uriLines.length > 0) {
                fileShelfModel.addUrls(uriLines)
            } else {
                fileShelfModel.addTextSnippet(drop.text)
            }
            drop.acceptProposedAction()
            root.dropCompleted()
            return true
        }

        return false
    }

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
                root.dragHoverChanged()
            }
            onExited: root.dragHoverChanged()
            onDropped: function(drop) {
                root.acceptDrop(drop)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                visible: fileShelfModel.count > 0
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    color: "#94a3b8"
                    font.pixelSize: 11
                    text: fileShelfModel.count + (fileShelfModel.count === 1 ? " item staged (click to copy)" : " items staged (click to copy)")
                }

                Button {
                    text: "Clear All"
                    implicitHeight: 24
                    font.pixelSize: 11
                    onClicked: fileShelfModel.clear()
                }
            }

            ListView {
                id: shelfList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: fileShelfModel

                delegate: Rectangle {
                    id: shelfItemDelegate
                    required property int index
                    required property string name
                    required property string uri
                    required property string kind
                    width: shelfList.width
                    height: 40
                    radius: 10
                    color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    HoverHandler { id: rowHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Label {
                                    color: shelfItemDelegate.kind === "DIR"
                                           ? "#fbbf24"
                                           : (shelfItemDelegate.kind === "TEXT" ? "#c4b5fd" : "#34d399")
                                    font.pixelSize: 10
                                    font.bold: true
                                    text: shelfItemDelegate.kind
                                }

                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                    color: "#e2e8f0"
                                    font.pixelSize: 12
                                    text: shelfItemDelegate.name
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fileShelfModel.copyItem(shelfItemDelegate.index)
                            }
                        }

                        Button {
                            text: "×"
                            implicitWidth: 26
                            implicitHeight: 26
                            onClicked: fileShelfModel.removeItem(shelfItemDelegate.index)
                        }
                    }
                }
            }
        }

        Label {
            anchors.centerIn: parent
            visible: fileShelfModel.count === 0
            color: dropArea.containsDrag ? "#7dd3fc" : "#64748b"
            font.pixelSize: 12
            text: dropArea.containsDrag
                  ? "Release to stage onto File Shelf"
                  : "Drag & drop files, URLs, or snippets here to stage on shelf"
        }
    }
}
