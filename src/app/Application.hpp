#pragma once

#include <QObject>
#include <QString>

class QDBusServiceWatcher;
class QQmlApplicationEngine;
class QQuickWindow;
class QTimer;

namespace catchypills::capture {
class CaptureCoordinator;
class CaptureImageProvider;
}

namespace catchypills::core {
class DaemonClient;
}

namespace catchypills::wayland {
class LayerSurfaceController;
}

namespace catchypills::app {

/**
 * Top-level application coordinator owning the Wayland windows, capture
 * pipeline, D-Bus client, and resilient systemd-user daemon watcher.
 */
class Application final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool daemonOnline READ isDaemonOnline NOTIFY daemonOnlineChanged)
    Q_PROPERTY(QString daemonStatusText READ daemonStatusText NOTIFY daemonOnlineChanged)

public:
    explicit Application(QObject *parent = nullptr);

    bool initialize();

    bool isDaemonOnline() const noexcept { return m_daemonOnline; }
    QString daemonStatusText() const;

Q_SIGNALS:
    void daemonOnlineChanged(bool online);

private Q_SLOTS:
    void onDaemonRegistered(const QString &serviceName);
    void onDaemonUnregistered(const QString &serviceName);
    void probeDaemonAsync();

private:
    void setupDaemonWatcher();
    void setDaemonOnline(bool online);

    static constexpr const char *kDaemonService = "io.hearnelabs.CatchyPillsDaemon";
    static constexpr const char *kDaemonPath = "/io/hearnelabs/CatchyPillsDaemon";
    static constexpr const char *kDaemonIface = "io.hearnelabs.CatchyPillsDaemon1";

    QQmlApplicationEngine *m_engine{nullptr};
    core::DaemonClient *m_daemonClient{nullptr};
    capture::CaptureImageProvider *m_imageProvider{nullptr};
    capture::CaptureCoordinator *m_captureCoordinator{nullptr};
    wayland::LayerSurfaceController *m_islandLayer{nullptr};
    wayland::LayerSurfaceController *m_overlayLayer{nullptr};

    QDBusServiceWatcher *m_daemonWatcher{nullptr};
    QTimer *m_reconnectTimer{nullptr};
    int m_probeIntervalMs{3000};
    bool m_daemonOnline{false};
};

} // namespace catchypills::app
