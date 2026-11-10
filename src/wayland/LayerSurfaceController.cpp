#include "LayerSurfaceController.hpp"

#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QColor>
#include <QGuiApplication>
#include <QPainterPath>
#include <QQuickWindow>
#include <QScreen>

#include <algorithm>

namespace catchypills::wayland {

LayerSurfaceController::LayerSurfaceController(QQuickWindow *window, QObject *parent)
    : QObject(parent)
    , m_window(window)
{
}

void LayerSurfaceController::setWindow(QQuickWindow *window)
{
    m_window = window;
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

    // LayerTop sits above normal windows & panels while allowing fullscreen apps/games
    // to render above the island cleanly on KWin (auto-hide on fullscreen).
    layerWindow->setLayer(LayerShellQt::Window::LayerTop);

    // Anchor exclusively to Top | Left so absolute QMargins(x, y, 0, 0) offsets
    // position the zwlr_layer_surface_v1 anywhere across the target display.
    const auto anchors = LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)
                         | LayerShellQt::Window::AnchorLeft;
    layerWindow->setAnchors(anchors);

    // ExclusiveZone = 0 does not shrink maximized windows' usable work area.
    layerWindow->setExclusiveZone(0);
    layerWindow->setDesiredSize(kDefaultCanvasSize);

    // Never steal keyboard focus on startup or during ambient HUD updates.
    layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    layerWindow->setActivateOnShow(false);
    layerWindow->setScope(QStringLiteral("catchypills-island"));

    const int screenW = targetScreen ? targetScreen->geometry().width() : 3840;
    const int centerPillX = std::max(0, (screenW - kCollapsedPillSize.width()) / 2);
    setAbsolutePosition(centerPillX, 0);
    if (targetScreen) {
        Q_EMIT currentScreenChanged(targetScreen->name());
    }
}

void LayerSurfaceController::applyScreenAndLayer(
    const QString &monitorName,
    bool autoHideFullscreen)
{
    if (!m_window) {
        return;
    }

    m_autoHideFullscreen = autoHideFullscreen;

    QScreen *targetScreen = findScreenByName(monitorName);
    if (!targetScreen) {
        targetScreen = resolveUltrawideScreen(nullptr);
    }

    auto *layerWindow = LayerShellQt::Window::get(m_window);
    if (!layerWindow) {
        return;
    }

    // In KWin Wayland, fullscreen windows sit above LayerTop and below LayerOverlay.
    layerWindow->setLayer(autoHideFullscreen ? LayerShellQt::Window::LayerTop
                                             : LayerShellQt::Window::LayerOverlay);

    if (targetScreen && m_window->screen() != targetScreen) {
        reanchorToScreen(targetScreen, m_pillX, m_pillY);
    }
}

QString LayerSurfaceController::currentScreenName() const
{
    QScreen *screen = m_window ? m_window->screen() : nullptr;
    if (!screen) {
        screen = resolveUltrawideScreen(nullptr);
    }
    return screen ? screen->name() : QString();
}

bool LayerSurfaceController::moveToScreenUnderCursor(int globalX, int globalY, int anchorX, int anchorY)
{
    if (!m_window) {
        return false;
    }

    QScreen *currentScreen = m_window->screen();
    if (!currentScreen) {
        currentScreen = resolveUltrawideScreen(nullptr);
    }

    QScreen *targetScreen = findAdjacentScreen(QPoint(globalX, globalY), currentScreen);
    if (!targetScreen || targetScreen == currentScreen) {
        return false;
    }

    const QRect targetGeo = targetScreen->geometry();
    const int localPillX = globalX - targetGeo.x() - anchorX;
    const int localPillY = globalY - targetGeo.y() - anchorY;

    reanchorToScreen(targetScreen, localPillX, localPillY);
    return true;
}

