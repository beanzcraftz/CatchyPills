#pragma once

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariantList>

class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

namespace catchypills::app {
class ConfigManager;
}

namespace catchypills::weather {

/**
 * Fetches current weather and forecast telemetry from local Home Assistant REST API.
 */
class WeatherController final : public QObject
{
    Q_OBJECT
    // HA telemetry properties
    Q_PROPERTY(QString weatherTemp READ weatherTemp NOTIFY weatherUpdated)
    Q_PROPERTY(QString weatherState READ weatherState NOTIFY weatherUpdated)

    // Backwards-compatible properties
    Q_PROPERTY(QString temperatureText READ temperatureText NOTIFY weatherUpdated)
    Q_PROPERTY(QString conditionIcon READ conditionIcon NOTIFY weatherUpdated)
    Q_PROPERTY(QString conditionSummary READ conditionSummary NOTIFY weatherUpdated)
    Q_PROPERTY(QString lastUpdatedText READ lastUpdatedText NOTIFY weatherUpdated)
    Q_PROPERTY(QVariantList forecastData READ forecastData NOTIFY weatherUpdated)
    Q_PROPERTY(double latitude READ latitude NOTIFY coordinatesChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY coordinatesChanged)
    Q_PROPERTY(bool available READ isAvailable NOTIFY weatherUpdated)

public:
    static constexpr int kPollIntervalMs = 60 * 1000;

    explicit WeatherController(const app::ConfigManager *config = nullptr, QObject *parent = nullptr);
    explicit WeatherController(QObject *parent);

    QString weatherTemp() const { return m_weatherTemp; }
    QString weatherState() const { return m_weatherState; }
    QString temperatureText() const { return m_weatherTemp; }
    QString conditionIcon() const { return m_conditionIcon; }
    QString conditionSummary() const { return m_conditionSummary; }
    QString lastUpdatedText() const { return m_lastUpdatedText; }
    QVariantList forecastData() const { return m_forecastData; }
    double latitude() const noexcept { return m_latitude; }
    double longitude() const noexcept { return m_longitude; }
    bool isAvailable() const noexcept { return m_available; }

    Q_INVOKABLE void setCoordinates(double latitude, double longitude);
    Q_INVOKABLE void refresh(bool force = false);

Q_SIGNALS:
    void weatherUpdated();
    void coordinatesChanged();

private:
    void onReplyFinished(QNetworkReply *reply);
    void fetchForecast();
    QString resolveHaBaseUrl() const;
    QString resolveApiKey() const;
    QString resolveEntityId() const;
    static QString mapHaStateToIcon(const QString &state);
    static QString formatHaState(const QString &state);

    const app::ConfigManager *m_config{nullptr};
    QNetworkAccessManager *m_nam{nullptr};
    QPointer<QNetworkReply> m_activeReply;
    QPointer<QNetworkReply> m_forecastReply;
    QTimer *m_pollTimer{nullptr};
    QDateTime m_lastFetchedAt;
    QVariantList m_forecastData;
    QString m_weatherTemp{QStringLiteral("--°C")};
    QString m_weatherState{QStringLiteral("unavailable")};
    QString m_conditionIcon{QStringLiteral("🌤️")};
    QString m_conditionSummary{QStringLiteral("Unavailable")};
    QString m_lastUpdatedText;
    double m_latitude{-27.82};
    double m_longitude{152.96};
    bool m_available{false};
    bool m_fetchInFlight{false};
};

} // namespace catchypills::weather
