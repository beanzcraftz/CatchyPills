#pragma once

#include <QObject>
#include <QString>

class QAction;
class QDBusServiceWatcher;
class QMenu;
class QQmlApplicationEngine;
class QQuickWindow;
class QSystemTrayIcon;
class QTimer;

namespace catchypills::capture {
class CaptureCoordinator;
class CaptureImageProvider;
}

namespace catchypills::core {
class DaemonClient;
}

namespace catchypills::iot {
class IoTController;
}

namespace catchypills::itsm {
class ITSMController;
}

namespace catchypills::media {
class MprisController;
}

namespace catchypills::notes {
class NotesModel;
}

namespace catchypills::solar {
class SolarController;
}

namespace catchypills::sysmon {
class SysMonController;
}

namespace catchypills::weather {
class WeatherController;
}

namespace catchypills::worklog {
class WorklogController;
}

namespace catchypills::wayland {
class LayerSurfaceController;
}

namespace catchypills::app {

class ConfigManager;

/**
 * Top-level application coordinator owning the Wayland windows, live settings,
 * system tray menu, capture pipeline, D-Bus client, and daemon watcher.
 */
class Application final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool daemonOnline READ isDaemonOnline NOTIFY daemonOnlineChanged)
    Q_PROPERTY(QString daemonStatusText READ daemonStatusText NOTIFY daemonOnlineChanged)

public:
    explicit Application(QObject *parent = nullptr);
    ~Application() override;

    bool initialize();

    bool isDaemonOnline() const noexcept { return m_daemonOnline; }
    QString daemonStatusText() const;

    Q_INVOKABLE void openSettings();
    Q_INVOKABLE void toggleIslandVisible();
    Q_INVOKABLE void openWebSearch(const QString &query);

Q_SIGNALS:
    void daemonOnlineChanged(bool online);

private Q_SLOTS:
    void onDaemonRegistered(const QString &serviceName);
    void onDaemonUnregistered(const QString &serviceName);
    void probeDaemonAsync();
    void applyDisplaySettings();

private:
    void setupDaemonWatcher();
    void setupTrayIcon();
    void syncDaemonPreferences();
    void setDaemonOnline(bool online);

    static constexpr const char *kDaemonService = "io.hearnelabs.CatchyPillsDaemon";
    static constexpr const char *kDaemonPath = "/io/hearnelabs/CatchyPillsDaemon";
    static constexpr const char *kDaemonIface = "io.hearnelabs.CatchyPillsDaemon1";

    ConfigManager *m_configManager{nullptr};
    QQmlApplicationEngine *m_engine{nullptr};
    core::DaemonClient *m_daemonClient{nullptr};
    iot::IoTController *m_iotController{nullptr};
    itsm::ITSMController *m_itsmController{nullptr};
    media::MprisController *m_mprisController{nullptr};
    notes::NotesModel *m_notesModel{nullptr};
    solar::SolarController *m_solarController{nullptr};
    sysmon::SysMonController *m_sysMonController{nullptr};
    weather::WeatherController *m_weatherController{nullptr};
    worklog::WorklogController *m_worklogController{nullptr};
    capture::CaptureImageProvider *m_imageProvider{nullptr};
    capture::CaptureCoordinator *m_captureCoordinator{nullptr};
    wayland::LayerSurfaceController *m_islandLayer{nullptr};
    wayland::LayerSurfaceController *m_overlayLayer{nullptr};
    QQuickWindow *m_islandWindow{nullptr};
    QQuickWindow *m_settingsWindow{nullptr};

    QSystemTrayIcon *m_trayIcon{nullptr};
    QMenu *m_trayMenu{nullptr};
    QAction *m_pauseClipboardAction{nullptr};

    QDBusServiceWatcher *m_daemonWatcher{nullptr};
    QTimer *m_reconnectTimer{nullptr};
    int m_probeIntervalMs{3000};
    bool m_daemonOnline{false};
};

} // namespace catchypills::app
