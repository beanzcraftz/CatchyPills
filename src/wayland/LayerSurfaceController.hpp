#pragma once

#include <QObject>
#include <QRect>
#include <QRegion>
#include <QSize>
#include <QString>

class QQuickWindow;
class QScreen;

namespace catchypills::wayland {

/**
 * Configures and manages a QtQuick window as a Wayland zwlr_layer_shell_v1
 * surface on KDE Plasma 6 (KWin), handling both the top-anchored Dynamic Island
 * (with dynamic QWindow::setMask click-through and ext_background_effect_v1 blur)
 * and the fullscreen 3840x1080 OmniShot region-selection overlay.
 */
class LayerSurfaceController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool clickThrough READ isClickThrough WRITE setClickThrough NOTIFY clickThroughChanged)
    Q_PROPERTY(bool dragActive READ isDragActive WRITE setDragActive NOTIFY dragActiveChanged)
    Q_PROPERTY(int surfaceX READ surfaceX NOTIFY positionChanged)
    Q_PROPERTY(int surfaceY READ surfaceY NOTIFY positionChanged)
    Q_PROPERTY(int pillX READ pillX NOTIFY positionChanged)
    Q_PROPERTY(int pillY READ pillY NOTIFY positionChanged)
    Q_PROPERTY(int pillCanvasX READ pillCanvasX NOTIFY positionChanged)
    Q_PROPERTY(int pillCanvasY READ pillCanvasY NOTIFY positionChanged)

public:
    explicit LayerSurfaceController(QQuickWindow *window = nullptr, QObject *parent = nullptr);
    void setWindow(QQuickWindow *window);

    /**
     * Binds LayerShellQt properties BEFORE the QWindow maps its wl_surface.
     * Anchors flush to the top-center bezel of the target 3840x1080 display.
     */
    void attachToLayerShell(QScreen *preferredScreen = nullptr);

    /**
     * Updates target monitor and fullscreen auto-hide layer policy without moving the surface.
     */
    Q_INVOKABLE void applyScreenAndLayer(const QString &monitorName, bool autoHideFullscreen);

    /**
     * Places the zwlr_layer_surface_v1 surface using AnchorTop | AnchorLeft and
     * QMargins(x, y, 0, 0) so the collapsed pill rests at exact screen coordinates (x, y).
     */
    Q_INVOKABLE void setAbsolutePosition(int x, int y);

    /**
     * Applies live Display & Position settings (target monitor, horizontal offset,
     * top margin, and fullscreen auto-hide layer policy) without recreating the surface.
     */
    Q_INVOKABLE void applyDisplayPreferences(const QString &monitorName,
                                             int horizontalOffset,
                                             int topMargin,
                                             bool autoHideFullscreen);

    /**
     * Binds LayerShellQt properties for the fullscreen CaptureOverlay across all
     * edges of the 3840x1080 display, covering even the bottom Plasma panel.
     */
    void attachAsFullscreenOverlay(QScreen *preferredScreen = nullptr);

    /**
     * During active screen recording, lowers the CaptureOverlay to LayerTop, releases
     * keyboard exclusivity, and constrains Wayland pointer input solely to toolbarRect.
     */
    Q_INVOKABLE void setOverlayRecordingPassThrough(const QRect &toolbarRect, int cornerRadius = 16);

    /**
     * Restores the fullscreen CaptureOverlay to LayerOverlay with exclusive keyboard
     * interactivity and full-surface input before displaying the region selector.
     */
    Q_INVOKABLE void restoreFullscreenOverlay();

    /**
     * Dynamically constrains pointer hit-testing to only the visible pill area
     * inside the fixed transparent canvas, or passes all clicks through.
     */
    Q_INVOKABLE void updateInputRegion(const QRect &pillRect, int cornerRadius = 18);

    Q_INVOKABLE void setClickThrough(bool enabled);
    bool isClickThrough() const noexcept { return m_clickThrough; }

    Q_INVOKABLE void setDragActive(bool active);
    bool isDragActive() const noexcept { return m_dragActive; }

    int surfaceX() const noexcept { return m_surfaceX; }
    int surfaceY() const noexcept { return m_surfaceY; }
    int pillX() const noexcept { return m_pillX; }
    int pillY() const noexcept { return m_pillY; }
    int pillCanvasX() const noexcept { return m_pillCanvasX; }
    int pillCanvasY() const noexcept { return m_pillCanvasY; }

    /**
     * Toggles Wayland keyboard interactivity between None (passive HUD) and
     * OnDemand (expanded Search / quick input without permanently stealing focus).
     */
    Q_INVOKABLE void setKeyboardInteractive(bool interactive);

    static constexpr QSize kDefaultCanvasSize{760, 460};
    static constexpr QSize kCollapsedPillSize{260, 36};

Q_SIGNALS:
    void clickThroughChanged(bool enabled);
    void dragActiveChanged(bool active);
    void positionChanged();

private:
    QScreen *findScreenByName(const QString &monitorName) const;
    QScreen *resolveUltrawideScreen(QScreen *preferredScreen) const;
    void applyBlurBehind(const QRegion &region);

    QQuickWindow *m_window{nullptr};
    QRect m_lastPillRect;
    int m_lastCornerRadius{18};
    bool m_clickThrough{false};
    bool m_dragActive{false};
    bool m_maskBypassed{false};
    int m_surfaceX{0};
    int m_surfaceY{0};
    int m_pillX{0};
    int m_pillY{0};
    int m_pillCanvasX{(kDefaultCanvasSize.width() - kCollapsedPillSize.width()) / 2};
    int m_pillCanvasY{0};
};

} // namespace catchypills::wayland
