#include "ConfigManager.hpp"

#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QGuiApplication>
#include <QScreen>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>
#include <QVariant>

#include <algorithm>
#include <cmath>

namespace catchypills::app {

namespace {
constexpr const char *kAutostartDesktopName = "io.beanzcraftz.CatchyPills.desktop";
}

ConfigManager::ConfigManager(QObject *parent)
    : QObject(parent)
    , m_settings(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                     + QStringLiteral("/CatchyPills/CatchyPills.conf"),
                 QSettings::IniFormat)
{
    loadDotEnv();

    m_targetMonitor = m_settings.value(QStringLiteral("Display/targetMonitor")).toString();
    if (m_targetMonitor.isEmpty()) {
        m_targetMonitor = detectDefaultUltrawideMonitor();
    }

    m_horizontalOffset = std::clamp(
        m_settings.value(QStringLiteral("Display/horizontalOffset"), 0).toInt(), -1000, 1000);
    m_topMargin = std::clamp(
        m_settings.value(QStringLiteral("Display/topMargin"), 0).toInt(), 0, 64);
    m_posX = m_settings.value(QStringLiteral("Display/posX"), -1).toInt();
    m_posY = m_settings.value(QStringLiteral("Display/posY"), -1).toInt();
    if (m_posX < 0 || m_posY < 0) {
        m_posX = -1;
        m_posY = -1;
    }
    m_collapseDelayMs = std::clamp(
        m_settings.value(QStringLiteral("Display/collapseDelayMs"), 220).toInt(), 100, 1000);
    m_autoHideFullscreen =
        m_settings.value(QStringLiteral("Display/autoHideFullscreen"), true).toBool();

    m_clipboardPaused =
        m_settings.value(QStringLiteral("Clipboard/paused"), false).toBool();

    const QString defaultShots =
        QStandardPaths::writableLocation(QStandardPaths::PicturesLocation)
        + QStringLiteral("/Screenshots");
    m_screenshotsDir =
        m_settings.value(QStringLiteral("Capture/screenshotsDir"), defaultShots).toString();
    m_autoCopyCapture =
        m_settings.value(QStringLiteral("Capture/autoCopy"), true).toBool();

    m_weatherLatitude = std::clamp(
        m_settings.value(QStringLiteral("Weather/latitude"), -27.82).toDouble(), -90.0, 90.0);
    m_weatherLongitude = std::clamp(
        m_settings.value(QStringLiteral("Weather/longitude"), 152.96).toDouble(), -180.0, 180.0);

    m_enableITSM = loadBoolFeatureFlag(
        QStringLiteral("Integrations/enableITSM"),
        {QStringLiteral("ENABLE_ITSM"), QStringLiteral("CATCHYPILLS_ENABLE_ITSM")});
    m_enableIoT = loadBoolFeatureFlag(
        QStringLiteral("Integrations/enableIoT"),
        {QStringLiteral("ENABLE_IOT"), QStringLiteral("CATCHYPILLS_ENABLE_IOT")});
    m_enableSolar = loadBoolFeatureFlag(
        QStringLiteral("Integrations/enableSolar"),
        {QStringLiteral("ENABLE_SOLAR"), QStringLiteral("CATCHYPILLS_ENABLE_SOLAR")});
    m_enableWorklog = loadBoolFeatureFlag(
        QStringLiteral("Integrations/enableWorklog"),
        {QStringLiteral("ENABLE_WORKLOG"), QStringLiteral("CATCHYPILLS_ENABLE_WORKLOG")});

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
    const bool hadCustom = clearCustomPosition();
    if (monitorName.isEmpty() || (m_targetMonitor == monitorName && !hadCustom)) {
        return;
    }
    m_targetMonitor = monitorName;
    m_settings.setValue(QStringLiteral("Display/targetMonitor"), m_targetMonitor);
    m_settings.sync();
    Q_EMIT targetMonitorChanged(m_targetMonitor);
}

void ConfigManager::setHorizontalOffset(int offset)
{
    const bool hadCustom = clearCustomPosition();
    const int clamped = std::clamp(offset, -1000, 1000);
    if (m_horizontalOffset == clamped && !hadCustom) {
        return;
    }
    m_horizontalOffset = clamped;
    m_settings.setValue(QStringLiteral("Display/horizontalOffset"), m_horizontalOffset);
    m_settings.sync();
    Q_EMIT horizontalOffsetChanged(m_horizontalOffset);
}

void ConfigManager::setTopMargin(int margin)
{
    const bool hadCustom = clearCustomPosition();
    const int clamped = std::clamp(margin, 0, 64);
    if (m_topMargin == clamped && !hadCustom) {
        return;
    }
    m_topMargin = clamped;
    m_settings.setValue(QStringLiteral("Display/topMargin"), m_topMargin);
    m_settings.sync();
    Q_EMIT topMarginChanged(m_topMargin);
}

void ConfigManager::setAbsolutePosition(int x, int y)
{
    const int clampedX = std::max(0, x);
    const int clampedY = std::max(0, y);
    if (m_posX == clampedX && m_posY == clampedY) {
        return;
    }
    m_posX = clampedX;
    m_posY = clampedY;
    m_settings.setValue(QStringLiteral("Display/posX"), m_posX);
    m_settings.setValue(QStringLiteral("Display/posY"), m_posY);
    m_settings.sync();
    Q_EMIT positionChanged(m_posX, m_posY);
}

void ConfigManager::setMonitorAndPosition(const QString &monitorName, int x, int y)
{
    const int clampedX = std::max(0, x);
    const int clampedY = std::max(0, y);
    const bool monitorChanged = !monitorName.isEmpty() && m_targetMonitor != monitorName;
    const bool posChanged = m_posX != clampedX || m_posY != clampedY;

    if (!monitorChanged && !posChanged) {
        return;
    }

    if (monitorChanged) {
        m_targetMonitor = monitorName;
        m_settings.setValue(QStringLiteral("Display/targetMonitor"), m_targetMonitor);
    }
    m_posX = clampedX;
    m_posY = clampedY;
    m_settings.setValue(QStringLiteral("Display/posX"), m_posX);
    m_settings.setValue(QStringLiteral("Display/posY"), m_posY);
    m_settings.sync();

    if (monitorChanged) {
        Q_EMIT targetMonitorChanged(m_targetMonitor);
    }
    if (posChanged) {
        Q_EMIT positionChanged(m_posX, m_posY);
    }
}

bool ConfigManager::clearCustomPosition()
{
    if (m_posX < 0 && m_posY < 0) {
        return false;
    }
    m_posX = -1;
    m_posY = -1;
    m_settings.remove(QStringLiteral("Display/posX"));
    m_settings.remove(QStringLiteral("Display/posY"));
    m_settings.sync();
    Q_EMIT positionChanged(-1, -1);
    return true;
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

QString ConfigManager::urlToLocalPath(const QUrl &url) const
{
    return url.isLocalFile() ? url.toLocalFile() : url.toString();
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

void ConfigManager::setWeatherLatitude(double latitude)
{
    const double clamped = std::clamp(latitude, -90.0, 90.0);
    if (std::abs(m_weatherLatitude - clamped) < 1e-6) {
        return;
    }
    m_weatherLatitude = clamped;
    m_settings.setValue(QStringLiteral("Weather/latitude"), m_weatherLatitude);
    m_settings.sync();
    Q_EMIT weatherLatitudeChanged(m_weatherLatitude);
    Q_EMIT weatherCoordinatesChanged(m_weatherLatitude, m_weatherLongitude);
}

void ConfigManager::setWeatherLongitude(double longitude)
{
    const double clamped = std::clamp(longitude, -180.0, 180.0);
    if (std::abs(m_weatherLongitude - clamped) < 1e-6) {
        return;
    }
    m_weatherLongitude = clamped;
    m_settings.setValue(QStringLiteral("Weather/longitude"), m_weatherLongitude);
    m_settings.sync();
    Q_EMIT weatherLongitudeChanged(m_weatherLongitude);
    Q_EMIT weatherCoordinatesChanged(m_weatherLatitude, m_weatherLongitude);
}

void ConfigManager::setEnableITSM(bool enabled)
{
    if (m_enableITSM == enabled) {
        return;
    }
    m_enableITSM = enabled;
    m_settings.setValue(QStringLiteral("Integrations/enableITSM"), m_enableITSM);
    m_settings.sync();
    Q_EMIT enableITSMChanged(m_enableITSM);
}

void ConfigManager::setEnableIoT(bool enabled)
{
    if (m_enableIoT == enabled) {
        return;
    }
    m_enableIoT = enabled;
    m_settings.setValue(QStringLiteral("Integrations/enableIoT"), m_enableIoT);
    m_settings.sync();
    Q_EMIT enableIoTChanged(m_enableIoT);
}

void ConfigManager::setEnableSolar(bool enabled)
{
    if (m_enableSolar == enabled) {
        return;
    }
    m_enableSolar = enabled;
    m_settings.setValue(QStringLiteral("Integrations/enableSolar"), m_enableSolar);
    m_settings.sync();
    Q_EMIT enableSolarChanged(m_enableSolar);
}

void ConfigManager::setEnableWorklog(bool enabled)
{
    if (m_enableWorklog == enabled) {
        return;
    }
    m_enableWorklog = enabled;
    m_settings.setValue(QStringLiteral("Integrations/enableWorklog"), m_enableWorklog);
    m_settings.sync();
    Q_EMIT enableWorklogChanged(m_enableWorklog);
}

QString ConfigManager::envFilePath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
           + QStringLiteral("/catchypills/.env");
}

QString ConfigManager::envValue(const QString &key, const QString &fallback) const
{
    if (m_envVars.contains(key)) {
        return m_envVars.value(key);
    }
    if (qEnvironmentVariableIsSet(key.toUtf8().constData())) {
        return qEnvironmentVariable(key.toUtf8().constData());
    }
    return fallback;
}

void ConfigManager::reloadEnv()
{
    m_envVars.clear();
    loadDotEnv();
    Q_EMIT envConfigChanged();
}

bool ConfigManager::ensureEnvTemplateExists() const
{
    const QString path = envFilePath();
    if (QFileInfo::exists(path)) {
        return true;
    }

    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }

    const QString starter = QStringLiteral(
        "# CatchyPills Personal & Bespoke Integrations\n"
        "# Edited safely outside git. Save or run Reload .env in Settings.\n\n"
        "# --- IoT Controls (Home Assistant REST or Webhooks) ---\n"
        "# IOT_WEBHOOK_BASE=\"http://192.168.1.244:8123\"\n"
        "# IOT_API_KEY=\"\"\n"
        "# IOT_ENTITY_OFFICE_LIGHTS=\"light.olamp\"\n\n"
        "# --- Solar Telemetry ---\n"
        "# SOLAR_API_URL=\"http://192.168.1.200:8000/api/solar\"\n"
        "# SOLAR_API_KEY=\"\"\n"
        "# SOLAR_POLL_INTERVAL_MS=\"15000\"\n\n"
        "# --- Worklog Time Tracker ---\n"
        "# WORKLOG_DB_PATH=\"\"\n"
        "# WORKLOG_DB_TABLE=\"\"\n"
        "# WORKLOG_API_URL=\"http://192.168.1.200:8501/api/worklog\"\n"
        "# WORKLOG_API_KEY=\"\"\n");

    file.write(starter.toUtf8());
    file.close();
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

bool ConfigManager::saveIntegrationEnv(const QVariantMap &entries)
{
    const QString path = envFilePath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    auto formatEnvLine = [](const QString &key, const QString &rawVal) {
        QString escaped = rawVal;
        escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
        escaped.replace(QLatin1Char('"'), QStringLiteral("\\\""));
        return QStringLiteral("%1=\"%2\"").arg(key, escaped);
    };

    QStringList existingLines;
    {
        QFile existing(path);
        if (existing.exists() && existing.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&existing);
            while (!in.atEnd()) {
                existingLines.append(in.readLine());
            }
        }
    }

    if (existingLines.isEmpty()) {
        existingLines << QStringLiteral("# CatchyPills Personal & Bespoke Integrations")
                      << QStringLiteral("# Managed by CatchyPills Settings (excluded from git)");
    }

    QSet<QString> handledKeys;
    QStringList outputLines;
    outputLines.reserve(existingLines.size() + entries.size());

    for (const QString &rawLine : existingLines) {
        QString probe = rawLine.trimmed();
        if (probe.isEmpty() || probe.startsWith(QLatin1Char('#'))) {
            outputLines.append(rawLine);
            continue;
        }
        if (probe.startsWith(QStringLiteral("export "))) {
            probe = probe.mid(7).trimmed();
        }
        const int eqIdx = probe.indexOf(QLatin1Char('='));
        if (eqIdx <= 0) {
            outputLines.append(rawLine);
            continue;
        }
        const QString key = probe.left(eqIdx).trimmed();
        if (!entries.contains(key)) {
            outputLines.append(rawLine);
            continue;
        }

        handledKeys.insert(key);
        const QString newVal = entries.value(key).toString().trimmed();
        if (newVal.isEmpty()) {
            m_envVars.remove(key);
            qunsetenv(key.toUtf8().constData());
        } else {
            m_envVars.insert(key, newVal);
            qputenv(key.toUtf8().constData(), newVal.toUtf8());
            outputLines.append(formatEnvLine(key, newVal));
        }
    }

    for (auto it = entries.constBegin(); it != entries.constEnd(); ++it) {
        const QString key = it.key().trimmed();
        if (key.isEmpty() || handledKeys.contains(key)) {
            continue;
        }
        const QString newVal = it.value().toString().trimmed();
        if (newVal.isEmpty()) {
            m_envVars.remove(key);
            qunsetenv(key.toUtf8().constData());
        } else {
            m_envVars.insert(key, newVal);
            qputenv(key.toUtf8().constData(), newVal.toUtf8());
            outputLines.append(formatEnvLine(key, newVal));
        }
    }

    QFile outFile(path);
    if (!outFile.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        return false;
    }
    const QByteArray payload = (outputLines.join(QLatin1Char('\n')) + QLatin1Char('\n')).toUtf8();
    outFile.write(payload);
    outFile.close();
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    reloadEnv();
    return true;
}

void ConfigManager::loadDotEnv()
{
    const QString configRoot = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    const QStringList candidates = {
        QDir::currentPath() + QStringLiteral("/.env"),
        configRoot + QStringLiteral("/CatchyPills/.env"),
        configRoot + QStringLiteral("/catchypills/.env"),
    };

    for (const QString &path : candidates) {
        QFile file(path);
        if (!file.exists() || !file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }
        QTextStream in(&file);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
                continue;
            }
            if (line.startsWith(QStringLiteral("export "))) {
                line = line.mid(7).trimmed();
            }
            const int eqIdx = line.indexOf(QLatin1Char('='));
            if (eqIdx <= 0) {
                continue;
            }
            const QString key = line.left(eqIdx).trimmed();
            QString val = line.mid(eqIdx + 1).trimmed();
            if (val.size() >= 2
                && ((val.startsWith(QLatin1Char('"')) && val.endsWith(QLatin1Char('"')))
                    || (val.startsWith(QLatin1Char('\'')) && val.endsWith(QLatin1Char('\''))))) {
                val = val.mid(1, val.size() - 2);
                val.replace(QStringLiteral("\\\""), QStringLiteral("\""));
                val.replace(QStringLiteral("\\\\"), QStringLiteral("\\"));
            }
            if (!key.isEmpty()) {
                m_envVars.insert(key, val);
                qputenv(key.toUtf8().constData(), val.toUtf8());
            }
        }
    }
}

bool ConfigManager::loadBoolFeatureFlag(const QString &settingsKey, const QStringList &envKeys) const
{
    if (m_settings.contains(settingsKey)) {
        return m_settings.value(settingsKey, false).toBool();
    }
    for (const QString &envKey : envKeys) {
        const QString raw = envValue(envKey).trimmed().toLower();
        if (raw == QStringLiteral("1") || raw == QStringLiteral("true")
            || raw == QStringLiteral("yes") || raw == QStringLiteral("on")) {
            return true;
        }
    }
    return false;
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
