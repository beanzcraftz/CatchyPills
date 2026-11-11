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
 * Triggers smart home and workshop IoT device webhooks read from .env
 * (e.g., IOT_WEBHOOK_BASE or per-device IOT_WEBHOOK_<DEVICE_ID>).
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
    Q_INVOKABLE void reloadConfig();

Q_SIGNALS:
    void stateChanged();

private:
    QString resolveWebhookUrl(const QString &deviceId) const;
    void onReplyFinished(QNetworkReply *reply, const QString &deviceId);

    const app::ConfigManager *m_config{nullptr};
    QNetworkAccessManager *m_nam{nullptr};
    int m_pendingRequests{0};
    QString m_lastTriggeredDevice;
    QString m_statusText;
};

} // namespace catchypills::iot
