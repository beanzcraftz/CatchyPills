#include "CaptureCoordinator.hpp"

#include <PipeWireRecord>

#include <QBuffer>
#include <QClipboard>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMimeData>
#include <QPainter>
#include <QPen>
#include <QPolygonF>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QVariantMap>

#include <algorithm>
#include <cmath>
#include <fcntl.h>
#include <future>
#include <memory>
#include <thread>
#include <unistd.h>

namespace catchypills::capture::detail {

struct PortalFileFilterRule {
    quint32 type{0}; // 0 = glob pattern, 1 = MIME type
    QString pattern;
};

struct PortalFileFilter {
    QString name;
    QList<PortalFileFilterRule> rules;
};

QDBusArgument &operator<<(QDBusArgument &arg, const PortalFileFilterRule &rule)
{
    arg.beginStructure();
    arg << rule.type << rule.pattern;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, PortalFileFilterRule &rule)
{
    arg.beginStructure();
    arg >> rule.type >> rule.pattern;
    arg.endStructure();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const PortalFileFilter &filter)
{
    arg.beginStructure();
    arg << filter.name << filter.rules;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, PortalFileFilter &filter)
{
    arg.beginStructure();
    arg >> filter.name >> filter.rules;
    arg.endStructure();
    return arg;
}

} // namespace catchypills::capture::detail

Q_DECLARE_METATYPE(catchypills::capture::detail::PortalFileFilterRule)
Q_DECLARE_METATYPE(catchypills::capture::detail::PortalFileFilter)

