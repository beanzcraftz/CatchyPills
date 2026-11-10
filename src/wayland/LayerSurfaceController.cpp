#include "LayerSurfaceController.hpp"

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QColor>
#include <QGuiApplication>
#include <QPainterPath>
#include <QQuickWindow>
#include <QScreen>

namespace catchypills::wayland {

LayerSurfaceController::LayerSurfaceController(QQuickWindow *window, QObject *parent)
    : QObject(parent)
    , m_window(window)
{
}

void LayerSurfaceController::attachToLayerShell(QScreen *preferredScreen)
{
    if (!m_window) {
        return;
    }

    // Ensure alpha-transparent backing store before the Wayland surface is created.
    m_window->setColor(Qt::transparent);
    m_window->setFlag(Qt::FramelessWindowHint, true);

    // Fixed-canvas sizing avoids zwlr_layer_surface_v1 configure/ack roundtrips
    // on every spring animation frame while keeping shadows unclipped.
    m_window->resize(kDefaultCanvasSize);

    QScreen *targetScreen = resolveUltrawideScreen(preferredScreen);
    if (targetScreen) {
        m_window->setScreen(targetScreen);
    }

    // LayerShellQt::Window::get() MUST be called before m_window->show() so Qt
    // creates a zwlr_layer_surface_v1 role instead of a regular xdg_toplevel.
    auto *layerWindow = LayerShellQt::Window::get(m_window);
    if (!layerWindow) {
        return;
    }

    if (targetScreen) {
        layerWindow->setWantsToBeOnActiveScreen(false);
        layerWindow->setScreen(targetScreen);
    }

    // LayerOverlay keeps the Dynamic Island above normal windows and docks.
    layerWindow->setLayer(LayerShellQt::Window::LayerOverlay);

    // Anchor ONLY to AnchorTop so KWin centers the surface horizontally on the
    // 3840px wide monitor instead of stretching it across AnchorLeft | AnchorRight.
    layerWindow->setAnchors(LayerShellQt::Window::AnchorTop);

    // ExclusiveZone = 0 does not shrink maximized windows' usable work area.
    // With Plasma's panel positioned at the bottom of the 3840x1080 display,
    // the top edge is unobstructed and zero margins pin the island flush to y=0.
    layerWindow->setExclusiveZone(0);
    layerWindow->setMargins(QMargins(0, 0, 0, 0));
    layerWindow->setDesiredSize(kDefaultCanvasSize);

    // Never steal keyboard focus on startup or during ambient HUD updates.
    layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    layerWindow->setActivateOnShow(false);
    layerWindow->setScope(QStringLiteral("catchypills-island"));
}

void LayerSurfaceController::attachAsFullscreenOverlay(QScreen *preferredScreen)
{
    if (!m_window) {
        return;
    }

    m_window->setColor(Qt::transparent);
    m_window->setFlag(Qt::FramelessWindowHint, true);

    QScreen *targetScreen = resolveUltrawideScreen(preferredScreen);
    if (targetScreen) {
        m_window->setScreen(targetScreen);
        m_window->resize(targetScreen->geometry().size());
    }

    auto *layerWindow = LayerShellQt::Window::get(m_window);
    if (!layerWindow) {
        return;
    }

    if (targetScreen) {
        layerWindow->setWantsToBeOnActiveScreen(false);
        layerWindow->setScreen(targetScreen);
        layerWindow->setDesiredSize(targetScreen->geometry().size());
    }

    // Anchor all four edges with exclusiveZone = -1 so the region-selection
    // canvas spans the full 3840x1080 surface, covering the bottom Plasma panel.
    layerWindow->setLayer(LayerShellQt::Window::LayerOverlay);
    const auto allAnchors = LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)
                            | LayerShellQt::Window::AnchorBottom
                            | LayerShellQt::Window::AnchorLeft
                            | LayerShellQt::Window::AnchorRight;
    layerWindow->setAnchors(allAnchors);
    layerWindow->setExclusiveZone(-1);
    layerWindow->setMargins(QMargins(0, 0, 0, 0));
    layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    layerWindow->setActivateOnShow(true);
    layerWindow->setScope(QStringLiteral("catchypills-capture-overlay"));
}

