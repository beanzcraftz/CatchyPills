#pragma once

#include <QDBusMessage>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace catchypills::media {

/**
 * Asynchronous Session D-Bus controller for org.mpris.MediaPlayer2.Player services.
 * Tracks active playback state, track metadata, and album art URL without blocking
 * the Wayland render loop, backing the SpotiBar-inspired MediaView.
 */
class MprisController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasPlayer READ hasPlayer NOTIFY stateChanged)
    Q_PROPERTY(bool playing READ isPlaying NOTIFY stateChanged)
    Q_PROPERTY(QString playbackStatus READ playbackStatus NOTIFY stateChanged)
    Q_PROPERTY(QString playerName READ playerName NOTIFY stateChanged)
    Q_PROPERTY(QString title READ title NOTIFY stateChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY stateChanged)
    Q_PROPERTY(QString album READ album NOTIFY stateChanged)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY stateChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY stateChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY stateChanged)
    Q_PROPERTY(bool canControl READ canControl NOTIFY stateChanged)

public:
    explicit MprisController(QObject *parent = nullptr);

    bool hasPlayer() const noexcept { return !m_activeService.isEmpty(); }
    bool isPlaying() const noexcept { return m_playbackStatus == QLatin1String("Playing"); }
    QString playbackStatus() const { return m_playbackStatus; }
    QString playerName() const { return m_playerName; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString album() const { return m_album; }
    QString artUrl() const { return m_artUrl; }
    bool canGoNext() const noexcept { return m_canGoNext; }
    bool canGoPrevious() const noexcept { return m_canGoPrevious; }
    bool canControl() const noexcept { return m_canPlay || m_canPause; }

    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void stateChanged();

private Q_SLOTS:
    void onServiceOwnerChanged(const QString &serviceName,
                               const QString &oldOwner,
                               const QString &newOwner);
    void onMprisPropertiesChanged(const QDBusMessage &message);

private:
    void discoverPlayers();
    void selectActiveService(const QString &serviceName);
    void queryPlayerProperties(const QString &serviceName);
    void queryServiceOwner(const QString &serviceName);
    void applyPropertiesMap(const QVariantMap &props);
    void clearPlayerState();
    void invokePlayerMethod(const QString &methodName);

    static QVariantMap demarshalVariantMap(const QVariant &value);
    static QString formatPlayerName(const QString &serviceName);

    QStringList m_availableServices;
    QString m_activeService;
    QString m_activeOwner;
    QString m_playerName;
    QString m_playbackStatus{QStringLiteral("Stopped")};
    QString m_title;
    QString m_artist;
    QString m_album;
    QString m_artUrl;
    bool m_canGoNext{false};
    bool m_canGoPrevious{false};
    bool m_canPlay{false};
    bool m_canPause{false};
};

} // namespace catchypills::media