void LayerSurfaceController::dragBy(int dx, int dy, int anchorX, int anchorY)
{
    if (!m_window) {
        return;
    }

    QScreen *currentScreen = m_window->screen();
    if (!currentScreen) {
        currentScreen = resolveUltrawideScreen(nullptr);
    }

    const QRect curGeo = currentScreen ? currentScreen->geometry() : QRect(0, 0, 3840, 1080);
    const int candidateX = m_pillX + dx;
    const int candidateY = m_pillY + dy;

    const int globalCursorX = curGeo.x() + candidateX + anchorX;
    const int globalCursorY = curGeo.y() + candidateY + anchorY;

    if (!curGeo.contains(QPoint(globalCursorX, globalCursorY))) {
        if (moveToScreenUnderCursor(globalCursorX, globalCursorY, anchorX, anchorY)) {
            return;
        }
    }

    setAbsolutePosition(candidateX, candidateY);
}

void LayerSurfaceController::reanchorToScreen(QScreen *targetScreen, int localPillX, int localPillY)
{
    if (!m_window || !targetScreen) {
        return;
    }

    auto *layerWindow = LayerShellQt::Window::get(m_window);
    if (!layerWindow) {
        return;
    }

    const bool wasVisible = m_window->isVisible();
    if (wasVisible) {
        // zwlr_layer_shell_v1 binds wl_output only on layer surface creation, so
        // recreating the platform surface moves the island cleanly to targetScreen.
        m_window->hide();
    }

    m_window->setScreen(targetScreen);
    layerWindow->setWantsToBeOnActiveScreen(false);
    layerWindow->setScreen(targetScreen);
    layerWindow->setLayer(m_autoHideFullscreen ? LayerShellQt::Window::LayerTop
                                               : LayerShellQt::Window::LayerOverlay);
    layerWindow->setExclusiveZone(0);
    layerWindow->setDesiredSize(kDefaultCanvasSize);
    layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    layerWindow->setActivateOnShow(false);
    layerWindow->setScope(QStringLiteral("catchypills-island"));

    setAbsolutePosition(localPillX, localPillY);

    if (wasVisible) {
        m_window->show();
    }

    Q_EMIT currentScreenChanged(targetScreen->name());
}

void LayerSurfaceController::setAbsolutePosition(int x, int y)
{
    if (!m_window) {
        return;
    }

    auto *layerWindow = LayerShellQt::Window::get(m_window);
    if (!layerWindow) {
        return;
    }

    QScreen *targetScreen = m_window->screen();
    if (!targetScreen) {
        targetScreen = resolveUltrawideScreen(nullptr);
    }

    const int screenW = targetScreen ? targetScreen->geometry().width() : 3840;
    const int screenH = targetScreen ? targetScreen->geometry().height() : 1080;

    const int maxPillX = std::max(0, screenW - kCollapsedPillSize.width());
    const int maxPillY = std::max(0, screenH - kCollapsedPillSize.height());
    const int clampedPillX = std::clamp(x, 0, maxPillX);
    const int clampedPillY = std::clamp(y, 0, maxPillY);

    const int centerOffsetX = (kDefaultCanvasSize.width() - kCollapsedPillSize.width()) / 2;
    const int maxSurfX = std::max(0, screenW - kDefaultCanvasSize.width());
    const int maxSurfY = std::max(0, screenH - kDefaultCanvasSize.height());

    const int newSurfX = std::clamp(clampedPillX - centerOffsetX, 0, maxSurfX);
    const int newSurfY = std::clamp(clampedPillY, 0, maxSurfY);
    const int newCanvasX = std::clamp(
        clampedPillX - newSurfX, 0, kDefaultCanvasSize.width() - kCollapsedPillSize.width());
    const int newCanvasY = std::clamp(
        clampedPillY - newSurfY, 0, kDefaultCanvasSize.height() - kCollapsedPillSize.height());

    const auto anchors = LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop)
                         | LayerShellQt::Window::AnchorLeft;
    if (layerWindow->anchors() != anchors) {
        layerWindow->setAnchors(anchors);
    }

    const QMargins targetMargins(newSurfX, newSurfY, 0, 0);
    const bool surfaceMoved = (m_surfaceX != newSurfX || m_surfaceY != newSurfY);
    const bool anyChanged = surfaceMoved
                            || m_pillX != clampedPillX
                            || m_pillY != clampedPillY
                            || m_pillCanvasX != newCanvasX
                            || m_pillCanvasY != newCanvasY;

    m_pillX = clampedPillX;
    m_pillY = clampedPillY;
    m_pillCanvasX = newCanvasX;
    m_pillCanvasY = newCanvasY;

    if (surfaceMoved || layerWindow->margins() != targetMargins) {
        m_surfaceX = newSurfX;
        m_surfaceY = newSurfY;
        layerWindow->setMargins(targetMargins);
        if (m_window->isVisible()) {
            m_window->requestUpdate();
        }
    }

    if (anyChanged) {
        Q_EMIT positionChanged();
    }

    if (m_window->isVisible() && !m_clickThrough && m_lastPillRect.isValid()) {
        updateInputRegion(m_lastPillRect, m_lastCornerRadius);
    }
}

