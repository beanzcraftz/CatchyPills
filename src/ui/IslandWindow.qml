import QtQuick

Window {
    id: root
    width: 760
    height: 460
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint

    // Sync initial input mask once LayerSurfaceController maps the window.
    onVisibleChanged: {
        if (visible) {
            pillPlaceholder.syncMask()
        }
    }

    // Placeholder collapsed pill aligned flush to top-center of the transparent canvas.
    Rectangle {
        id: pillPlaceholder
        width: 260
        height: 36
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        bottomLeftRadius: 18
        bottomRightRadius: 18
        topLeftRadius: 0
        topRightRadius: 0
        color: Qt.rgba(0.06, 0.07, 0.09, 0.86)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        onXChanged: syncMask()
        onWidthChanged: syncMask()
        onHeightChanged: syncMask()

        function syncMask() {
            if (typeof layerController !== "undefined" && layerController !== null) {
                layerController.updateInputRegion(
                    Qt.rect(Math.round(x), Math.round(y), Math.round(width), Math.round(height)),
                    18
                )
            }
        }
    }
}
