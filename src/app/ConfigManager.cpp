#include "ConfigManager.hpp"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QScreen>
#include <QStandardPaths>
#include <QTextStream>

#include <algorithm>

namespace catchypills::app {

namespace {
constexpr const char *kAutostartDesktopName = "io.hearnelabs.CatchyPills.desktop";
}

ConfigManager::ConfigManager(QObject *parent)
    : QObject(parent)
    , m_settings(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                     + QStringLiteral("/CatchyPills/CatchyPills.conf"),
                 QSettings::IniFormat)
{
    m_targetMonitor = m_settings.value(QStringLiteral("Display/targetMonitor")).toString();
    if (m_targetMonitor.isEmpty()) {
        m_targetMonitor = detectDefaultUltrawideMonitor();
    }

    m_horizontalOffset = std::clamp(
        m_settings.value(QStringLiteral("Display/horizontalOffset"), 0).toInt(), -1000, 1000);
    m_topMargin = std::clamp(
        m_settings.value(QStringLiteral("Display/topMargin"), 0).toInt(), 0, 64);
    m_collapseDelayMs = std::clamp(
        m_settings.value(QStringLiteral("Display/collapseDelayMs"), 220).toInt(), 100, 1000);
    m_autoHideFullscreen =
        m_settings.value(QStringLiteral("Display/autoHideFullscreen"), true).toBool();

    m_clipboardPaused =
        m_settings.value(QStringLiteral("Clipboard/paused"), false).toBool();
    m_shelfRetentionHours =
        m_settings.value(QStringLiteral("Shelf/retentionHours"), 24).toInt();

    const QString defaultShots =
        QStandardPaths::writableLocation(QStandardPaths::PicturesLocation)
        + QStringLiteral("/Screenshots");
    m_screenshotsDir =
        m_settings.value(QStringLiteral("Capture/screenshotsDir"), defaultShots).toString();
    m_autoCopyCapture =
        m_settings.value(QStringLiteral("Capture/autoCopy"), true).toBool();

    connect(qGuiApp, &QGuiApplication::screenAdded, this, &ConfigManager::availableMonitorsChanged);
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, &ConfigManager::availableMonitorsChanged);
}

QStringList ConfigManager::availableMonitors() const
{
    QStringList names;
    for (QScreen *screen : QGuiApplication::screens()) {
        if (screen) {
            names.append(screen->name());
        }
    }
    return names;
}

void ConfigManager::setTargetMonitor(const QString &monitorName)
{
    if (monitorName.isEmpty() || m_targetMonitor == monitorName) {
        return;
    }
    m_targetMonitor = monitorName;
    m_settings.setValue(QStringLiteral("Display/targetMonitor"), m_targetMonitor);
    m_settings.sync();
    Q_EMIT targetMonitorChanged(m_targetMonitor);
}

void ConfigManager::setHorizontalOffset(int offset)
{
    const int clamped = std::clamp(offset, -1000, 1000);
    if (m_horizontalOffset == clamped) {
        return;
    }
    m_horizontalOffset = clamped;
    m_settings.setValue(QStringLiteral("Display/horizontalOffset"), m_horizontalOffset);
    m_settings.sync();
    Q_EMIT horizontalOffsetChanged(m_horizontalOffset);
}

void ConfigManager::setTopMargin(int margin)
{
    const int clamped = std::clamp(margin, 0, 64);
    if (m_topMargin == clamped) {
        return;
    }
    m_topMargin = clamped;
    m_settings.setValue(QStringLiteral("Display/topMargin"), m_topMargin);
    m_settings.sync();
    Q_EMIT topMarginChanged(m_topMargin);
}

void ConfigManager::setCollapseDelayMs(int delayMs)
{
    const int clamped = std::clamp(delayMs, 100, 1000);
    if (m_collapseDelayMs == clamped) {
        return;
    }
    m_collapseDelayMs = clamped;
    m_settings.setValue(QStringLiteral("Display/collapseDelayMs"), m_collapseDelayMs);
    m_settings.sync();
    Q_EMIT collapseDelayMsChanged(m_collapseDelayMs);
}

void ConfigManager::setAutoHideFullscreen(bool enabled)
{
    if (m_autoHideFullscreen == enabled) {
        return;
    }
    m_autoHideFullscreen = enabled;
    m_settings.setValue(QStringLiteral("Display/autoHideFullscreen"), m_autoHideFullscreen);
    m_settings.sync();
    Q_EMIT autoHideFullscreenChanged(m_autoHideFullscreen);
}

void ConfigManager::setClipboardPaused(bool paused)
{
    if (m_clipboardPaused == paused) {
        return;
    }
    m_clipboardPaused = paused;
    m_settings.setValue(QStringLiteral("Clipboard/paused"), m_clipboardPaused);
    m_settings.sync();
    Q_EMIT clipboardPausedChanged(m_clipboardPaused);
}

