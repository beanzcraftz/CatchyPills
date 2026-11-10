#include "MprisController.hpp"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

namespace catchypills::media {

namespace {
constexpr const char *kMprisPrefix = "org.mpris.MediaPlayer2.";
constexpr const char *kMprisPath = "/org/mpris/MediaPlayer2";
constexpr const char *kMprisPlayerIface = "org.mpris.MediaPlayer2.Player";
constexpr const char *kDbusPropsIface = "org.freedesktop.DBus.Properties";
} // namespace

MprisController::MprisController(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        return;
    }

    if (auto *iface = bus.interface()) {
        connect(iface,
                &QDBusConnectionInterface::serviceOwnerChanged,
                this,
                &MprisController::onServiceOwnerChanged);
    }

    bus.connect(QString(),
                QString::fromLatin1(kMprisPath),
                QString::fromLatin1(kDbusPropsIface),
                QStringLiteral("PropertiesChanged"),
                this,
                SLOT(onMprisPropertiesChanged(QDBusMessage)));

    discoverPlayers();
}

void MprisController::playPause()
{
    invokePlayerMethod(QStringLiteral("PlayPause"));
}

void MprisController::next()
{
    invokePlayerMethod(QStringLiteral("Next"));
}

void MprisController::previous()
{
    invokePlayerMethod(QStringLiteral("Previous"));
}

void MprisController::refresh()
{
    discoverPlayers();
}

void MprisController::onServiceOwnerChanged(const QString &serviceName,
                                            const QString &oldOwner,
                                            const QString &newOwner)
{
    if (!serviceName.startsWith(QLatin1String(kMprisPrefix))) {
        return;
    }

    if (!newOwner.isEmpty()) {
        if (!m_availableServices.contains(serviceName)) {
            m_availableServices.append(serviceName);
        }
        if (m_activeService.isEmpty()
            || (!isPlaying() && serviceName.contains(QLatin1String("spotify"), Qt::CaseInsensitive))) {
            selectActiveService(serviceName);
        } else if (m_activeService == serviceName) {
            m_activeOwner = newOwner;
            queryPlayerProperties(serviceName);
        }
    } else if (!oldOwner.isEmpty()) {
        m_availableServices.removeAll(serviceName);
        if (m_activeService == serviceName) {
            clearPlayerState();
            if (!m_availableServices.isEmpty()) {
                selectActiveService(m_availableServices.constFirst());
            } else {
                Q_EMIT stateChanged();
            }
        }
    }
}

void MprisController::onMprisPropertiesChanged(const QDBusMessage &message)
{
    const QList<QVariant> args = message.arguments();
    if (args.size() < 2) {
        return;
    }

    if (args.at(0).toString() != QLatin1String(kMprisPlayerIface)) {
        return;
    }

    const QVariantMap changed = demarshalVariantMap(args.at(1));
    if (changed.isEmpty()) {
        return;
    }

    const QString sender = message.service();
    if (!m_activeOwner.isEmpty() && sender == m_activeOwner) {
        applyPropertiesMap(changed);
        return;
    }

    // If another MPRIS player starts playing while ours is idle, switch to it.
    const QString newStatus = changed.value(QStringLiteral("PlaybackStatus")).toString();
    if (!isPlaying() && newStatus == QLatin1String("Playing")) {
        discoverPlayers();
    }
}

void MprisController::discoverPlayers()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("ListNames"));

    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QStringList> reply = *w;
        if (!reply.isValid()) {
            return;
        }

        m_availableServices.clear();
        QString preferred;
        for (const QString &name : reply.value()) {
            if (!name.startsWith(QLatin1String(kMprisPrefix))) {
                continue;
            }
            m_availableServices.append(name);
            if (preferred.isEmpty() || name.contains(QLatin1String("spotify"), Qt::CaseInsensitive)) {
                preferred = name;
            }
        }

        if (m_availableServices.isEmpty()) {
            if (!m_activeService.isEmpty()) {
                clearPlayerState();
                Q_EMIT stateChanged();
            }
            return;
        }

        if (!m_activeService.isEmpty() && m_availableServices.contains(m_activeService)) {
            queryPlayerProperties(m_activeService);
            if (m_activeOwner.isEmpty()) {
                queryServiceOwner(m_activeService);
            }
        } else {
            selectActiveService(preferred);
        }
    });
}

void MprisController::selectActiveService(const QString &serviceName)
{
    if (serviceName.isEmpty()) {
        clearPlayerState();
        Q_EMIT stateChanged();
        return;
    }

    m_activeService = serviceName;
    m_activeOwner.clear();
    m_playerName = formatPlayerName(serviceName);
    queryServiceOwner(serviceName);
    queryPlayerProperties(serviceName);
    Q_EMIT stateChanged();
}

void MprisController::queryServiceOwner(const QString &serviceName)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"),
        QStringLiteral("GetNameOwner"));
    msg << serviceName;

    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, serviceName](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        QDBusPendingReply<QString> reply = *w;
        if (reply.isValid() && m_activeService == serviceName) {
            m_activeOwner = reply.value();
        }
    });
}