namespace catchypills::capture {

namespace {
constexpr const char *kKWinShotService = "org.kde.KWin.ScreenShot2";
constexpr const char *kKWinShotPath = "/org/kde/KWin/ScreenShot2";
constexpr const char *kKWinShotIface = "org.kde.KWin.ScreenShot2";

constexpr const char *kPortalService = "org.freedesktop.portal.Desktop";
constexpr const char *kPortalPath = "/org/freedesktop/portal/desktop";
constexpr const char *kScreenCastIface = "org.freedesktop.portal.ScreenCast";
constexpr const char *kFileChooserIface = "org.freedesktop.portal.FileChooser";
constexpr const char *kSessionIface = "org.freedesktop.portal.Session";
constexpr const char *kRequestIface = "org.freedesktop.portal.Request";

bool moveFileSafely(const QString &srcPath, const QString &dstPath)
{
    if (srcPath.isEmpty() || dstPath.isEmpty() || !QFileInfo::exists(srcPath)) {
        return false;
    }
    if (QFileInfo::exists(dstPath) && !QFile::remove(dstPath)) {
        return false;
    }
    if (QFile::rename(srcPath, dstPath)) {
        return true;
    }
    // Cross-device fallback (e.g., /tmp tmpfs -> ~/Videos btrfs/ext4).
    if (QFile::copy(srcPath, dstPath)) {
        QFile::remove(srcPath);
        return true;
    }
    return false;
}
} // namespace

CaptureImageProvider::CaptureImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

void CaptureImageProvider::setBackdrop(const QImage &image)
{
    std::scoped_lock lock(m_mutex);
    m_backdrop = image;
}

QImage CaptureImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    Q_UNUSED(id)
    std::scoped_lock lock(m_mutex);
    if (size) {
        *size = m_backdrop.size();
    }
    if (requestedSize.isValid() && !m_backdrop.isNull()) {
        return m_backdrop.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    return m_backdrop;
}

CaptureCoordinator::CaptureCoordinator(CaptureImageProvider *imageProvider, QObject *parent)
    : QObject(parent)
    , m_imageProvider(imageProvider)
{
}

CaptureCoordinator::~CaptureCoordinator()
{
    if (m_recorder && m_recorder->isActive()) {
        m_recorder->stop();
    }
    closePortalSession();
    cleanupRawRecordingFile();
}

void CaptureCoordinator::captureWorkspace(bool includeCursor)
{
    m_pendingAnnotations.clear();
    m_pendingLogicalCrop = QRect();
    m_pendingSaveFile = true;
    m_pendingCopyClipboard = m_autoCopyEnabled;
    m_pendingOmniShotHandoff = false;
    invokeScreenShot2(QStringLiteral("CaptureWorkspace"), {}, includeCursor, ShotPurpose::SaveAndCopy);
}

void CaptureCoordinator::captureArea(int x, int y, int width, int height, bool includeCursor)
{
    finalizeRegionCapture(x, y, width, height, {}, includeCursor, true, m_autoCopyEnabled);
}

void CaptureCoordinator::prepareRegionCapture(bool includeCursor)
{
    m_pendingAnnotations.clear();
    m_pendingLogicalCrop = QRect();
    m_pendingOmniShotHandoff = false;
    invokeScreenShot2(QStringLiteral("CaptureWorkspace"), {}, includeCursor, ShotPurpose::OverlayBackdrop);
}

void CaptureCoordinator::captureToOmniShot(
    int x,
    int y,
    int width,
    int height,
    const QVariantList &annotations,
    bool includeCursor)
{
    if (width <= 0 || height <= 0) {
        Q_EMIT captureFailed(QStringLiteral("Invalid capture area dimensions"));
        return;
    }

    m_pendingLogicalCrop = QRect(x, y, width, height);
    m_pendingAnnotations = annotations;
    m_pendingSaveFile = false;
    m_pendingCopyClipboard = false;
    m_pendingOmniShotHandoff = true;

    const QVariantList args{
        x,
        y,
        static_cast<uint>(width),
        static_cast<uint>(height),
    };
    invokeScreenShot2(QStringLiteral("CaptureArea"), args, includeCursor, ShotPurpose::SaveAndCopy);
}

void CaptureCoordinator::finalizeRegionCapture(
    int x,
    int y,
    int width,
    int height,
    const QVariantList &annotations,
    bool includeCursor,
    bool saveToFile,
    bool copyToClipboard)
{
    if (width <= 0 || height <= 0) {
        Q_EMIT captureFailed(QStringLiteral("Invalid capture area dimensions"));
        return;
    }

    m_pendingLogicalCrop = QRect(x, y, width, height);
    m_pendingAnnotations = annotations;
    m_pendingSaveFile = saveToFile;
    m_pendingCopyClipboard = copyToClipboard;
    m_pendingOmniShotHandoff = false;

    const QVariantList args{
        x,
        y,
        static_cast<uint>(width),
        static_cast<uint>(height),
    };
    invokeScreenShot2(QStringLiteral("CaptureArea"), args, includeCursor, ShotPurpose::SaveAndCopy);
}

void CaptureCoordinator::invokeScreenShot2(
    const QString &methodName,
    const QVariantList &leadingArgs,
    bool includeCursor,
    ShotPurpose purpose)
{
    int fds[2]{-1, -1};
    if (::pipe2(fds, O_CLOEXEC) != 0) {
        Q_EMIT captureFailed(QStringLiteral("Failed to create pipe for ScreenShot2"));
        return;
    }

    QDBusUnixFileDescriptor dbusWriteFd(fds[1]);
    ::close(fds[1]);

    const int readFd = fds[0];

    auto bytesFuture = std::make_shared<std::future<QByteArray>>(
        std::async(std::launch::async, [readFd]() {
            QByteArray buffer;
            char chunk[131072];
            for (;;) {
                const ssize_t n = ::read(readFd, chunk, sizeof(chunk));
                if (n > 0) {
                    buffer.append(chunk, static_cast<qsizetype>(n));
                } else if (n == -1 && errno == EINTR) {
                    continue;
                } else {
                    break;
                }
            }
            ::close(readFd);
            return buffer;
        }));

    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kKWinShotService),
        QString::fromLatin1(kKWinShotPath),
        QString::fromLatin1(kKWinShotIface),
        methodName);

    for (const QVariant &arg : leadingArgs) {
        msg << arg;
    }

    QVariantMap options;
    options.insert(QStringLiteral("include-cursor"), includeCursor);
    options.insert(QStringLiteral("native-resolution"), true);
    msg << options << QVariant::fromValue(dbusWriteFd);

    setStatus(purpose == ShotPurpose::OverlayBackdrop
                  ? QStringLiteral("Preparing region overlay...")
                  : QStringLiteral("Capturing via KWin ScreenShot2..."));

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, bytesFuture, purpose](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                QDBusPendingReply<QVariantMap> reply = *w;
                if (!reply.isValid()) {
                    const QString err = reply.error().message();
                    m_pendingOmniShotHandoff = false;
                    setStatus(err);
                    Q_EMIT captureFailed(err);
                    return;
                }

                const QVariantMap meta = reply.value();
                const int width = meta.value(QStringLiteral("width")).toInt();
                const int height = meta.value(QStringLiteral("height")).toInt();
                const int stride = meta.value(QStringLiteral("stride")).toInt();
                const int fmtCode = meta.value(QStringLiteral("format"),
                                               static_cast<int>(QImage::Format_RGBX8888)).toInt();

                std::thread([this, bytesFuture, purpose, width, height, stride, fmtCode]() {
                    const QByteArray raw = bytesFuture->get();
                    QImage image;
                    const qsizetype expected = static_cast<qsizetype>(stride) * height;

                    if (width > 0 && height > 0 && stride > 0 && raw.size() >= expected) {
                        const auto fmt = (fmtCode > static_cast<int>(QImage::Format_Invalid)
                                          && fmtCode < static_cast<int>(QImage::NImageFormats))
                            ? static_cast<QImage::Format>(fmtCode)
                            : QImage::Format_RGBX8888;
                        image = QImage(reinterpret_cast<const uchar *>(raw.constData()),
                                       width,
                                       height,
                                       stride,
                                       fmt)
                                    .copy();
                    }

                    QMetaObject::invokeMethod(this, [this, image, purpose]() {
                        if (image.isNull()) {
                            m_pendingOmniShotHandoff = false;
                            setStatus(QStringLiteral("Capture returned empty pixel buffer"));
                            Q_EMIT captureFailed(m_lastStatus);
                            return;
                        }
                        if (purpose == ShotPurpose::OverlayBackdrop) {
                            if (m_imageProvider) {
                                m_imageProvider->setBackdrop(image);
                            }
                            ++m_backdropRevision;
                            Q_EMIT backdropRevisionChanged();
                            Q_EMIT regionOverlayRequested();
                            return;
                        }
                        handleCapturedImage(image);
                    }, Qt::QueuedConnection);
                }).detach();
            });
}