void LayerSurfaceController::updateInputRegion(const QRect &pillRect, int cornerRadius)
{
    if (!m_window) {
        return;
    }

    m_lastPillRect = pillRect;
    m_lastCornerRadius = cornerRadius;

    if (m_clickThrough) {
        return;
    }

    if (!pillRect.isValid() || pillRect.isEmpty()) {
        setClickThrough(true);
        return;
    }

    // Build a crisp rounded QRegion matching ONLY the active pill bounds.
    // Every transparent pixel outside this region passes pointer events
    // directly through to underlying windows on KWin.
    QPainterPath path;
    path.addRoundedRect(QRectF(pillRect), cornerRadius, cornerRadius);
    const QRegion maskRegion(path.toFillPolygon().toPolygon());

    m_window->setFlag(Qt::WindowTransparentForInput, false);
    m_window->setMask(maskRegion);

    applyBlurBehind(maskRegion);
}

void LayerSurfaceController::setClickThrough(bool enabled)
{
    if (!m_window || m_clickThrough == enabled) {
        return;
    }

    m_clickThrough = enabled;

    if (enabled) {
        // Wayland quirk: passing an empty QRegion() to QWindow::setMask() causes
        // Qt's Wayland QPA to pass `nullptr` to wl_surface.set_input_region,
        // which makes the ENTIRE surface intercept clicks. Setting
        // Qt::WindowTransparentForInput tells Qt Wayland to send a non-null empty
        // wl_region instead so 100% of clicks pass through.
        m_window->setFlag(Qt::WindowTransparentForInput, true);
        applyBlurBehind(QRegion());
    } else {
        m_window->setFlag(Qt::WindowTransparentForInput, false);
        if (m_lastPillRect.isValid() && !m_lastPillRect.isEmpty()) {
            updateInputRegion(m_lastPillRect, m_lastCornerRadius);
        }
    }

    Q_EMIT clickThroughChanged(m_clickThrough);
}

void LayerSurfaceController::setKeyboardInteractive(bool interactive)
{
    if (!m_window) {
        return;
    }

    if (auto *layerWindow = LayerShellQt::Window::get(m_window)) {
        layerWindow->setKeyboardInteractivity(
            interactive ? LayerShellQt::Window::KeyboardInteractivityOnDemand
                        : LayerShellQt::Window::KeyboardInteractivityNone);
    }
}

QScreen *LayerSurfaceController::resolveUltrawideScreen(QScreen *preferredScreen) const
{
    if (preferredScreen) {
        return preferredScreen;
    }

    // Prefer the 32:9 ultrawide (3840x1080) or widest connected display.
    QScreen *widest = QGuiApplication::primaryScreen();
    int maxWidth = widest ? widest->geometry().width() : 0;

    for (QScreen *screen : QGuiApplication::screens()) {
        const QSize geo = screen->geometry().size();
        if (geo.width() == 3840 && geo.height() == 1080) {
            return screen;
        }
        if (geo.width() > maxWidth) {
            maxWidth = geo.width();
            widest = screen;
        }
    }

    return widest;
}

void LayerSurfaceController::applyBlurBehind(const QRegion &region)
{
    if (!m_window) {
        return;
    }

    // On KDE Plasma 6.7+ / 6.8, KWindowEffects bridges the standardized Wayland
    // ext_background_effect_manager_v1 protocol (replacing org_kde_kwin_blur_manager).
    // Passing enable=false when region is empty avoids KWindowEffects treating an
    // empty QRegion as "blur the entire transparent canvas".
    const bool enable = !region.isEmpty();
    KWindowEffects::enableBlurBehind(m_window, enable, region);
}

} // namespace catchypills::wayland
