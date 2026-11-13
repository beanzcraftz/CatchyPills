#pragma once

#include <QObject>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;

namespace catchypills::app {
class ConfigManager;
}

namespace catchypills::iot {

/**
 * Triggers smart home and workshop IoT devices read from .env
 * (Home Assistant REST entities via IOT_ENTITY_<DEVICE_ID>, or webhook URLs
 * via IOT_WEBHOOK_BASE / IOT_WEBHOOK_<DEVICE_ID>).
 */
class IoTController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ isBusy NOTIFY stateChanged)
    Q_PROPERTY(bool configured READ isConfigured NOTIFY stateChanged)
    Q_PROPERTY(QString lastTriggeredDevice READ lastTriggeredDevice NOTIFY stateChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)

public:
    explicit IoTController(const app::ConfigManager *config, QObject *parent = nullptr);

    bool isBusy() const noexcept { return m_pendingRequests > 0; }
    bool isConfigured() const;
    QString lastTriggeredDevice() const { return m_lastTriggeredDevice; }
    QString statusText() const { return m_statusText; }

    Q_INVOKABLE void triggerDevice(const QString &deviceId);
    Q_INVOKABLE void setClimateMode(const QString &entityId, const QString &mode);
    Q_INVOKABLE void setClimateTemperature(const QString &entityId, double temperature);
    Q_INVOKABLE void reloadConfig();

Q_SIGNALS:
    void stateChanged();

private:
    QString resolveHaBaseUrl() const;
    QString resolveEntityId(const QString &deviceId) const;
    QString resolveWebhookUrl(const QString &deviceId) const;
    void onReplyFinished(QNetworkReply *reply, const QString &deviceId);

    const app::ConfigManager *m_config{nullptr};
    QNetworkAccessManager *m_nam{nullptr};
    int m_pendingRequests{0};
    QString m_lastTriggeredDevice;
    QString m_statusText;
};

} // namespace catchypills::iot