void CaptureCoordinator::handleCapturedImage(QImage image)
{
    if (!m_pendingAnnotations.isEmpty()) {
        applyAnnotations(image, m_pendingLogicalCrop, m_pendingAnnotations);
        m_pendingAnnotations.clear();
    }

    if (m_pendingOmniShotHandoff) {
        m_pendingOmniShotHandoff = false;
        const QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
        QDir().mkpath(tempDir);
        const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss_zzz"));
        const QString handoffPath = QStringLiteral("%1/CatchyPills_omnishot_%2.png").arg(tempDir, stamp);

        if (!image.save(handoffPath, "PNG")) {
            setStatus(QStringLiteral("Failed to write OmniShot handoff image"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        // Launch installed OmniShot directly into editor mode with the exact cropped image
        // (`omnishot --edit-existing FILE`; `-r` in omnishot takes no coordinate argument).
        if (!QProcess::startDetached(QStringLiteral("omnishot"),
                                     {QStringLiteral("--edit-existing"), handoffPath})) {
            setStatus(QStringLiteral("Failed to start omnishot"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        setStatus(QStringLiteral("Opened %1x%2 in OmniShot").arg(image.width()).arg(image.height()));
        Q_EMIT screenshotCaptured(handoffPath, image.size());
        Q_EMIT captureWorkflowFinished();
        return;
    }

    QString outPath;
    if (m_pendingSaveFile) {
        outPath = buildOutputPath(QStringLiteral("png"));
        if (!image.save(outPath, "PNG")) {
            setStatus(QStringLiteral("Failed to write PNG capture"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }
    }

    if (m_pendingCopyClipboard) {
        if (QClipboard *clipboard = QGuiApplication::clipboard()) {
            QByteArray pngBytes;
            QBuffer buffer(&pngBytes);
            buffer.open(QIODevice::WriteOnly);
            image.save(&buffer, "PNG");

            auto *mime = new QMimeData();
            mime->setImageData(image);
            mime->setData(QStringLiteral("image/png"), pngBytes);
            clipboard->setMimeData(mime);
        }
    }

    if (m_pendingSaveFile && m_pendingCopyClipboard) {
        setStatus(QStringLiteral("Saved & copied %1x%2").arg(image.width()).arg(image.height()));
    } else if (m_pendingSaveFile) {
        setStatus(QStringLiteral("Saved %1x%2").arg(image.width()).arg(image.height()));
    } else {
        setStatus(QStringLiteral("Copied %1x%2 to clipboard").arg(image.width()).arg(image.height()));
    }
    Q_EMIT screenshotCaptured(outPath, image.size());
    Q_EMIT captureWorkflowFinished();
}

void CaptureCoordinator::applyAnnotations(
    QImage &image,
    const QRect &logicalCrop,
    const QVariantList &annotations) const
{
    if (image.isNull() || annotations.isEmpty()) {
        return;
    }

    const double sx = logicalCrop.width() > 0
        ? static_cast<double>(image.width()) / static_cast<double>(logicalCrop.width())
        : 1.0;
    const double sy = logicalCrop.height() > 0
        ? static_cast<double>(image.height()) / static_cast<double>(logicalCrop.height())
        : 1.0;

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);

    for (const QVariant &entry : annotations) {
        const QVariantMap item = entry.toMap();
        const QString tool = item.value(QStringLiteral("tool")).toString();
        const double x1 = item.value(QStringLiteral("x1")).toDouble() * sx;
        const double y1 = item.value(QStringLiteral("y1")).toDouble() * sy;
        const double x2 = item.value(QStringLiteral("x2")).toDouble() * sx;
        const double y2 = item.value(QStringLiteral("y2")).toDouble() * sy;
        const QColor color(item.value(QStringLiteral("color"), QStringLiteral("#ef4444")).toString());
        const double stroke = item.value(QStringLiteral("strokeWidth"), 3.0).toDouble() * sx;

        if (tool == QStringLiteral("blur")) {
            const int rx = std::clamp(static_cast<int>(std::min(x1, x2)), 0, image.width() - 1);
            const int ry = std::clamp(static_cast<int>(std::min(y1, y2)), 0, image.height() - 1);
            const int rw = std::min(image.width() - rx, static_cast<int>(std::abs(x2 - x1)));
            const int rh = std::min(image.height() - ry, static_cast<int>(std::abs(y2 - y1)));
            if (rw > 4 && rh > 4) {
                const int block = std::max(6, static_cast<int>(10.0 * sx));
                const QImage sub = image.copy(rx, ry, rw, rh);
                const QImage down = sub.scaled(std::max(1, rw / block),
                                               std::max(1, rh / block),
                                               Qt::IgnoreAspectRatio,
                                               Qt::FastTransformation);
                const QImage mosaic = down.scaled(rw, rh, Qt::IgnoreAspectRatio, Qt::FastTransformation);
                painter.drawImage(rx, ry, mosaic);
            }
        } else if (tool == QStringLiteral("rect")) {
            painter.setPen(QPen(color, stroke, Qt::SolidLine, Qt::SquareCap, Qt::MiterJoin));
            painter.setBrush(Qt::NoBrush);
            painter.drawRect(QRectF(QPointF(x1, y1), QPointF(x2, y2)).normalized());
        } else if (tool == QStringLiteral("arrow")) {
            const double dx = x2 - x1;
            const double dy = y2 - y1;
            const double len = std::hypot(dx, dy);
            if (len < 2.0) {
                continue;
            }
            const double angle = std::atan2(dy, dx);
            const double headLen = std::max(12.0 * sx, stroke * 4.0);
            const QPointF p1(x1, y1);
            const QPointF p2(x2, y2);
            const QPointF shaftEnd(x2 - std::cos(angle) * (headLen * 0.72),
                                   y2 - std::sin(angle) * (headLen * 0.72));

            painter.setPen(QPen(color, stroke, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
            painter.drawLine(p1, shaftEnd);

            const QPointF leftWing(x2 - headLen * std::cos(angle - M_PI / 6.0),
                                   y2 - headLen * std::sin(angle - M_PI / 6.0));
            const QPointF rightWing(x2 - headLen * std::cos(angle + M_PI / 6.0),
                                    y2 - headLen * std::sin(angle + M_PI / 6.0));
            painter.setPen(Qt::NoPen);
            painter.setBrush(color);
            painter.drawPolygon(QPolygonF{p2, leftWing, rightWing});
        }
    }
}

void CaptureCoordinator::startRegionRecording(int x, int y, int width, int height)
{
    startRecording(RecordingPreset::Mp4H264, QRect(x, y, width, height));
}

void CaptureCoordinator::startRecording(RecordingPreset preset, const QRect &cropRect)
{
    Q_UNUSED(preset)
    if (m_recording || m_saving || m_saveDialogOpen || m_croppingInProgress || m_portalStep != PortalStep::Idle) {
        return;
    }

    m_activePreset = RecordingPreset::Mp4H264;
    m_pendingCropRect = cropRect;
    m_streamPos = QPoint(0, 0);
    m_streamSize = QSize();
    m_stopRequested = false;

    m_activeOutputPath.clear();
    m_rawRecordingPath = buildTempVideoPath();
    QFile::remove(m_rawRecordingPath);

    if (!m_recorder) {
        m_recorder = new PipeWireRecord(this);
        connect(m_recorder, &PipeWireBaseEncodedStream::stateChanged, this, [this]() {
            if (!m_recorder) {
                return;
            }
            const auto st = m_recorder->state();
            if (st == PipeWireBaseEncodedStream::Idle && m_stopRequested) {
                m_stopRequested = false;
                m_recording = false;
                Q_EMIT recordingChanged(false);
                closePortalSession();
                finalizeRecordedVideo();
            }
        });
        connect(m_recorder, &PipeWireBaseEncodedStream::errorFound, this, [this](const QString &err) {
            m_stopRequested = false;
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaveDialogOpen(false);
            setSaving(false);
            closePortalSession();
            cleanupRawRecordingFile();
            setStatus(err);
            Q_EMIT captureFailed(err);
        });
    }

    m_recorder->setOutput(m_rawRecordingPath);
    m_recorder->setEncodingPreference(PipeWireBaseEncodedStream::Speed);
    m_recorder->setEncoder(PipeWireBaseEncodedStream::H264Main);
    m_recorder->setMaxFramerate(60, 1);
    m_recorder->setQuality(85);

    m_recording = true;
    Q_EMIT recordingChanged(true);

    requestPortalScreenCastSession();
}

void CaptureCoordinator::stopRecording()
{
    if (!m_recording || m_stopRequested || m_saving) {
        return;
    }

    m_stopRequested = true;
    setStatus(QStringLiteral("Saving..."));

    if (m_recorder && m_recorder->isActive()) {
        setSaving(true);
        m_recorder->stop();
    } else if (m_portalStep != PortalStep::Idle) {
        // Portal flow hasn't started the KPipeWire encoder yet.
        m_portalStep = PortalStep::Idle;
        m_stopRequested = false;
        m_recording = false;
        Q_EMIT recordingChanged(false);
        setSaving(false);
        closePortalSession();
        cleanupRawRecordingFile();
        Q_EMIT captureWorkflowFinished();
    } else if (!m_croppingInProgress) {
        m_stopRequested = false;
        m_recording = false;
        Q_EMIT recordingChanged(false);
        setSaving(false);
        closePortalSession();
        cleanupRawRecordingFile();
        Q_EMIT captureWorkflowFinished();
    }
}

void CaptureCoordinator::requestPortalScreenCastSession()
{
    const QString token = QStringLiteral("cp_%1")
                              .arg(QUuid::createUuid().toString(QUuid::Id128));

    QVariantMap options;
    options.insert(QStringLiteral("handle_token"), token);
    options.insert(QStringLiteral("session_handle_token"), token);

    m_portalStep = PortalStep::CreateSession;

    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kPortalService),
        QString::fromLatin1(kPortalPath),
        QString::fromLatin1(kScreenCastIface),
        QStringLiteral("CreateSession"));
    msg << options;

    setStatus(QStringLiteral("Requesting ScreenCast portal session..."));

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath> reply = *w;
        if (!reply.isValid()) {
            m_portalStep = PortalStep::Idle;
            m_stopRequested = false;
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            cleanupRawRecordingFile();
            setStatus(reply.error().message());
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        QDBusConnection::sessionBus().connect(
            QString::fromLatin1(kPortalService),
            reply.value().path(),
            QString::fromLatin1(kRequestIface),
            QStringLiteral("Response"),
            this,
            SLOT(onScreenCastResponse(uint,QVariantMap)));
    });
}

void CaptureCoordinator::selectPortalSources()
{
    const QString token = QStringLiteral("cp_sel_%1")
                              .arg(QUuid::createUuid().toString(QUuid::Id128));

    QVariantMap options;
    options.insert(QStringLiteral("handle_token"), token);
    options.insert(QStringLiteral("types"), static_cast<quint32>(1 | 2)); // Monitor | Window
    options.insert(QStringLiteral("multiple"), false);
    options.insert(QStringLiteral("cursor_mode"), static_cast<quint32>(2)); // Embedded cursor

    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kPortalService),
        QString::fromLatin1(kPortalPath),
        QString::fromLatin1(kScreenCastIface),
        QStringLiteral("SelectSources"));
    msg << QDBusObjectPath(m_portalSessionHandle) << options;

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath> reply = *w;
        if (!reply.isValid()) {
            m_portalStep = PortalStep::Idle;
            m_stopRequested = false;
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            closePortalSession();
            cleanupRawRecordingFile();
            setStatus(reply.error().message());
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        QDBusConnection::sessionBus().connect(
            QString::fromLatin1(kPortalService),
            reply.value().path(),
            QString::fromLatin1(kRequestIface),
            QStringLiteral("Response"),
            this,
            SLOT(onScreenCastResponse(uint,QVariantMap)));
    });
}

void CaptureCoordinator::startPortalScreenCast()
{
    const QString token = QStringLiteral("cp_start_%1")
                              .arg(QUuid::createUuid().toString(QUuid::Id128));

    QVariantMap options;
    options.insert(QStringLiteral("handle_token"), token);

    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kPortalService),
        QString::fromLatin1(kPortalPath),
        QString::fromLatin1(kScreenCastIface),
        QStringLiteral("Start"));
    msg << QDBusObjectPath(m_portalSessionHandle) << QString() << options;

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath> reply = *w;
        if (!reply.isValid()) {
            m_portalStep = PortalStep::Idle;
            m_stopRequested = false;
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            closePortalSession();
            cleanupRawRecordingFile();
            setStatus(reply.error().message());
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        QDBusConnection::sessionBus().connect(
            QString::fromLatin1(kPortalService),
            reply.value().path(),
            QString::fromLatin1(kRequestIface),
            QStringLiteral("Response"),
            this,
            SLOT(onScreenCastResponse(uint,QVariantMap)));
    });
}

