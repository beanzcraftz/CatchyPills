#include "DaemonClient.hpp"

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QGuiApplication>
#include <QVariantMap>

QDBusArgument &operator<<(QDBusArgument &arg, const catchypills::core::ClipboardEntryDto &item)
{
    arg.beginStructure();
    arg << item.id << item.kind << item.preview << item.createdAt;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, catchypills::core::ClipboardEntryDto &item)
{
    arg.beginStructure();
    arg >> item.id >> item.kind >> item.preview >> item.createdAt;
    arg.endStructure();
    return arg;
}

QDBusArgument &operator<<(QDBusArgument &arg, const catchypills::core::FileMatchDto &item)
{
    arg.beginStructure();
    arg << item.name << item.path << item.score;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, catchypills::core::FileMatchDto &item)
{
    arg.beginStructure();
    arg >> item.name >> item.path >> item.score;
    arg.endStructure();
    return arg;
}

namespace catchypills::core {

DaemonClient::DaemonClient(QObject *parent)
    : QObject(parent)
{
    qDBusRegisterMetaType<ClipboardEntryDto>();
    qDBusRegisterMetaType<QList<ClipboardEntryDto>>();
    qDBusRegisterMetaType<FileMatchDto>();
    qDBusRegisterMetaType<QList<FileMatchDto>>();

    QDBusConnection::sessionBus().connect(
        QString::fromLatin1(kServiceName),
        QString::fromLatin1(kObjectPath),
        QString::fromLatin1(kInterfaceName),
        QStringLiteral("ClipboardUpdated"),
        this,
        SLOT(onClipboardUpdated(qint64,QString)));

    QDBusConnection::sessionBus().connect(
        QString::fromLatin1(kServiceName),
        QString::fromLatin1(kObjectPath),
        QString::fromLatin1(kInterfaceName),
        QStringLiteral("HtmlClipboardReady"),
        this,
        SLOT(onHtmlClipboardReady(QString)));

    refreshClips();
}

void DaemonClient::onClipboardUpdated(qint64 clipId, const QString &preview)
{
    m_latestClipPreview = preview;
    Q_EMIT latestClipPreviewChanged();
    Q_EMIT clipboardUpdated(clipId, preview);
    refreshClips();
}

void DaemonClient::onHtmlClipboardReady(const QString &htmlText)
{
    Q_EMIT htmlClipboardReady(htmlText);
}

void DaemonClient::refreshClips(int limit)
{
    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kServiceName),
        QString::fromLatin1(kObjectPath),
        QString::fromLatin1(kInterfaceName),
        QStringLiteral("GetRecentClips"));
    msg << static_cast<quint32>(qBound(1, limit, 200));

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QList<ClipboardEntryDto>> reply = *w;
        if (!reply.isValid()) {
            return;
        }

        QVariantList out;
        const auto items = reply.value();
        out.reserve(items.size());
        for (const auto &item : items) {
            out.append(QVariantMap{
                {QStringLiteral("id"), item.id},
                {QStringLiteral("kind"), item.kind},
                {QStringLiteral("preview"), item.preview},
                {QStringLiteral("createdAt"), item.createdAt},
            });
        }
        m_recentClips = out;
        if (!items.isEmpty() && m_latestClipPreview.isEmpty()) {
            m_latestClipPreview = items.first().preview;
            Q_EMIT latestClipPreviewChanged();
        }
        Q_EMIT recentClipsChanged();
    });
}

void DaemonClient::searchFiles(const QString &query, int limit)
{
    const QString trimmed = query.trimmed();
    if (trimmed.isEmpty()) {
        m_searchResults.clear();
        Q_EMIT searchResultsChanged();
        return;
    }

    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kServiceName),
        QString::fromLatin1(kObjectPath),
        QString::fromLatin1(kInterfaceName),
        QStringLiteral("SearchFiles"));
    msg << trimmed << static_cast<quint32>(qBound(1, limit, 200));

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QList<FileMatchDto>> reply = *w;
        if (!reply.isValid()) {
            return;
        }

        QVariantList out;
        const auto matches = reply.value();
        out.reserve(matches.size());
        for (const auto &m : matches) {
            out.append(QVariantMap{
                {QStringLiteral("name"), m.name},
                {QStringLiteral("path"), m.path},
                {QStringLiteral("score"), m.score},
            });
        }
        m_searchResults = out;
        Q_EMIT searchResultsChanged();
    });
}

void DaemonClient::setClipboardPaused(bool paused)
{
    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kServiceName),
        QString::fromLatin1(kObjectPath),
        QString::fromLatin1(kInterfaceName),
        QStringLiteral("SetClipboardPaused"));
    msg << paused;

    QDBusConnection::sessionBus().asyncCall(msg);
}

void DaemonClient::setItsmEnabled(bool enabled)
{
    auto msg = QDBusMessage::createMethodCall(
        QString::fromLatin1(kServiceName),
        QString::fromLatin1(kObjectPath),
        QString::fromLatin1(kInterfaceName),
        QStringLiteral("SetItsmEnabled"));
    msg << enabled;

    QDBusConnection::sessionBus().asyncCall(msg);
}

void DaemonClient::copyClipText(const QString &text)
{
    if (text.isEmpty()) {
        return;
    }
    if (QClipboard *clipboard = QGuiApplication::clipboard()) {
        clipboard->setText(text);
    }
}

} // namespace catchypills::core