void ConfigManager::setShelfRetentionHours(int hours)
{
    if (m_shelfRetentionHours == hours) {
        return;
    }
    m_shelfRetentionHours = hours;
    m_settings.setValue(QStringLiteral("Shelf/retentionHours"), m_shelfRetentionHours);
    m_settings.sync();
    Q_EMIT shelfRetentionHoursChanged(m_shelfRetentionHours);
}

void ConfigManager::setScreenshotsDir(const QString &path)
{
    const QString trimmed = path.trimmed();
    if (trimmed.isEmpty() || m_screenshotsDir == trimmed) {
        return;
    }
    QDir().mkpath(trimmed);
    m_screenshotsDir = trimmed;
    m_settings.setValue(QStringLiteral("Capture/screenshotsDir"), m_screenshotsDir);
    m_settings.sync();
    Q_EMIT screenshotsDirChanged(m_screenshotsDir);
}

void ConfigManager::setScreenshotsDirFromUrl(const QUrl &url)
{
    if (url.isLocalFile()) {
        setScreenshotsDir(url.toLocalFile());
    }
}

void ConfigManager::setAutoCopyCapture(bool enabled)
{
    if (m_autoCopyCapture == enabled) {
        return;
    }
    m_autoCopyCapture = enabled;
    m_settings.setValue(QStringLiteral("Capture/autoCopy"), m_autoCopyCapture);
    m_settings.sync();
    Q_EMIT autoCopyCaptureChanged(m_autoCopyCapture);
}

bool ConfigManager::startWithSystem() const
{
    const QString userFile = userAutostartPath();
    if (QFileInfo::exists(userFile)) {
        QFile f(userFile);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString content = QString::fromUtf8(f.readAll());
            if (content.contains(QStringLiteral("Hidden=true"), Qt::CaseInsensitive)) {
                return false;
            }
        }
        return true;
    }
    return QFileInfo::exists(QStringLiteral("/etc/xdg/autostart/")
                              + QString::fromLatin1(kAutostartDesktopName));
}

void ConfigManager::setStartWithSystem(bool enabled)
{
    const QString userFile = userAutostartPath();
    QDir().mkpath(QFileInfo(userFile).absolutePath());

    if (enabled) {
        const QString source = sourceDesktopEntryPath();
        QString content;
        QFile src(source);
        if (!source.isEmpty() && src.open(QIODevice::ReadOnly | QIODevice::Text)) {
            content = QString::fromUtf8(src.readAll());
        } else {
            content = QStringLiteral(
                "[Desktop Entry]\n"
                "Name=CatchyPills\n"
                "Exec=catchypills\n"
                "Icon=catchypills\n"
                "Type=Application\n"
                "OnlyShowIn=KDE;\n"
                "X-KDE-autostart-phase=2\n"
                "X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2\n");
        }

        QFile out(userFile);
        if (out.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            QTextStream stream(&out);
            stream << content;
        }
    } else {
        const QString systemAutostart = QStringLiteral("/etc/xdg/autostart/")
                                        + QString::fromLatin1(kAutostartDesktopName);
        if (QFileInfo::exists(systemAutostart)) {
            // Respect XDG Autostart spec override when system-wide autostart exists.
            QFile out(userFile);
            if (out.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                QTextStream stream(&out);
                stream << "[Desktop Entry]\nType=Application\nName=CatchyPills\nHidden=true\n";
            }
        } else {
            QFile::remove(userFile);
        }
    }

    Q_EMIT startWithSystemChanged(startWithSystem());
}

QString ConfigManager::detectDefaultUltrawideMonitor() const
{
    QScreen *widest = QGuiApplication::primaryScreen();
    int maxWidth = widest ? widest->geometry().width() : 0;

    for (QScreen *screen : QGuiApplication::screens()) {
        if (!screen) {
            continue;
        }
        const QSize geo = screen->geometry().size();
        if (geo.width() == 3840 && geo.height() == 1080) {
            return screen->name();
        }
        if (geo.width() > maxWidth) {
            maxWidth = geo.width();
            widest = screen;
        }
    }
    return widest ? widest->name() : QString();
}

QString ConfigManager::userAutostartPath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
           + QStringLiteral("/autostart/") + QString::fromLatin1(kAutostartDesktopName);
}

QString ConfigManager::sourceDesktopEntryPath() const
{
    const QString systemApp = QStringLiteral("/usr/share/applications/")
                              + QString::fromLatin1(kAutostartDesktopName);
    if (QFileInfo::exists(systemApp)) {
        return systemApp;
    }
    const QString localApp = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                             + QStringLiteral("/applications/")
                             + QString::fromLatin1(kAutostartDesktopName);
    if (QFileInfo::exists(localApp)) {
        return localApp;
    }
    return {};
}

} // namespace catchypills::app