void CaptureCoordinator::onScreenCastResponse(uint response, const QVariantMap &results)
{
    if (response != 0) {
        m_portalStep = PortalStep::Idle;
        m_stopRequested = false;
        m_recording = false;
        Q_EMIT recordingChanged(false);
        setSaving(false);
        closePortalSession();
        cleanupRawRecordingFile();
        setStatus(QStringLiteral("ScreenCast portal cancelled"));
        Q_EMIT captureFailed(m_lastStatus);
        return;
    }

    if (m_stopRequested) {
        m_portalStep = PortalStep::Idle;
        m_stopRequested = false;
        m_recording = false;
        Q_EMIT recordingChanged(false);
        setSaving(false);
        closePortalSession();
        cleanupRawRecordingFile();
        Q_EMIT captureWorkflowFinished();
        return;
    }

    if (m_portalStep == PortalStep::CreateSession) {
        m_portalSessionHandle = results.value(QStringLiteral("session_handle")).toString();
        if (m_portalSessionHandle.isEmpty()) {
            m_portalStep = PortalStep::Idle;
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            cleanupRawRecordingFile();
            Q_EMIT captureFailed(QStringLiteral("Empty ScreenCast session handle"));
            return;
        }
        m_portalStep = PortalStep::SelectSources;
        selectPortalSources();
        return;
    }

    if (m_portalStep == PortalStep::SelectSources) {
        m_portalStep = PortalStep::Start;
        startPortalScreenCast();
        return;
    }

    if (m_portalStep == PortalStep::Start) {
        m_portalStep = PortalStep::Idle;

        quint32 nodeId = 0;
        QPoint streamPos(0, 0);
        QSize streamSize;

        if (results.contains(QStringLiteral("streams"))) {
            const QDBusArgument streamsArg = results.value(QStringLiteral("streams")).value<QDBusArgument>();
            streamsArg.beginArray();
            if (!streamsArg.atEnd()) {
                QVariantMap props;
                streamsArg.beginStructure();
                streamsArg >> nodeId >> props;
                streamsArg.endStructure();

                if (props.contains(QStringLiteral("position"))) {
                    const QDBusArgument posArg = props.value(QStringLiteral("position")).value<QDBusArgument>();
                    qint32 px = 0;
                    qint32 py = 0;
                    posArg.beginStructure();
                    posArg >> px >> py;
                    posArg.endStructure();
                    streamPos = QPoint(px, py);
                }
                if (props.contains(QStringLiteral("size"))) {
                    const QDBusArgument sizeArg = props.value(QStringLiteral("size")).value<QDBusArgument>();
                    qint32 sw = 0;
                    qint32 sh = 0;
                    sizeArg.beginStructure();
                    sizeArg >> sw >> sh;
                    sizeArg.endStructure();
                    streamSize = QSize(sw, sh);
                }
            }
            streamsArg.endArray();
        }

        if (nodeId == 0) {
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            closePortalSession();
            cleanupRawRecordingFile();
            setStatus(QStringLiteral("ScreenCast returned no active stream"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        openPipeWireRemoteAndBegin(nodeId, streamPos, streamSize);
    }
}

void CaptureCoordinator::openPipeWireRemoteAndBegin(
    quint32 nodeId,
    const QPoint &streamPos,
    const QSize &streamSize)
{
    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kPortalService),
        QString::fromLatin1(kPortalPath),
        QString::fromLatin1(kScreenCastIface),
        QStringLiteral("OpenPipeWireRemote"));
    msg << QDBusObjectPath(m_portalSessionHandle) << QVariantMap{};

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, [this, nodeId, streamPos, streamSize](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusUnixFileDescriptor> reply = *w;
        if (!reply.isValid() || !reply.value().isValid()) {
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            closePortalSession();
            cleanupRawRecordingFile();
            const QString err = reply.isValid()
                ? QStringLiteral("Invalid PipeWire file descriptor")
                : reply.error().message();
            setStatus(err);
            Q_EMIT captureFailed(err);
            return;
        }

        const int dupFd = ::fcntl(reply.value().fileDescriptor(), F_DUPFD_CLOEXEC, 0);
        if (dupFd < 0) {
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            closePortalSession();
            cleanupRawRecordingFile();
            setStatus(QStringLiteral("Failed to duplicate PipeWire FD"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        if (m_stopRequested) {
            ::close(dupFd);
            m_stopRequested = false;
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setSaving(false);
            closePortalSession();
            cleanupRawRecordingFile();
            Q_EMIT captureWorkflowFinished();
            return;
        }

        beginPipeWireRecording(static_cast<uint>(dupFd), nodeId, streamPos, streamSize);
    });
}

void CaptureCoordinator::closePortalSession()
{
    if (m_portalSessionHandle.isEmpty()) {
        return;
    }

    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kPortalService),
        m_portalSessionHandle,
        QString::fromLatin1(kSessionIface),
        QStringLiteral("Close"));
    QDBusConnection::sessionBus().asyncCall(msg);
    m_portalSessionHandle.clear();
}

void CaptureCoordinator::beginPipeWireRecording(
    uint pipewireFd,
    quint32 nodeId,
    const QPoint &streamPos,
    const QSize &streamSize)
{
    if (!m_recorder) {
        ::close(static_cast<int>(pipewireFd));
        return;
    }

    m_streamPos = streamPos;
    m_streamSize = streamSize;

    m_recorder->setFd(pipewireFd);
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    m_recorder->setNodeId(nodeId);
    QT_WARNING_POP
    m_recorder->start();
    setStatus(QStringLiteral("Recording MP4"));
}

void CaptureCoordinator::finalizeRecordedVideo()
{
    m_recording = false;
    Q_EMIT recordingChanged(false);

    if (m_rawRecordingPath.isEmpty()
        || !QFileInfo::exists(m_rawRecordingPath)
        || QFileInfo(m_rawRecordingPath).size() <= 0) {
        cleanupRawRecordingFile();
        setSaveDialogOpen(false);
        setSaving(false);
        setStatus(QStringLiteral("No video frames recorded"));
        Q_EMIT captureFailed(m_lastStatus);
        return;
    }

    promptSaveRecordingDialog();
}

void CaptureCoordinator::promptSaveRecordingDialog()
{
    setSaving(true);
    setStatus(QStringLiteral("Saving..."));
    setSaveDialogOpen(true);

    const QString defaultDir = defaultVideoDirectory();
    const QString defaultName = defaultVideoFilename();
    const QString defaultFilePath = QStringLiteral("%1/%2").arg(defaultDir, defaultName);

    qDBusRegisterMetaType<detail::PortalFileFilterRule>();
    qDBusRegisterMetaType<QList<detail::PortalFileFilterRule>>();
    qDBusRegisterMetaType<detail::PortalFileFilter>();
    qDBusRegisterMetaType<QList<detail::PortalFileFilter>>();

    const detail::PortalFileFilter mp4Filter{
        QStringLiteral("MP4 Video (*.mp4)"),
        {detail::PortalFileFilterRule{0U, QStringLiteral("*.mp4")}},
    };
    const detail::PortalFileFilter allFilter{
        QStringLiteral("All Files (*)"),
        {detail::PortalFileFilterRule{0U, QStringLiteral("*")}},
    };

    const QString token = QStringLiteral("cp_save_%1")
                              .arg(QUuid::createUuid().toString(QUuid::Id128));

    QString sender = QDBusConnection::sessionBus().baseService();
    sender.replace(QLatin1Char('.'), QLatin1Char('_'));
    sender.remove(QLatin1Char(':'));
    if (!m_fileChooserRequestPath.isEmpty()) {
        QDBusConnection::sessionBus().disconnect(
            QString::fromLatin1(kPortalService),
            m_fileChooserRequestPath,
            QString::fromLatin1(kRequestIface),
            QStringLiteral("Response"),
            this,
            SLOT(onFileChooserResponse(uint,QVariantMap)));
        m_fileChooserRequestPath.clear();
    }

    if (!sender.isEmpty()) {
        m_fileChooserRequestPath = QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2")
                                       .arg(sender, token);
        QDBusConnection::sessionBus().connect(
            QString::fromLatin1(kPortalService),
            m_fileChooserRequestPath,
            QString::fromLatin1(kRequestIface),
            QStringLiteral("Response"),
            this,
            SLOT(onFileChooserResponse(uint,QVariantMap)));
    }

    QByteArray encodedFolder = QFile::encodeName(defaultDir);
    encodedFolder.append('\0');

    QVariantMap options;
    options.insert(QStringLiteral("handle_token"), token);
    options.insert(QStringLiteral("accept_label"), QStringLiteral("Save"));
    options.insert(QStringLiteral("modal"), false);
    options.insert(QStringLiteral("current_name"), defaultName);
    options.insert(QStringLiteral("current_folder"), encodedFolder);
    options.insert(QStringLiteral("filters"),
                   QVariant::fromValue(QList<detail::PortalFileFilter>{mp4Filter, allFilter}));
    options.insert(QStringLiteral("current_filter"), QVariant::fromValue(mp4Filter));

    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kPortalService),
        QString::fromLatin1(kPortalPath),
        QString::fromLatin1(kFileChooserIface),
        QStringLiteral("SaveFile"));
    msg << QString() << QStringLiteral("Save MP4 Recording") << options;

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, [this, defaultFilePath](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QDBusObjectPath> reply = *w;
        if (!reply.isValid()) {
            if (!m_fileChooserRequestPath.isEmpty()) {
                QDBusConnection::sessionBus().disconnect(
                    QString::fromLatin1(kPortalService),
                    m_fileChooserRequestPath,
                    QString::fromLatin1(kRequestIface),
                    QStringLiteral("Response"),
                    this,
                    SLOT(onFileChooserResponse(uint,QVariantMap)));
                m_fileChooserRequestPath.clear();
            }
            openFallbackSaveDialog(defaultFilePath);
            return;
        }

        const QString actualPath = reply.value().path();
        if (!actualPath.isEmpty() && actualPath != m_fileChooserRequestPath) {
            if (!m_fileChooserRequestPath.isEmpty()) {
                QDBusConnection::sessionBus().disconnect(
                    QString::fromLatin1(kPortalService),
                    m_fileChooserRequestPath,
                    QString::fromLatin1(kRequestIface),
                    QStringLiteral("Response"),
                    this,
                    SLOT(onFileChooserResponse(uint,QVariantMap)));
            }
            m_fileChooserRequestPath = actualPath;
            QDBusConnection::sessionBus().connect(
                QString::fromLatin1(kPortalService),
                m_fileChooserRequestPath,
                QString::fromLatin1(kRequestIface),
                QStringLiteral("Response"),
                this,
                SLOT(onFileChooserResponse(uint,QVariantMap)));
        }
    });
}