void MprisController::queryPlayerProperties(const QString &serviceName)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(
        serviceName,
        QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kDbusPropsIface),
        QStringLiteral("GetAll"));
    msg << QString::fromLatin1(kMprisPlayerIface);

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, serviceName](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (m_activeService != serviceName) {
            return;
        }
        QDBusPendingReply<QVariantMap> reply = *w;
        if (!reply.isValid()) {
            return;
        }
        applyPropertiesMap(reply.value());
    });
}

void MprisController::applyPropertiesMap(const QVariantMap &props)
{
    bool changed = false;

    if (props.contains(QStringLiteral("PlaybackStatus"))) {
        const QString status = props.value(QStringLiteral("PlaybackStatus")).toString();
        if (m_playbackStatus != status) {
            m_playbackStatus = status;
            changed = true;
        }
    }

    if (props.contains(QStringLiteral("CanGoNext"))) {
        const bool nextAllowed = props.value(QStringLiteral("CanGoNext")).toBool();
        if (m_canGoNext != nextAllowed) {
            m_canGoNext = nextAllowed;
            changed = true;
        }
    }

    if (props.contains(QStringLiteral("CanGoPrevious"))) {
        const bool prevAllowed = props.value(QStringLiteral("CanGoPrevious")).toBool();
        if (m_canGoPrevious != prevAllowed) {
            m_canGoPrevious = prevAllowed;
            changed = true;
        }
    }

    if (props.contains(QStringLiteral("CanPlay"))) {
        const bool playAllowed = props.value(QStringLiteral("CanPlay")).toBool();
        if (m_canPlay != playAllowed) {
            m_canPlay = playAllowed;
            changed = true;
        }
    }

    if (props.contains(QStringLiteral("CanPause"))) {
        const bool pauseAllowed = props.value(QStringLiteral("CanPause")).toBool();
        if (m_canPause != pauseAllowed) {
            m_canPause = pauseAllowed;
            changed = true;
        }
    }

    if (props.contains(QStringLiteral("Metadata"))) {
        const QVariantMap meta = demarshalVariantMap(props.value(QStringLiteral("Metadata")));

        const QString newTitle = meta.value(QStringLiteral("xesam:title")).toString();
        if (m_title != newTitle) {
            m_title = newTitle;
            changed = true;
        }

        QStringList artists;
        const QVariant artistVar = meta.value(QStringLiteral("xesam:artist"));
        if (artistVar.canConvert<QDBusArgument>()) {
            artists = qdbus_cast<QStringList>(artistVar.value<QDBusArgument>());
        } else {
            artists = artistVar.toStringList();
        }
        if (artists.isEmpty() && !artistVar.toString().isEmpty()) {
            artists.append(artistVar.toString());
        }
        const QString newArtist = artists.join(QStringLiteral(", "));
        if (m_artist != newArtist) {
            m_artist = newArtist;
            changed = true;
        }

        const QString newAlbum = meta.value(QStringLiteral("xesam:album")).toString();
        if (m_album != newAlbum) {
            m_album = newAlbum;
            changed = true;
        }

        const QString newArt = meta.value(QStringLiteral("mpris:artUrl")).toString();
        if (m_artUrl != newArt) {
            m_artUrl = newArt;
            changed = true;
        }
    }

    if (changed) {
        Q_EMIT stateChanged();
    }
}

void MprisController::clearPlayerState()
{
    m_activeService.clear();
    m_activeOwner.clear();
    m_playerName.clear();
    m_playbackStatus = QStringLiteral("Stopped");
    m_title.clear();
    m_artist.clear();
    m_album.clear();
    m_artUrl.clear();
    m_canGoNext = false;
    m_canGoPrevious = false;
    m_canPlay = false;
    m_canPause = false;
}

void MprisController::invokePlayerMethod(const QString &methodName)
{
    if (m_activeService.isEmpty()) {
        discoverPlayers();
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        m_activeService,
        QString::fromLatin1(kMprisPath),
        QString::fromLatin1(kMprisPlayerIface),
        methodName);
    QDBusConnection::sessionBus().asyncCall(msg);
}

QVariantMap MprisController::demarshalVariantMap(const QVariant &value)
{
    if (value.canConvert<QDBusArgument>()) {
        return qdbus_cast<QVariantMap>(value.value<QDBusArgument>());
    }
    return value.toMap();
}

QString MprisController::formatPlayerName(const QString &serviceName)
{
    QString name = serviceName.mid(QString::fromLatin1(kMprisPrefix).size());
    const qsizetype instanceIdx = name.indexOf(QStringLiteral(".instance"));
    if (instanceIdx > 0) {
        name = name.left(instanceIdx);
    }
    if (!name.isEmpty()) {
        name[0] = name.at(0).toUpper();
    }
    return name;
}

} // namespace catchypills::media
