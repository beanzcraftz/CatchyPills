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

public:
    explicit LayerSurfaceController(QQuickWindow *window, QObject *parent = nullptr);

    /**
     * Binds LayerShellQt properties BEFORE the QWindow maps its wl_surface.
     * Anchors flush to the top-center bezel of the target 3840x1080 display.
     */
    void attachToLayerShell(QScreen *preferredScreen = nullptr);

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
     * Dynamically constrains pointer hit-testing to only the visible pill area
     * inside the fixed transparent canvas, or passes all clicks through.
     */
    Q_INVOKABLE void updateInputRegion(const QRect &pillRect, int cornerRadius = 18);

    Q_INVOKABLE void setClickThrough(bool enabled);
    bool isClickThrough() const noexcept { return m_clickThrough; }

    /**
     * Toggles Wayland keyboard interactivity between None (passive HUD) and
     * OnDemand (expanded Search / quick input without permanently stealing focus).
     */
    Q_INVOKABLE void setKeyboardInteractive(bool interactive);

    static constexpr QSize kDefaultCanvasSize{760, 460};

Q_SIGNALS:
    void clickThroughChanged(bool enabled);

private:
    QScreen *findScreenByName(const QString &monitorName) const;
    QScreen *resolveUltrawideScreen(QScreen *preferredScreen) const;
    void applyBlurBehind(const QRegion &region);

    QQuickWindow *m_window{nullptr};
    QRect m_lastPillRect;
    int m_lastCornerRadius{18};
    bool m_clickThrough{false};
};

} // namespace catchypills::wayland