void LayerSurfaceController::applyDisplayPreferences(
    const QString &monitorName,
    int horizontalOffset,
    int topMargin,
    bool autoHideFullscreen)
{
    applyScreenAndLayer(monitorName, autoHideFullscreen);

    if (!m_window) {
        return;
    }

    QScreen *targetScreen = m_window->screen();
    if (!targetScreen) {
        targetScreen = resolveUltrawideScreen(nullptr);
    }

    const int screenW = targetScreen ? targetScreen->geometry().width() : 3840;
    const int centerPillX = (screenW - kCollapsedPillSize.width()) / 2;
    const int clampedTop = std::clamp(topMargin, 0, 64);
    setAbsolutePosition(centerPillX + horizontalOffset, clampedTop);
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

void LayerSurfaceController::setOverlayRecordingPassThrough(const QRect &toolbarRect, int cornerRadius)
{
    if (!m_window) {
        return;
    }

    if (auto *layerWindow = LayerShellQt::Window::get(m_window)) {
        layerWindow->setLayer(LayerShellQt::Window::LayerTop);
        layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        layerWindow->setActivateOnShow(false);
    }

    m_clickThrough = false;
    m_maskBypassed = false;
    applyBlurBehind(QRegion());

    if (toolbarRect.isValid() && !toolbarRect.isEmpty()) {
        QPainterPath path;
        path.addRoundedRect(QRectF(toolbarRect), cornerRadius, cornerRadius);
        m_window->setFlag(Qt::WindowTransparentForInput, false);
        m_window->setMask(QRegion(path.toFillPolygon().toPolygon()));
    } else {
        m_window->setFlag(Qt::WindowTransparentForInput, true);
    }

    if (m_window->isVisible()) {
        m_window->requestUpdate();
    }
}

void LayerSurfaceController::restoreFullscreenOverlay()
{
    if (!m_window) {
        return;
    }

    if (auto *layerWindow = LayerShellQt::Window::get(m_window)) {
        layerWindow->setLayer(LayerShellQt::Window::LayerOverlay);
        layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
        layerWindow->setActivateOnShow(true);
    }

    m_clickThrough = false;
    m_maskBypassed = false;
    applyBlurBehind(QRegion());
    m_window->setFlag(Qt::WindowTransparentForInput, false);
    m_window->setMask(QRegion());

    if (m_window->isVisible()) {
        m_window->requestUpdate();
    }
}

void LayerSurfaceController::setTemporaryDialogBehind(bool behind)
{
    if (!m_window) {
        return;
    }

    if (auto *layerWindow = LayerShellQt::Window::get(m_window)) {
        if (behind) {
            layerWindow->setLayer(LayerShellQt::Window::LayerBottom);
            layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
            layerWindow->setActivateOnShow(false);
        } else {
            layerWindow->setLayer(m_autoHideFullscreen
                                      ? LayerShellQt::Window::LayerTop
                                      : LayerShellQt::Window::LayerOverlay);
            layerWindow->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        }
    }

    if (behind) {
        m_window->setFlag(Qt::WindowTransparentForInput, true);
    } else {
        m_window->setFlag(Qt::WindowTransparentForInput, m_clickThrough);
        updateInputRegion(m_lastPillRect, m_lastCornerRadius);
    }

    if (m_window->isVisible()) {
        m_window->requestUpdate();
    }
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

    if (m_dragActive) {
        // Bypass tight QWindow::setMask() so the entire 760x460 wl_surface
        // accepts Wayland pointer and drag events during the animation, and
        // avoid re-issuing setMask() on every animation frame.
        if (!m_maskBypassed) {
            m_maskBypassed = true;
            m_window->setFlag(Qt::WindowTransparentForInput, false);
            m_window->setMask(QRegion());
        }

        if (pillRect.isValid() && !pillRect.isEmpty()) {
            QPainterPath path;
            path.addRoundedRect(QRectF(pillRect), cornerRadius, cornerRadius);
            applyBlurBehind(QRegion(path.toFillPolygon().toPolygon()));
        }
        return;
    }

    m_maskBypassed = false;

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

void LayerSurfaceController::setDragActive(bool active)
{
    if (m_dragActive == active) {
        return;
    }

    m_dragActive = active;
    if (!m_dragActive) {
        m_maskBypassed = false;
    }
    Q_EMIT dragActiveChanged(m_dragActive);

    if (!m_window || m_clickThrough) {
        return;
    }

    const QRect targetRect = (m_lastPillRect.isValid() && !m_lastPillRect.isEmpty())
        ? m_lastPillRect
        : QRect(m_pillCanvasX, m_pillCanvasY,
                kCollapsedPillSize.width(), kCollapsedPillSize.height());
    updateInputRegion(targetRect, m_lastCornerRadius);

    if (m_window->isVisible()) {
        m_window->requestUpdate();
    }
}

void LayerSurfaceController::setClickThrough(bool enabled)
{
    if (!m_window || m_clickThrough == enabled) {
        return;
    }

    m_clickThrough = enabled;
    m_maskBypassed = false;

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

QScreen *LayerSurfaceController::findScreenByName(const QString &monitorName) const
{
    if (monitorName.isEmpty()) {
        return nullptr;
    }
    for (QScreen *screen : QGuiApplication::screens()) {
        if (screen && screen->name() == monitorName) {
            return screen;
        }
    }
    return nullptr;
}

QScreen *LayerSurfaceController::findAdjacentScreen(
    const QPoint &globalPos,
    QScreen *currentScreen) const
{
    for (QScreen *screen : QGuiApplication::screens()) {
        if (screen && screen->geometry().contains(globalPos)) {
            return screen;
        }
    }

    // Handle edge-overhang crossings between monitors with mismatched heights/widths
    // (e.g., dragging near y=18 from a taller 1440p monitor into an offset 1080p monitor).
    if (!currentScreen) {
        return nullptr;
    }
    const QRect curGeo = currentScreen->geometry();
    for (QScreen *screen : QGuiApplication::screens()) {
        if (!screen || screen == currentScreen) {
            continue;
        }
        const QRect g = screen->geometry();
        const bool crossedX = (globalPos.x() < curGeo.left() || globalPos.x() > curGeo.right())
                              && globalPos.x() >= g.left() && globalPos.x() <= g.right();
        const bool crossedY = (globalPos.y() < curGeo.top() || globalPos.y() > curGeo.bottom())
                              && globalPos.y() >= g.top() && globalPos.y() <= g.bottom();
        if (crossedX || crossedY) {
            return screen;
        }
    }

    return nullptr;
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
