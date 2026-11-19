#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

namespace catchypills::app {
class ConfigManager;
}

namespace catchypills::solar {

/**
 * Polls dual-inverter telemetry JSON from Home Assistant (/api/template) or
 * direct SOLAR_API_URL and surfaces live generation vs. household consumption
 * readouts for the dashboard header.
 */
class SolarController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double generationKw READ generationKw NOTIFY telemetryUpdated)
    Q_PROPERTY(double consumptionKw READ consumptionKw NOTIFY telemetryUpdated)
    Q_PROPERTY(QString generationText READ generationText NOTIFY telemetryUpdated)
    Q_PROPERTY(QString consumptionText READ consumptionText NOTIFY telemetryUpdated)
    Q_PROPERTY(double dailyGenerationKwh READ dailyGenerationKwh NOTIFY telemetryUpdated)
    Q_PROPERTY(double dailyConsumptionKwh READ dailyConsumptionKwh NOTIFY telemetryUpdated)
    Q_PROPERTY(QString dailyGenerationText READ dailyGenerationText NOTIFY telemetryUpdated)
    Q_PROPERTY(QString dailyConsumptionText READ dailyConsumptionText NOTIFY telemetryUpdated)
    Q_PROPERTY(double netKw READ netKw NOTIFY telemetryUpdated)
    Q_PROPERTY(QString netText READ netText NOTIFY telemetryUpdated)
    Q_PROPERTY(bool exceedingConsumption READ isExceedingConsumption NOTIFY telemetryUpdated)
    Q_PROPERTY(bool available READ isAvailable NOTIFY telemetryUpdated)
    Q_PROPERTY(bool configured READ isConfigured NOTIFY telemetryUpdated)
    Q_PROPERTY(QString lastUpdatedText READ lastUpdatedText NOTIFY telemetryUpdated)
    Q_PROPERTY(int batteryPercentage READ batteryPercentage NOTIFY telemetryUpdated)
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY telemetryUpdated)
    Q_PROPERTY(QString bluettiInputPowerText READ bluettiInputPowerText NOTIFY telemetryUpdated)
    Q_PROPERTY(QString bluettiOutputPowerText READ bluettiOutputPowerText NOTIFY telemetryUpdated)
    Q_PROPERTY(double bluettiInputWatts READ bluettiInputWatts NOTIFY telemetryUpdated)
    Q_PROPERTY(double bluettiOutputWatts READ bluettiOutputWatts NOTIFY telemetryUpdated)
    Q_PROPERTY(bool hasNotifiedPeakSolar READ hasNotifiedPeakSolar NOTIFY telemetryUpdated)
    Q_PROPERTY(QString tomorrowPeakTime READ tomorrowPeakTime NOTIFY telemetryUpdated)
    Q_PROPERTY(QString tomorrowSolarKwh READ tomorrowSolarKwh NOTIFY telemetryUpdated)

public:
    static constexpr int kDefaultPollIntervalMs = 15000;

    explicit SolarController(const app::ConfigManager *config, QObject *parent = nullptr);

    double generationKw() const noexcept { return m_generationKw; }
    double consumptionKw() const noexcept { return m_consumptionKw; }
    QString generationText() const { return m_generationText; }
    QString consumptionText() const { return m_consumptionText; }
    double dailyGenerationKwh() const noexcept { return m_dailyGenerationKwh; }
    double dailyConsumptionKwh() const noexcept { return m_dailyConsumptionKwh; }
    QString dailyGenerationText() const { return m_dailyGenerationText; }
    QString dailyConsumptionText() const { return m_dailyConsumptionText; }
    double netKw() const noexcept { return m_generationKw - m_consumptionKw; }
    QString netText() const { return m_netText; }
    bool isExceedingConsumption() const noexcept { return m_generationKw > m_consumptionKw; }
    bool isAvailable() const noexcept { return m_available; }
    bool isConfigured() const;
    QString lastUpdatedText() const { return m_lastUpdatedText; }
    int batteryPercentage() const noexcept { return m_batteryPercentage; }
    bool hasBattery() const noexcept { return m_hasBattery; }
    QString bluettiInputPowerText() const { return m_bluettiInputPowerText; }
    QString bluettiOutputPowerText() const { return m_bluettiOutputPowerText; }
    double bluettiInputWatts() const noexcept { return m_bluettiInputWatts; }
    double bluettiOutputWatts() const noexcept { return m_bluettiOutputWatts; }
    bool hasNotifiedPeakSolar() const noexcept { return m_hasNotifiedPeakSolar; }
    QString tomorrowPeakTime() const { return m_tomorrowPeakTime; }
    QString tomorrowSolarKwh() const { return m_tomorrowSolarKwh; }

    Q_INVOKABLE void setEnabled(bool enabled);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void reloadConfig();

Q_SIGNALS:
    void telemetryUpdated();

private:
    QString endpointUrl() const;
    QString resolveHaBaseUrl() const;
    QString resolveApiKey() const;
    void onReplyFinished(QNetworkReply *reply);
    void fetchBatteryTelemetry();
    void onBatteryReplyFinished(QNetworkReply *reply);

    const app::ConfigManager *m_config{nullptr};
    QNetworkAccessManager *m_nam{nullptr};
    QPointer<QNetworkReply> m_activeReply;
    QPointer<QNetworkReply> m_batteryReply;
    QTimer *m_pollTimer{nullptr};
    double m_generationKw{0.0};
    double m_consumptionKw{0.0};
    double m_dailyGenerationKwh{0.0};
    double m_dailyConsumptionKwh{0.0};
    QString m_generationText{QStringLiteral("-- kW")};
    QString m_consumptionText{QStringLiteral("-- kW")};
    QString m_dailyGenerationText;
    QString m_dailyConsumptionText;
    QString m_netText{QStringLiteral("0.0 kW")};
    QString m_lastUpdatedText;
    int m_batteryPercentage{100};
    bool m_hasBattery{false};
    bool m_hasNotifiedLowBattery{false};
    bool m_hasNotifiedPeakSolar{false};
    QString m_bluettiInputPowerText{QStringLiteral("In: 0W")};
    QString m_bluettiOutputPowerText{QStringLiteral("Out: 0W")};
    double m_bluettiInputWatts{0.0};
    double m_bluettiOutputWatts{0.0};
    QString m_tomorrowPeakTime{QStringLiteral("--")};
    QString m_tomorrowSolarKwh{QStringLiteral("--")};
    bool m_enabled{false};
    bool m_available{false};
    bool m_fetchInFlight{false};
};

} // namespace catchypills::solar
