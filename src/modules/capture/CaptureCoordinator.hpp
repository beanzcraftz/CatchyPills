#pragma once

#include <QImage>
#include <QObject>
#include <QPoint>
#include <QQuickImageProvider>
#include <QRect>
#include <QSize>
#include <QString>
#include <QVariantList>

#include <mutex>

class PipeWireRecord;

namespace catchypills::capture {

/**
 * Serves the pre-overlay frozen desktop snapshot (`image://capture/backdrop`)
 * to CaptureOverlay.qml so the loupe magnifier can inspect real desktop pixels
 * inside Wayland's strict client isolation.
 */
class CaptureImageProvider final : public QQuickImageProvider
{
public:
    CaptureImageProvider();

    void setBackdrop(const QImage &image);
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    std::mutex m_mutex;
    QImage m_backdrop;
};

/**
 * Orchestrates Wayland screen capture on KDE Plasma 6:
 *  - Instant still & region capture via restricted org.kde.KWin.ScreenShot2 D-Bus pipe
 *  - Composited annotations + OmniShot editor handoff (`omnishot --edit-existing`)
 *  - Full XDG ScreenCast Portal + KPipeWire MP4 region recording & desktop notification
 */
class CaptureCoordinator final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool recording READ isRecording NOTIFY recordingChanged)
    Q_PROPERTY(QString lastStatus READ lastStatus NOTIFY lastStatusChanged)
    Q_PROPERTY(int backdropRevision READ backdropRevision NOTIFY backdropRevisionChanged)

public:
    enum class RecordingPreset {
        Gif,
        Mp4H264,
        WebP,
    };
    Q_ENUM(RecordingPreset)

    explicit CaptureCoordinator(CaptureImageProvider *imageProvider = nullptr, QObject *parent = nullptr);
    ~CaptureCoordinator() override;

    bool isRecording() const noexcept { return m_recording; }
    QString lastStatus() const { return m_lastStatus; }
    int backdropRevision() const noexcept { return m_backdropRevision; }

    void setOutputDirectory(const QString &directory);
    void setAutoCopyEnabled(bool enabled) noexcept { m_autoCopyEnabled = enabled; }

    Q_INVOKABLE void captureWorkspace(bool includeCursor = false);
    Q_INVOKABLE void captureArea(int x, int y, int width, int height, bool includeCursor = false);

    /**
     * Grabs a silent workspace snapshot for the loupe magnifier, updates
     * image://capture/backdrop, and emits regionOverlayRequested().
     */
    Q_INVOKABLE void prepareRegionCapture(bool includeCursor = false);

    /**
     * Captures the selected (x, y, width, height) region with any annotations
     * and opens it directly in the external OmniShot application.
     */
    Q_INVOKABLE void captureToOmniShot(int x,
                                         int y,
                                         int width,
                                         int height,
                                         const QVariantList &annotations,
                                         bool includeCursor = false);

    /**
     * Executes org.kde.KWin.ScreenShot2::CaptureArea for the finalized crop
     * coordinates, composites QML annotations at native resolution, and saves/copies PNG.
     */
    Q_INVOKABLE void finalizeRegionCapture(int x,
                                             int y,
                                             int width,
                                             int height,
                                             const QVariantList &annotations,
                                             bool includeCursor = false,
                                             bool saveToFile = true,
                                             bool copyToClipboard = true);

    Q_INVOKABLE void startRegionRecording(int x, int y, int width, int height);
    Q_INVOKABLE void startRecording(RecordingPreset preset = RecordingPreset::Mp4H264,
                                      const QRect &cropRect = QRect());
    Q_INVOKABLE void stopRecording();

Q_SIGNALS:
    void regionOverlayRequested();
    void captureWorkflowFinished();
    void screenshotCaptured(const QString &savedPath, const QSize &dimensions);
    void captureFailed(const QString &reason);
    void recordingChanged(bool recording);
    void recordingFinished(const QString &outputPath);
    void lastStatusChanged();
    void backdropRevisionChanged();

private Q_SLOTS:
    void onScreenCastResponse(uint response, const QVariantMap &results);

private:
    enum class ShotPurpose {
        SaveAndCopy,
        OverlayBackdrop,
    };

    enum class PortalStep {
        Idle,
        CreateSession,
        SelectSources,
        Start,
    };

    void invokeScreenShot2(const QString &methodName,
                           const QVariantList &leadingArgs,
                           bool includeCursor,
                           ShotPurpose purpose);
    void handleCapturedImage(QImage image);
    void applyAnnotations(QImage &image, const QRect &logicalCrop, const QVariantList &annotations) const;

    void requestPortalScreenCastSession();
    void selectPortalSources();
    void startPortalScreenCast();
    void openPipeWireRemoteAndBegin(quint32 nodeId, const QPoint &streamPos, const QSize &streamSize);
    void closePortalSession();
    void beginPipeWireRecording(uint pipewireFd,
                                quint32 nodeId,
                                const QPoint &streamPos,
                                const QSize &streamSize);
    void finalizeRecordedVideo();
    void notifyRecordingSaved(const QString &outputPath);

    void setStatus(const QString &status);
    QString buildOutputPath(const QString &extension) const;
    QString buildVideoOutputPath(const QString &prefix = QStringLiteral("screencast")) const;

    CaptureImageProvider *m_imageProvider{nullptr};
    PipeWireRecord *m_recorder{nullptr};
    RecordingPreset m_activePreset{RecordingPreset::Mp4H264};
    PortalStep m_portalStep{PortalStep::Idle};
    QRect m_pendingCropRect;
    QRect m_pendingLogicalCrop;
    QPoint m_streamPos{0, 0};
    QSize m_streamSize;
    QVariantList m_pendingAnnotations;
    QString m_portalSessionHandle;
    QString m_activeOutputPath;
    QString m_rawRecordingPath;
    QString m_outputDirectory;
    QString m_lastStatus;
    int m_backdropRevision{0};
    bool m_recording{false};
    bool m_stopRequested{false};
    bool m_croppingInProgress{false};
    bool m_autoCopyEnabled{true};
    bool m_pendingSaveFile{true};
    bool m_pendingCopyClipboard{true};
    bool m_pendingOmniShotHandoff{false};
};

} // namespace catchypills::capture