void CaptureCoordinator::onFileChooserResponse(uint response, const QVariantMap &results)
{
    if (!m_saveDialogOpen && m_fileChooserRequestPath.isEmpty()) {
        return;
    }

    if (!m_fileChooserRequestPath.isEmpty()) {
        QDBusConnection::sessionBus().disconnect(
            QString::fromLatin1(kPortalService),
            m_fileChooserRequestPath,
            QString::fromLatin1(kRequestIface),
            QStringLiteral("Response"),
            this,
            SLOT(onFileChooserResponse(uint,QVariantMap)));
        m_fileChooserRequestPath.clear();
    }

    setSaveDialogOpen(false);

    if (response != 0) {
        cancelPendingSave();
        return;
    }

    const QStringList uris = results.value(QStringLiteral("uris")).toStringList();
    if (uris.isEmpty()) {
        cancelPendingSave();
        return;
    }

    const QString localPath = QUrl(uris.constFirst()).toLocalFile().trimmed();
    if (localPath.isEmpty()) {
        cancelPendingSave();
        return;
    }

    processRecordedVideoToDestination(localPath);
}

void CaptureCoordinator::openFallbackSaveDialog(const QString &defaultFilePath)
{
    auto *dialog = new QFileDialog(nullptr,
                                   QStringLiteral("Save MP4 Recording"),
                                   defaultFilePath,
                                   QStringLiteral("MP4 Video (*.mp4);;All Files (*)"));
    dialog->setAcceptMode(QFileDialog::AcceptSave);
    dialog->setFileMode(QFileDialog::AnyFile);
    dialog->setDefaultSuffix(QStringLiteral("mp4"));
    dialog->setAttribute(Qt::WA_DeleteOnClose);
    dialog->setWindowModality(Qt::NonModal);

    connect(dialog, &QFileDialog::finished, this, [this, dialog](int result) {
        setSaveDialogOpen(false);
        const QStringList files = dialog->selectedFiles();
        if (result != QDialog::Accepted || files.isEmpty() || files.constFirst().trimmed().isEmpty()) {
            cancelPendingSave();
            return;
        }
        processRecordedVideoToDestination(files.constFirst().trimmed());
    });

    dialog->open();
}

