#include "Application.hpp"

#include "core/DaemonClient.hpp"
#include "modules/capture/CaptureCoordinator.hpp"
#include "wayland/LayerSurfaceController.hpp"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

namespace catchypills::app {

Application::Application(QObject *parent)
    : QObject(parent)
{
}

bool Application::initialize()
{
    m_imageProvider = new capture::CaptureImageProvider();
    m_daemonClient = new core::DaemonClient(this);
    m_captureCoordinator = new capture::CaptureCoordinator(m_imageProvider, this);
    m_engine = new QQmlApplicationEngine(this);

    m_engine->addImageProvider(QStringLiteral("capture"), m_imageProvider);
    m_engine->rootContext()->setContextProperty(QStringLiteral("appController"), this);
    m_engine->rootContext()->setContextProperty(QStringLiteral("daemonClient"), m_daemonClient);
    m_engine->rootContext()->setContextProperty(QStringLiteral("captureCoordinator"), m_captureCoordinator);

    connect(m_engine,
            &QQmlApplicationEngine::objectCreationFailed,
            this,
            []() { QCoreApplication::exit(-1); },
            Qt::QueuedConnection);

    // Non-blocking D-Bus watcher: recovers seamlessly if systemd restarts catchypillsd.
    setupDaemonWatcher();

    // 1. Load primary top-anchored Dynamic Island window.
    m_engine->loadFromModule("CatchyPills", "IslandWindow");
    if (m_engine->rootObjects().isEmpty()) {
        return false;
    }

    auto *islandWindow = qobject_cast<QQuickWindow *>(m_engine->rootObjects().constFirst());
    if (!islandWindow) {
        return false;
    }

    m_islandLayer = new wayland::LayerSurfaceController(islandWindow, islandWindow);
    m_engine->rootContext()->setContextProperty(QStringLiteral("layerController"), m_islandLayer);

    // 2. Preload fullscreen 3840x1080 CaptureOverlay on LayerOverlay.
    m_engine->loadFromModule("CatchyPills", "CaptureOverlay");
    if (m_engine->rootObjects().size() >= 2) {
        if (auto *overlayWindow = qobject_cast<QQuickWindow *>(m_engine->rootObjects().at(1))) {
            m_overlayLayer = new wayland::LayerSurfaceController(overlayWindow, overlayWindow);
            m_overlayLayer->attachAsFullscreenOverlay();
            connect(m_captureCoordinator,
                    &capture::CaptureCoordinator::regionOverlayRequested,
                    overlayWindow,
                    [overlayWindow]() {
                        overlayWindow->show();
                        overlayWindow->raise();
                        overlayWindow->requestActivate();
                    });
        }
    }

    // Bind zwlr_layer_shell_v1 before mapping the Wayland island surface.
    m_islandLayer->attachToLayerShell();
    islandWindow->show();

    probeDaemonAsync();
    return true;
}

QString Application::daemonStatusText() const
{
    return m_daemonOnline
        ? QStringLiteral("Daemon connected")
        : QStringLiteral("Daemon offline — reconnecting...");
}

void Application::setupDaemonWatcher()
{
    m_daemonWatcher = new QDBusServiceWatcher(
        QString::fromLatin1(kDaemonService),
        QDBusConnection::sessionBus(),
        QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration,
        this);

    connect(m_daemonWatcher, &QDBusServiceWatcher::serviceRegistered,
            this, &Application::onDaemonRegistered);
    connect(m_daemonWatcher, &QDBusServiceWatcher::serviceUnregistered,
            this, &Application::onDaemonUnregistered);

    // Periodic non-blocking Ping fallback with exponential backoff (3s -> 15s)
    // in case the daemon started or recovered without an active registration event.
    m_reconnectTimer = new QTimer(this);
    m_reconnectTimer->setSingleShot(true);
    connect(m_reconnectTimer, &QTimer::timeout, this, &Application::probeDaemonAsync);
}

void Application::onDaemonRegistered(const QString &serviceName)
{
    Q_UNUSED(serviceName)
    m_probeIntervalMs = 3000;
    if (m_reconnectTimer) {
        m_reconnectTimer->stop();
    }
    setDaemonOnline(true);
    if (m_daemonClient) {
        m_daemonClient->refreshClips();
    }
}

void Application::onDaemonUnregistered(const QString &serviceName)
{
    Q_UNUSED(serviceName)
    setDaemonOnline(false);
    m_probeIntervalMs = 3000;
    if (m_reconnectTimer && !m_reconnectTimer->isActive()) {
        m_reconnectTimer->start(m_probeIntervalMs);
    }
}

void Application::probeDaemonAsync()
{
    // Strictly asynchronous D-Bus call so Wayland frame rendering never blocks.
    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kDaemonService),
        QString::fromLatin1(kDaemonPath),
        QString::fromLatin1(kDaemonIface),
        QStringLiteral("Ping"));

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        if (reply.isValid()) {
            const bool wasOffline = !m_daemonOnline;
            m_probeIntervalMs = 3000;
            setDaemonOnline(true);
            if (wasOffline && m_daemonClient) {
                m_daemonClient->refreshClips();
            }
            return;
        }

        setDaemonOnline(false);
        if (m_reconnectTimer) {
            m_reconnectTimer->start(m_probeIntervalMs);
            m_probeIntervalMs = qMin(m_probeIntervalMs * 2, 15000);
        }
    });
}

void Application::setDaemonOnline(bool online)
{
    if (m_daemonOnline != online) {
        m_daemonOnline = online;
        Q_EMIT daemonOnlineChanged(m_daemonOnline);
    }
}

} // namespace catchypills::app
