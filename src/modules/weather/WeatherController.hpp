#pragma once

#include <QDateTime>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariantList>

class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

namespace catchypills::weather {

/**
 * Fetches and caches current weather and a 7-day daily forecast from Open-Meteo
 * for 30 minutes (or immediately when location coordinates change in Settings).
 */
class WeatherController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString temperatureText READ temperatureText NOTIFY weatherUpdated)
    Q_PROPERTY(QString conditionIcon READ conditionIcon NOTIFY weatherUpdated)
    Q_PROPERTY(QString conditionSummary READ conditionSummary NOTIFY weatherUpdated)
    Q_PROPERTY(QString lastUpdatedText READ lastUpdatedText NOTIFY weatherUpdated)
    Q_PROPERTY(QVariantList forecastData READ forecastData NOTIFY weatherUpdated)
    Q_PROPERTY(double latitude READ latitude NOTIFY coordinatesChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY coordinatesChanged)
    Q_PROPERTY(bool available READ isAvailable NOTIFY weatherUpdated)

public:
    static constexpr int kCacheIntervalMs = 30 * 60 * 1000;

    explicit WeatherController(QObject *parent = nullptr);

    QString temperatureText() const { return m_temperatureText; }
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
    void mapWeatherCode(int wmoCode, bool isDay, QString &iconOut, QString &labelOut) const;

    QNetworkAccessManager *m_nam{nullptr};
    QPointer<QNetworkReply> m_activeReply;
    QTimer *m_refreshTimer{nullptr};
    QDateTime m_lastFetchedAt;
    QVariantList m_forecastData;
    QString m_temperatureText{QStringLiteral("--°C")};
    QString m_conditionIcon{QStringLiteral("🌤️")};
    QString m_conditionSummary{QStringLiteral("Fetching local weather...")};
    QString m_lastUpdatedText;
    double m_latitude{-27.82};
    double m_longitude{152.96};
    bool m_available{false};
    bool m_fetchInFlight{false};
    bool m_initialFetchTriggered{false};
};

} // namespace catchypills::weather
