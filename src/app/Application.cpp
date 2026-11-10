#include "Application.hpp"

#include "ConfigManager.hpp"
#include "core/DaemonClient.hpp"
#include "modules/capture/CaptureCoordinator.hpp"
#include "modules/media/MprisController.hpp"
#include "modules/notes/NotesModel.hpp"
#include "modules/shelf/FileShelfModel.hpp"
#include "wayland/LayerSurfaceController.hpp"

#include <QAction>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDesktopServices>
#include <QIcon>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSystemTrayIcon>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

namespace catchypills::app {

namespace {
QIcon makePillTrayIcon()
{
    QIcon themed = QIcon::fromTheme(QStringLiteral("catchypills"));
    if (!themed.isNull()) {
        return themed;
    }

    QPixmap pm(64, 64);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setPen(QPen(QColor(QStringLiteral("#38bdf8")), 3));
    p.setBrush(QColor(QStringLiteral("#0f172a")));
    p.drawRoundedRect(6, 20, 52, 24, 12, 12);
    p.setPen(Qt::NoPen);
    p.setBrush(QColor(QStringLiteral("#38bdf8")));
    p.drawEllipse(16, 27, 10, 10);
    return QIcon(pm);
}
} // namespace

Application::Application(QObject *parent)
    : QObject(parent)
{
}

Application::~Application()
{
    delete m_settingsWindow;
    delete m_trayMenu;
}

bool Application::initialize()
{
    m_configManager = new ConfigManager(this);
    m_imageProvider = new capture::CaptureImageProvider();
    m_daemonClient = new core::DaemonClient(this);
    m_mprisController = new media::MprisController(this);
    m_notesModel = new notes::NotesModel(this);
    m_fileShelfModel = new shelf::FileShelfModel(this);
    m_captureCoordinator = new capture::CaptureCoordinator(m_imageProvider, this);
    m_islandLayer = new wayland::LayerSurfaceController(nullptr, this);
    m_engine = new QQmlApplicationEngine(this);

    m_fileShelfModel->setRetentionHours(m_configManager->shelfRetentionHours());
    m_captureCoordinator->setOutputDirectory(m_configManager->screenshotsDir());
    m_captureCoordinator->setAutoCopyEnabled(m_configManager->autoCopyCapture());

    connect(m_configManager, &ConfigManager::shelfRetentionHoursChanged,
            m_fileShelfModel, &shelf::FileShelfModel::setRetentionHours);
    connect(m_configManager, &ConfigManager::screenshotsDirChanged,
            m_captureCoordinator, &capture::CaptureCoordinator::setOutputDirectory);
    connect(m_configManager, &ConfigManager::autoCopyCaptureChanged,
            m_captureCoordinator, &capture::CaptureCoordinator::setAutoCopyEnabled);
    connect(m_configManager, &ConfigManager::clipboardPausedChanged,
            m_daemonClient, &core::DaemonClient::setClipboardPaused);

    connect(m_configManager, &ConfigManager::targetMonitorChanged,
            this, &Application::applyDisplaySettings);
    connect(m_configManager, &ConfigManager::horizontalOffsetChanged,
            this, &Application::applyDisplaySettings);
    connect(m_configManager, &ConfigManager::topMarginChanged,
            this, &Application::applyDisplaySettings);
    connect(m_configManager, &ConfigManager::positionChanged,
            this, &Application::applyDisplaySettings);
    connect(m_configManager, &ConfigManager::autoHideFullscreenChanged,
            this, &Application::applyDisplaySettings);

    m_engine->addImageProvider(QStringLiteral("capture"), m_imageProvider);
    m_engine->rootContext()->setContextProperty(QStringLiteral("appController"), this);
    m_engine->rootContext()->setContextProperty(QStringLiteral("configManager"), m_configManager);
    m_engine->rootContext()->setContextProperty(QStringLiteral("daemonClient"), m_daemonClient);
    m_engine->rootContext()->setContextProperty(QStringLiteral("mprisController"), m_mprisController);
    m_engine->rootContext()->setContextProperty(QStringLiteral("notesModel"), m_notesModel);
    m_engine->rootContext()->setContextProperty(QStringLiteral("fileShelfModel"), m_fileShelfModel);
    m_engine->rootContext()->setContextProperty(QStringLiteral("captureCoordinator"), m_captureCoordinator);
    m_engine->rootContext()->setContextProperty(QStringLiteral("layerController"), m_islandLayer);

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

    m_islandWindow = qobject_cast<QQuickWindow *>(m_engine->rootObjects().constFirst());
    if (!m_islandWindow) {
        return false;
    }

    m_islandLayer->setWindow(m_islandWindow);

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

    // Bind zwlr_layer_shell_v1 and saved ultrawide placement before mapping the surface.
    m_islandLayer->attachToLayerShell();
    applyDisplaySettings();
    m_islandWindow->show();

    setupTrayIcon();
    probeDaemonAsync();
    return true;
}

QString Application::daemonStatusText() const
{
    return m_daemonOnline
        ? QStringLiteral("Daemon connected")
        : QStringLiteral("Daemon offline — reconnecting...");
}

void Application::openSettings()
{
    if (!m_engine) {
        return;
    }

    if (!m_settingsWindow) {
        QQmlComponent component(m_engine, QStringLiteral("CatchyPills"), QStringLiteral("SettingsWindow"));
        if (component.isError()) {
            qWarning("Failed to load SettingsWindow: %s", qPrintable(component.errorString()));
            return;
        }
        m_settingsWindow = qobject_cast<QQuickWindow *>(component.create(m_engine->rootContext()));
        if (!m_settingsWindow) {
            return;
        }
    }

    m_settingsWindow->show();
    m_settingsWindow->raise();
    m_settingsWindow->requestActivate();
}

void Application::toggleIslandVisible()
{
    if (!m_islandWindow) {
        return;
    }
    if (m_islandWindow->isVisible()) {
        m_islandWindow->hide();
    } else {
        m_islandWindow->show();
        m_islandWindow->raise();
    }
}

void Application::openWebSearch(const QString &query)
{
    const QString trimmed = query.trimmed();
    if (trimmed.isEmpty()) {
        return;
    }

    QUrl url(QStringLiteral("https://duckduckgo.com/"));
    QUrlQuery params;
    params.addQueryItem(QStringLiteral("q"), trimmed);
    url.setQuery(params);
    QDesktopServices::openUrl(url);
}

void Application::applyDisplaySettings()
{
    if (!m_islandLayer || !m_configManager) {
        return;
    }
    if (m_configManager->hasCustomPosition()) {
        m_islandLayer->applyScreenAndLayer(
            m_configManager->targetMonitor(),
            m_configManager->autoHideFullscreen());
        m_islandLayer->setAbsolutePosition(
            m_configManager->posX(),
            m_configManager->posY());
    } else {
        m_islandLayer->applyDisplayPreferences(
            m_configManager->targetMonitor(),
            m_configManager->horizontalOffset(),
            m_configManager->topMargin(),
            m_configManager->autoHideFullscreen());
    }
}

void Application::setupTrayIcon()
{
    if (!QSystemTrayIcon::isSystemTrayAvailable()) {
        return;
    }

    m_trayMenu = new QMenu();
    auto *toggleAction = m_trayMenu->addAction(QStringLiteral("Show / Hide Island"));
    connect(toggleAction, &QAction::triggered, this, &Application::toggleIslandVisible);

    auto *snipAction = m_trayMenu->addAction(QStringLiteral("Region Snip (Annotate)"));
    connect(snipAction, &QAction::triggered, m_captureCoordinator, [this]() {
        m_captureCoordinator->prepareRegionCapture(false);
    });

    m_trayMenu->addSeparator();

    m_pauseClipboardAction = m_trayMenu->addAction(QStringLiteral("Pause Clipboard Capture"));
    m_pauseClipboardAction->setCheckable(true);
    m_pauseClipboardAction->setChecked(m_configManager->clipboardPaused());
    connect(m_pauseClipboardAction, &QAction::toggled,
            m_configManager, &ConfigManager::setClipboardPaused);
    connect(m_configManager, &ConfigManager::clipboardPausedChanged,
            m_pauseClipboardAction, &QAction::setChecked);

    auto *settingsAction = m_trayMenu->addAction(QStringLiteral("Settings..."));
    connect(settingsAction, &QAction::triggered, this, &Application::openSettings);

    m_trayMenu->addSeparator();

    auto *quitAction = m_trayMenu->addAction(QStringLiteral("Quit CatchyPills"));
    connect(quitAction, &QAction::triggered, qApp, &QCoreApplication::quit);

    m_trayIcon = new QSystemTrayIcon(makePillTrayIcon(), this);
    m_trayIcon->setToolTip(QStringLiteral("CatchyPills — Dynamic Island & Capture Suite"));
    m_trayIcon->setContextMenu(m_trayMenu);
    connect(m_trayIcon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger) {
            toggleIslandVisible();
        }
    });
    m_trayIcon->show();
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

void Application::syncDaemonPreferences()
{
    if (m_daemonClient && m_configManager) {
        m_daemonClient->setClipboardPaused(m_configManager->clipboardPaused());
        m_daemonClient->refreshClips();
    }
}

void Application::onDaemonRegistered(const QString &serviceName)
{
    Q_UNUSED(serviceName)
    m_probeIntervalMs = 3000;
    if (m_reconnectTimer) {
        m_reconnectTimer->stop();
    }
    setDaemonOnline(true);
    syncDaemonPreferences();
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
            if (wasOffline) {
                syncDaemonPreferences();
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
