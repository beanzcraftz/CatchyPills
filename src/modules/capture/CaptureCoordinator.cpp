#include "CaptureCoordinator.hpp"

#include <PipeWireRecord>

#include <QBuffer>
#include <QClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QMimeData>
#include <QPainter>
#include <QPen>
#include <QPolygonF>
#include <QStandardPaths>
#include <QUuid>
#include <QVariantMap>

#include <algorithm>
#include <cmath>
#include <fcntl.h>
#include <future>
#include <memory>
#include <thread>
#include <unistd.h>

namespace catchypills::capture {

namespace {
constexpr const char *kKWinShotService = "org.kde.KWin.ScreenShot2";
constexpr const char *kKWinShotPath = "/org/kde/KWin/ScreenShot2";
constexpr const char *kKWinShotIface = "org.kde.KWin.ScreenShot2";

constexpr const char *kPortalService = "org.freedesktop.portal.Desktop";
constexpr const char *kPortalPath = "/org/freedesktop/portal/desktop";
constexpr const char *kScreenCastIface = "org.freedesktop.portal.ScreenCast";
constexpr const char *kRequestIface = "org.freedesktop.portal.Request";
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
}

void CaptureCoordinator::captureWorkspace(bool includeCursor)
{
    m_pendingAnnotations.clear();
    m_pendingLogicalCrop = QRect();
    invokeScreenShot2(QStringLiteral("CaptureWorkspace"), {}, includeCursor, ShotPurpose::SaveAndCopy);
}

void CaptureCoordinator::captureArea(int x, int y, int width, int height, bool includeCursor)
{
    finalizeRegionCapture(x, y, width, height, {}, includeCursor);
}

void CaptureCoordinator::prepareRegionCapture(bool includeCursor)
{
    m_pendingAnnotations.clear();
    m_pendingLogicalCrop = QRect();
    invokeScreenShot2(QStringLiteral("CaptureWorkspace"), {}, includeCursor, ShotPurpose::OverlayBackdrop);
}

void CaptureCoordinator::finalizeRegionCapture(
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
    // Create an anonymous pipe; KWin writes raw BGRA/RGBX pixels into fds[1]
    // while returning width/height/stride/format metadata over D-Bus.
    int fds[2]{-1, -1};
    if (::pipe2(fds, O_CLOEXEC) != 0) {
        Q_EMIT captureFailed(QStringLiteral("Failed to create pipe for ScreenShot2"));
        return;
    }

    QDBusUnixFileDescriptor dbusWriteFd(fds[1]);
    ::close(fds[1]); // Close local write end so EOF arrives when KWin finishes.

    const int readFd = fds[0];

    // Drain the pipe concurrently on a worker future to prevent a 64KB pipe-buffer
    // deadlock on large 3840x1080 (~16.6 MB) captures before KWin returns its D-Bus reply.
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

                // Collect drained pixel bytes off the main thread, then marshal back.
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

    const QString outPath = buildOutputPath(QStringLiteral("png"));
    if (!image.save(outPath, "PNG")) {
        setStatus(QStringLiteral("Failed to write PNG capture"));
        Q_EMIT captureFailed(m_lastStatus);
        return;
    }

    // Automatically publish the capture to the Wayland clipboard when enabled so
    // both catchypillsd (ext_data_control_v1) and paste targets receive it immediately.
    if (m_autoCopyEnabled) {
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

    setStatus(m_autoCopyEnabled
                  ? QStringLiteral("Saved & copied %1x%2")
                        .arg(image.width())
                        .arg(image.height())
                  : QStringLiteral("Saved %1x%2")
                        .arg(image.width())
                        .arg(image.height()));
    Q_EMIT screenshotCaptured(outPath, image.size());
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

void CaptureCoordinator::startRecording(RecordingPreset preset, const QRect &cropRect)
{
    if (m_recording) {
        return;
    }

    m_activePreset = preset;
    m_pendingCropRect = cropRect;

    const QString ext = (preset == RecordingPreset::Gif) ? QStringLiteral("gif")
                      : (preset == RecordingPreset::WebP) ? QStringLiteral("webp")
                                                          : QStringLiteral("mp4");
    m_activeOutputPath = buildOutputPath(ext);

    if (!m_recorder) {
        m_recorder = new PipeWireRecord(this);
        connect(m_recorder, &PipeWireBaseEncodedStream::stateChanged, this, [this]() {
            const auto st = m_recorder->state();
            const bool nowActive = (st == PipeWireBaseEncodedStream::Recording
                                    || st == PipeWireBaseEncodedStream::Paused);
            if (m_recording != nowActive) {
                m_recording = nowActive;
                Q_EMIT recordingChanged(m_recording);
            }
            if (st == PipeWireBaseEncodedStream::Idle && !m_activeOutputPath.isEmpty()) {
                setStatus(QStringLiteral("Recording saved"));
                Q_EMIT recordingFinished(m_activeOutputPath);
            }
        });
        connect(m_recorder, &PipeWireBaseEncodedStream::errorFound, this, [this](const QString &err) {
            m_recording = false;
            Q_EMIT recordingChanged(false);
            setStatus(err);
            Q_EMIT captureFailed(err);
        });
    }

    // Configure KPipeWire encoder presets (GIF uses built-in PipeWireBaseEncodedStream::Gif).
    m_recorder->setOutput(m_activeOutputPath);
    m_recorder->setEncodingPreference(PipeWireBaseEncodedStream::Speed);
    switch (preset) {
    case RecordingPreset::Gif:
        m_recorder->setEncoder(PipeWireBaseEncodedStream::Gif);
        m_recorder->setMaxFramerate(15, 1);
        m_recorder->setQuality(80);
        break;
    case RecordingPreset::WebP:
        m_recorder->setEncoder(PipeWireBaseEncodedStream::WebP);
        m_recorder->setMaxFramerate(20, 1);
        m_recorder->setQuality(80);
        break;
    case RecordingPreset::Mp4H264:
        m_recorder->setEncoder(PipeWireBaseEncodedStream::H264Main);
        m_recorder->setMaxFramerate(60, 1);
        m_recorder->setQuality(85);
        break;
    }

    // Kick off XDG ScreenCast portal handshake to obtain PipeWire remote FD + objectSerial.
    requestPortalScreenCastSession();
}

void CaptureCoordinator::stopRecording()
{
    if (m_recorder && m_recorder->isActive()) {
        setStatus(QStringLiteral("Finalizing recording..."));
        m_recorder->stop();
    }
}

void CaptureCoordinator::requestPortalScreenCastSession()
{
    const QString token = QStringLiteral("cp_%1")
                              .arg(QUuid::createUuid().toString(QUuid::Id128));

    QVariantMap options;
    options.insert(QStringLiteral("handle_token"), token);
    options.insert(QStringLiteral("session_handle_token"), token);

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
        setStatus(QStringLiteral("ScreenCast portal cancelled"));
        return;
    }

    if (results.contains(QStringLiteral("session_handle"))) {
        m_portalSessionHandle = results.value(QStringLiteral("session_handle")).toString();
        setStatus(QStringLiteral("ScreenCast session ready (SelectSources/Start scaffolded)"));
    }
}

void CaptureCoordinator::beginPipeWireRecording(uint pipewireFd, quint64 objectSerial)
{
    if (!m_recorder) {
        return;
    }

    if (m_pendingCropRect.isValid() && !m_pendingCropRect.isEmpty()) {
        m_recorder->setRequestedSize(m_pendingCropRect.size());
    }

    m_recorder->setFd(pipewireFd);
    // KPipeWire 6.4+ prefers PipeWire objectSerial over deprecated setNodeId().
    m_recorder->setObjectSerial(objectSerial);
    m_recorder->start();
    setStatus(QStringLiteral("Recording active"));
}

void CaptureCoordinator::setStatus(const QString &status)
{
    if (m_lastStatus != status) {
        m_lastStatus = status;
        Q_EMIT lastStatusChanged();
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

} // namespace catchypills::capture
