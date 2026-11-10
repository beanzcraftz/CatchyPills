#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QUrl>

namespace catchypills::app {

/**
 * Persistent user preferences stored in ~/.config/CatchyPills/CatchyPills.conf
 * via QSettings, with real-time desktop autostart synchronization.
 */
class ConfigManager final : public QObject
{
    Q_OBJECT

    // Display & Position
    Q_PROPERTY(QStringList availableMonitors READ availableMonitors NOTIFY availableMonitorsChanged)
    Q_PROPERTY(QString targetMonitor READ targetMonitor WRITE setTargetMonitor NOTIFY targetMonitorChanged)
    Q_PROPERTY(int horizontalOffset READ horizontalOffset WRITE setHorizontalOffset NOTIFY horizontalOffsetChanged)
    Q_PROPERTY(int topMargin READ topMargin WRITE setTopMargin NOTIFY topMarginChanged)
    Q_PROPERTY(int posX READ posX NOTIFY positionChanged)
    Q_PROPERTY(int posY READ posY NOTIFY positionChanged)
    Q_PROPERTY(bool hasCustomPosition READ hasCustomPosition NOTIFY positionChanged)
    Q_PROPERTY(int collapseDelayMs READ collapseDelayMs WRITE setCollapseDelayMs NOTIFY collapseDelayMsChanged)
    Q_PROPERTY(bool autoHideFullscreen READ autoHideFullscreen WRITE setAutoHideFullscreen NOTIFY autoHideFullscreenChanged)

    // Clipboard & File Shelf
    Q_PROPERTY(bool clipboardPaused READ clipboardPaused WRITE setClipboardPaused NOTIFY clipboardPausedChanged)
    Q_PROPERTY(int shelfRetentionHours READ shelfRetentionHours WRITE setShelfRetentionHours NOTIFY shelfRetentionHoursChanged)

    // OmniShot Capture & System
    Q_PROPERTY(QString screenshotsDir READ screenshotsDir WRITE setScreenshotsDir NOTIFY screenshotsDirChanged)
    Q_PROPERTY(bool autoCopyCapture READ autoCopyCapture WRITE setAutoCopyCapture NOTIFY autoCopyCaptureChanged)
    Q_PROPERTY(bool startWithSystem READ startWithSystem WRITE setStartWithSystem NOTIFY startWithSystemChanged)

public:
    explicit ConfigManager(QObject *parent = nullptr);

    QStringList availableMonitors() const;

    QString targetMonitor() const { return m_targetMonitor; }
    void setTargetMonitor(const QString &monitorName);

    int horizontalOffset() const noexcept { return m_horizontalOffset; }
    void setHorizontalOffset(int offset);

    int topMargin() const noexcept { return m_topMargin; }
    void setTopMargin(int margin);

    int posX() const noexcept { return m_posX; }
    int posY() const noexcept { return m_posY; }
    bool hasCustomPosition() const noexcept { return m_posX >= 0 && m_posY >= 0; }
    Q_INVOKABLE void setAbsolutePosition(int x, int y);
    Q_INVOKABLE void setMonitorAndPosition(const QString &monitorName, int x, int y);

    int collapseDelayMs() const noexcept { return m_collapseDelayMs; }
    void setCollapseDelayMs(int delayMs);

    bool autoHideFullscreen() const noexcept { return m_autoHideFullscreen; }
    void setAutoHideFullscreen(bool enabled);

    bool clipboardPaused() const noexcept { return m_clipboardPaused; }
    void setClipboardPaused(bool paused);

    int shelfRetentionHours() const noexcept { return m_shelfRetentionHours; }
    void setShelfRetentionHours(int hours);

    QString screenshotsDir() const { return m_screenshotsDir; }
    void setScreenshotsDir(const QString &path);
    Q_INVOKABLE void setScreenshotsDirFromUrl(const QUrl &url);

    bool autoCopyCapture() const noexcept { return m_autoCopyCapture; }
    void setAutoCopyCapture(bool enabled);

    bool startWithSystem() const;
    void setStartWithSystem(bool enabled);

Q_SIGNALS:
    void availableMonitorsChanged();
    void targetMonitorChanged(const QString &monitorName);
    void horizontalOffsetChanged(int offset);
    void topMarginChanged(int margin);
    void positionChanged(int x, int y);
    void collapseDelayMsChanged(int delayMs);
    void autoHideFullscreenChanged(bool enabled);
    void clipboardPausedChanged(bool paused);
    void shelfRetentionHoursChanged(int hours);
    void screenshotsDirChanged(const QString &path);
    void autoCopyCaptureChanged(bool enabled);
    void startWithSystemChanged(bool enabled);

private:
    bool clearCustomPosition();
    QString detectDefaultUltrawideMonitor() const;
    QString userAutostartPath() const;
    QString sourceDesktopEntryPath() const;

    QSettings m_settings;
    QString m_targetMonitor;
    int m_horizontalOffset{0};
    int m_topMargin{0};
    int m_posX{-1};
    int m_posY{-1};
    int m_collapseDelayMs{220};
    bool m_autoHideFullscreen{true};
    bool m_clipboardPaused{false};
    int m_shelfRetentionHours{24};
    QString m_screenshotsDir;
    bool m_autoCopyCapture{true};
};

} // namespace catchypills::app
