pragma ComponentBehavior: Bound
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
            onPositionChanged: function(drag) {
                drag.acceptProposedAction()
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
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: "#94a3b8"
                    font.pixelSize: 11
                    text: "Drop Inbox • Temporary staging area: Click to copy path, or drag out to any app"
                }

                Button {
                    visible: fileShelfModel.count > 0
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
                    required property string thumbnailPath
                    required property string kind
                    width: shelfList.width
                    height: 48
                    radius: 10
                    color: rowHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    function toFileUrl(path) {
                        if (!path || path.length === 0) {
                            return ""
                        }
                        if (path.indexOf("://") !== -1) {
                            return path
                        }
                        return "file://" + path.split("/").map(encodeURIComponent).join("/")
                    }

                    HoverHandler { id: rowHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.fill: parent
                                spacing: 10

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    radius: 8
                                    clip: true
                                    color: thumbImage.visible
                                           ? Qt.rgba(0, 0, 0, 0.35)
                                           : (shelfItemDelegate.kind === "DIR"
                                              ? Qt.rgba(0.98, 0.75, 0.14, 0.16)
                                              : (shelfItemDelegate.kind === "TEXT"
                                                 ? Qt.rgba(0.65, 0.55, 0.98, 0.18)
                                                 : Qt.rgba(0.20, 0.83, 0.60, 0.14)))
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.12)

                                    Image {
                                        id: thumbImage
                                        anchors.fill: parent
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: 64
                                        sourceSize.height: 64
                                        source: shelfItemDelegate.toFileUrl(shelfItemDelegate.thumbnailPath)
                                        visible: shelfItemDelegate.thumbnailPath.length > 0
                                                 && status === Image.Ready
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        visible: !thumbImage.visible
                                        color: shelfItemDelegate.kind === "DIR"
                                               ? "#fbbf24"
                                               : (shelfItemDelegate.kind === "TEXT" ? "#c4b5fd" : "#34d399")
                                        font.pixelSize: 9
                                        font.bold: true
                                        text: shelfItemDelegate.kind
                                    }
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

        // Centered Onboarding Empty State (Drop Inbox)
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 400)
            visible: fileShelfModel.count === 0
            spacing: 10

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 52
                implicitHeight: 52
                radius: 26
                color: dropArea.containsDrag
                       ? Qt.rgba(0.22, 0.74, 0.97, 0.22)
                       : Qt.rgba(0.20, 0.83, 0.60, 0.12)
                border.width: 1
                border.color: dropArea.containsDrag
                              ? Qt.rgba(0.22, 0.74, 0.97, 0.75)
                              : Qt.rgba(0.20, 0.83, 0.60, 0.38)

                Canvas {
                    id: inboxIcon
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    property bool active: dropArea.containsDrag
                    onActiveChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = active ? "#38bdf8" : "#34d399"
                        ctx.lineWidth = 1.8
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"

                        // Tray + inward drop arrow
                        ctx.beginPath()
                        ctx.moveTo(4, 13.5)
                        ctx.lineTo(4, 18.5)
                        ctx.lineTo(20, 18.5)
                        ctx.lineTo(20, 13.5)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.moveTo(12, 4.5)
                        ctx.lineTo(12, 14)
                        ctx.moveTo(8, 10.5)
                        ctx.lineTo(12, 14.5)
                        ctx.lineTo(16, 10.5)
                        ctx.stroke()
                    }
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                color: dropArea.containsDrag ? "#7dd3fc" : "#e2e8f0"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                text: dropArea.containsDrag ? "Release to Stage" : "Drop Inbox"
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: dropArea.containsDrag ? "#bae6fd" : "#94a3b8"
                font.pixelSize: 12
                text: dropArea.containsDrag
                      ? "Release to stage files, URLs, or snippets onto your File Shelf."
                      : "Drop Inbox. Drag and drop files, images, or URLs here to stage them. Click an item to copy it, or drag it out to another app."
            }
        }
    }
}
