#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

namespace catchypills::weather {

/**
 * Fetches and caches current weather data from Open-Meteo for 30 minutes
 * so expanding/collapsing the Dynamic Island triggers zero redundant network traffic.
 */
class WeatherController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString temperatureText READ temperatureText NOTIFY weatherUpdated)
    Q_PROPERTY(QString conditionIcon READ conditionIcon NOTIFY weatherUpdated)
    Q_PROPERTY(QString conditionSummary READ conditionSummary NOTIFY weatherUpdated)
    Q_PROPERTY(QString lastUpdatedText READ lastUpdatedText NOTIFY weatherUpdated)
    Q_PROPERTY(bool available READ isAvailable NOTIFY weatherUpdated)

public:
    static constexpr int kCacheIntervalMs = 30 * 60 * 1000;

    explicit WeatherController(QObject *parent = nullptr);

    QString temperatureText() const { return m_temperatureText; }
    QString conditionIcon() const { return m_conditionIcon; }
    QString conditionSummary() const { return m_conditionSummary; }
    QString lastUpdatedText() const { return m_lastUpdatedText; }
    bool isAvailable() const noexcept { return m_available; }

    Q_INVOKABLE void refresh(bool force = false);

Q_SIGNALS:
    void weatherUpdated();

private:
    void onReplyFinished(QNetworkReply *reply);
    void mapWeatherCode(int wmoCode, bool isDay, QString &iconOut, QString &labelOut) const;

    QNetworkAccessManager *m_nam{nullptr};
    QTimer *m_refreshTimer{nullptr};
    QDateTime m_lastFetchedAt;
    QString m_temperatureText{QStringLiteral("--°C")};
    QString m_conditionIcon{QStringLiteral("🌤️")};
    QString m_conditionSummary{QStringLiteral("Fetching local weather...")};
    QString m_lastUpdatedText;
    bool m_available{false};
    bool m_fetchInFlight{false};
};

} // namespace catchypills::weather