void CaptureCoordinator::processRecordedVideoToDestination(const QString &destinationPath)
{
    const QString destPath = destinationPath.trimmed();
    if (destPath.isEmpty()) {
        cancelPendingSave();
        return;
    }

    if (m_rawRecordingPath.isEmpty() || !QFileInfo::exists(m_rawRecordingPath)) {
        cleanupRawRecordingFile();
        setSaving(false);
        setStatus(QStringLiteral("Recorded stream file missing"));
        Q_EMIT captureFailed(m_lastStatus);
        return;
    }

    QFileInfo(destPath).dir().mkpath(QStringLiteral("."));
    m_activeOutputPath = destPath;

    const bool hasCrop = m_pendingCropRect.isValid()
                         && m_pendingCropRect.width() >= 8
                         && m_pendingCropRect.height() >= 8;

    int cx = std::max(0, m_pendingCropRect.x() - m_streamPos.x());
    int cy = std::max(0, m_pendingCropRect.y() - m_streamPos.y());
    int cw = m_pendingCropRect.width() & ~1;
    int ch = m_pendingCropRect.height() & ~1;

    if (m_streamSize.isValid() && !m_streamSize.isEmpty()) {
        cx = std::clamp(cx, 0, std::max(0, m_streamSize.width() - 2));
        cy = std::clamp(cy, 0, std::max(0, m_streamSize.height() - 2));
        cw = std::min(cw, (m_streamSize.width() - cx) & ~1);
        ch = std::min(ch, (m_streamSize.height() - cy) & ~1);
    }

    const QString ffmpegBin = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"));
    if (!hasCrop || cw < 8 || ch < 8 || ffmpegBin.isEmpty()) {
        const bool moved = moveFileSafely(m_rawRecordingPath, m_activeOutputPath);
        cleanupRawRecordingFile();
        setSaving(false);
        if (!moved) {
            setStatus(QStringLiteral("Failed to write MP4 recording"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }
        notifyRecordingSaved(m_activeOutputPath);
        Q_EMIT recordingFinished(m_activeOutputPath);
        Q_EMIT captureWorkflowFinished();
        return;
    }

    m_croppingInProgress = true;
    setStatus(QStringLiteral("Saving..."));
    const QString filter = QStringLiteral(
        "crop='trunc(min(iw-%1,%2)/2)*2':'trunc(min(ih-%3,%4)/2)*2':'min(%1,iw-2)':'min(%3,ih-2)'")
        .arg(cx)
        .arg(cw)
        .arg(cy)
        .arg(ch);

    auto *proc = new QProcess(this);
    auto completed = std::make_shared<bool>(false);

    connect(proc, &QProcess::errorOccurred, this, [this, proc, completed](QProcess::ProcessError) {
        if (*completed) {
            return;
        }
        *completed = true;
        proc->deleteLater();
        m_croppingInProgress = false;

        const bool moved = moveFileSafely(m_rawRecordingPath, m_activeOutputPath);
        cleanupRawRecordingFile();
        setSaving(false);
        if (!moved) {
            setStatus(QStringLiteral("Failed to encode MP4 recording"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }
        notifyRecordingSaved(m_activeOutputPath);
        Q_EMIT recordingFinished(m_activeOutputPath);
        Q_EMIT captureWorkflowFinished();
    });

    connect(proc, &QProcess::finished, this, [this, proc, completed](int exitCode, QProcess::ExitStatus status) {
        if (*completed) {
            return;
        }
        *completed = true;
        proc->deleteLater();
        m_croppingInProgress = false;

        bool ok = (status == QProcess::NormalExit && exitCode == 0 && QFileInfo::exists(m_activeOutputPath));
        if (!ok) {
            QFile::remove(m_activeOutputPath);
            ok = moveFileSafely(m_rawRecordingPath, m_activeOutputPath);
        }
        cleanupRawRecordingFile();
        setSaving(false);

        if (!ok) {
            setStatus(QStringLiteral("Failed to save cropped MP4 recording"));
            Q_EMIT captureFailed(m_lastStatus);
            return;
        }

        notifyRecordingSaved(m_activeOutputPath);
        Q_EMIT recordingFinished(m_activeOutputPath);
        Q_EMIT captureWorkflowFinished();
    });

    proc->start(ffmpegBin, {
        QStringLiteral("-y"),
        QStringLiteral("-i"), m_rawRecordingPath,
        QStringLiteral("-vf"), filter,
        QStringLiteral("-c:v"), QStringLiteral("libx264"),
        QStringLiteral("-preset"), QStringLiteral("veryfast"),
        QStringLiteral("-crf"), QStringLiteral("18"),
        QStringLiteral("-pix_fmt"), QStringLiteral("yuv420p"),
        QStringLiteral("-movflags"), QStringLiteral("+faststart"),
        QStringLiteral("-f"), QStringLiteral("mp4"),
        m_activeOutputPath,
    });
}

void CaptureCoordinator::cancelPendingSave()
{
    cleanupRawRecordingFile();
    m_activeOutputPath.clear();
    setSaveDialogOpen(false);
    setSaving(false);
    setStatus(QStringLiteral("Recording discarded"));
    Q_EMIT captureWorkflowFinished();
}

void CaptureCoordinator::cleanupRawRecordingFile()
{
    if (!m_rawRecordingPath.isEmpty()) {
        QFile::remove(m_rawRecordingPath);
        m_rawRecordingPath.clear();
    }
}

void CaptureCoordinator::notifyRecordingSaved(const QString &outputPath)
{
    const QFileInfo info(outputPath);
    const QString folderPath = info.absolutePath();
    const QString fileName = info.fileName();
    setStatus(QStringLiteral("Saved to %1").arg(folderPath));
    const QString msg = QStringLiteral("Saved %1 in %2").arg(fileName, folderPath);
    QProcess::startDetached(QStringLiteral("notify-send"), {
        QStringLiteral("-a"), QStringLiteral("CatchyPills"),
        QStringLiteral("-i"), QStringLiteral("video-x-generic"),
        QStringLiteral("CatchyPills"),
        msg,
    });
}

void CaptureCoordinator::setStatus(const QString &status)
{
    if (m_lastStatus != status) {
        m_lastStatus = status;
        Q_EMIT lastStatusChanged();
    }
}

void CaptureCoordinator::setSaving(bool saving)
{
    if (m_saving != saving) {
        m_saving = saving;
        Q_EMIT savingChanged(m_saving);
    }
}

void CaptureCoordinator::setSaveDialogOpen(bool open)
{
    if (m_saveDialogOpen != open) {
        m_saveDialogOpen = open;
        Q_EMIT saveDialogOpenChanged(m_saveDialogOpen);
    }
}

void CaptureCoordinator::setOutputDirectory(const QString &directory)
{
    m_outputDirectory = directory.trimmed();
}

QString CaptureCoordinator::buildOutputPath(const QString &extension) const
{
    const QString baseDir = m_outputDirectory.isEmpty()
        ? (QStandardPaths::writableLocation(QStandardPaths::PicturesLocation)
           + QStringLiteral("/Screenshots"))
        : m_outputDirectory;
    QDir().mkpath(baseDir);
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
    return QStringLiteral("%1/CatchyPills_%2.%3").arg(baseDir, stamp, extension);
}

QString CaptureCoordinator::buildTempVideoPath() const
{
    const QString tmpRoot = QFileInfo(QStringLiteral("/tmp")).isWritable()
        ? QStringLiteral("/tmp")
        : QDir::tempPath();
    return QStringLiteral("%1/catchypills_raw_screencast.mp4").arg(tmpRoot);
}

QString CaptureCoordinator::defaultVideoDirectory() const
{
    QString baseDir = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    if (baseDir.isEmpty()) {
        baseDir = QDir::homePath() + QStringLiteral("/Videos");
    }
    QDir().mkpath(baseDir);
    return baseDir;
}

QString CaptureCoordinator::defaultVideoFilename() const
{
    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
    return QStringLiteral("screencast_%1.mp4").arg(stamp);
}

} // namespace catchypills::capture
