import QtQuick

/**
 * Vector + redaction annotation layer embedded over the active crop region in
 * CaptureOverlay.qml. All annotation coordinates are stored relative to the
 * crop origin (0, 0) in logical pixels and forwarded to CaptureCoordinator so
 * C++ QPainter renders them at native device resolution onto ScreenShot2 pixels.
 */
Item {
    id: root

    // "none" | "arrow" | "rect" | "blur"
    property string activeTool: "none"
    property color strokeColor: "#ef4444"
    property real strokeWidth: 3
    property int pixelBlockSize: 10
    property var annotations: []
    property var draftAnnotation: null

    readonly property bool drawingEnabled: activeTool !== "none"

    function undo() {
        if (annotations.length === 0) {
            return
        }
        var next = annotations.slice(0, annotations.length - 1)
        annotations = next
        canvas.requestPaint()
    }

    function clear() {
        annotations = []
        draftAnnotation = null
        canvas.requestPaint()
    }

    function exportAnnotations() {
        return annotations.slice()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var items = root.annotations.slice()
            if (root.draftAnnotation) {
                items.push(root.draftAnnotation)
            }

            for (var i = 0; i < items.length; ++i) {
                var item = items[i]
                drawItem(ctx, item)
            }
        }

        function drawItem(ctx, item) {
            ctx.save()
            ctx.strokeStyle = item.color
            ctx.fillStyle = item.color
            ctx.lineWidth = item.strokeWidth
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            if (item.tool === "rect") {
                var rx = Math.min(item.x1, item.x2)
                var ry = Math.min(item.y1, item.y2)
                var rw = Math.abs(item.x2 - item.x1)
                var rh = Math.abs(item.y2 - item.y1)
                ctx.strokeRect(rx, ry, rw, rh)
            } else if (item.tool === "arrow") {
                var dx = item.x2 - item.x1
                var dy = item.y2 - item.y1
                var len = Math.hypot(dx, dy)
                if (len >= 2) {
                    var angle = Math.atan2(dy, dx)
                    var headLen = Math.max(12, item.strokeWidth * 4)
                    var shaftX = item.x2 - Math.cos(angle) * (headLen * 0.72)
                    var shaftY = item.y2 - Math.sin(angle) * (headLen * 0.72)

                    ctx.beginPath()
                    ctx.moveTo(item.x1, item.y1)
                    ctx.lineTo(shaftX, shaftY)
                    ctx.stroke()

                    ctx.beginPath()
                    ctx.moveTo(item.x2, item.y2)
                    ctx.lineTo(
                        item.x2 - headLen * Math.cos(angle - Math.PI / 6),
                        item.y2 - headLen * Math.sin(angle - Math.PI / 6)
                    )
                    ctx.lineTo(
                        item.x2 - headLen * Math.cos(angle + Math.PI / 6),
                        item.y2 - headLen * Math.sin(angle + Math.PI / 6)
                    )
                    ctx.closePath()
                    ctx.fill()
                }
            } else if (item.tool === "blur") {
                // Live mosaic redaction preview; final capture applies true
                // downscale/upscale pixelation to the native ScreenShot2 QImage.
                var bx = Math.min(item.x1, item.x2)
                var by = Math.min(item.y1, item.y2)
                var bw = Math.abs(item.x2 - item.x1)
                var bh = Math.abs(item.y2 - item.y1)
                if (bw > 2 && bh > 2) {
                    ctx.save()
                    ctx.beginPath()
                    ctx.rect(bx, by, bw, bh)
                    ctx.clip()

                    var step = root.pixelBlockSize
                    for (var py = by; py < by + bh; py += step) {
                        for (var px = bx; px < bx + bw; px += step) {
                            var alt = ((Math.floor(px / step) + Math.floor(py / step)) % 2) === 0
                            ctx.fillStyle = alt ? "rgba(15, 23, 42, 0.72)" : "rgba(51, 65, 85, 0.72)"
                            ctx.fillRect(px, py, step, step)
                        }
                    }
                    ctx.strokeStyle = "rgba(56, 189, 248, 0.85)"
                    ctx.lineWidth = 1.5
                    ctx.strokeRect(bx, by, bw, bh)
                    ctx.restore()
                }
            }
            ctx.restore()
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.drawingEnabled
        cursorShape: enabled ? Qt.CrossCursor : Qt.ArrowCursor

        onPressed: function(mouse) {
            root.draftAnnotation = {
                tool: root.activeTool,
                x1: mouse.x,
                y1: mouse.y,
                x2: mouse.x,
                y2: mouse.y,
                color: root.strokeColor.toString(),
                strokeWidth: root.strokeWidth
            }
            canvas.requestPaint()
        }

        onPositionChanged: function(mouse) {
            if (!root.draftAnnotation) {
                return
            }
            root.draftAnnotation = {
                tool: root.draftAnnotation.tool,
                x1: root.draftAnnotation.x1,
                y1: root.draftAnnotation.y1,
                x2: mouse.x,
                y2: mouse.y,
                color: root.draftAnnotation.color,
                strokeWidth: root.draftAnnotation.strokeWidth
            }
            canvas.requestPaint()
        }

        onReleased: {
            if (!root.draftAnnotation) {
                return
            }
            var dx = Math.abs(root.draftAnnotation.x2 - root.draftAnnotation.x1)
            var dy = Math.abs(root.draftAnnotation.y2 - root.draftAnnotation.y1)
            if (dx > 3 || dy > 3) {
                var next = root.annotations.slice()
                next.push(root.draftAnnotation)
                root.annotations = next
            }
            root.draftAnnotation = null
            canvas.requestPaint()
        }
    }
}
