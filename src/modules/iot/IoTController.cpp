#include "IoTController.hpp"

#include "app/ConfigManager.hpp"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QUrl>

namespace catchypills::iot {

namespace {
QString normalizeEnvSuffix(const QString &deviceId)
{
    QString out;
    out.reserve(deviceId.size());
    for (const QChar ch : deviceId.trimmed()) {
        if (ch.isLetterOrNumber()) {
            out.append(ch.toUpper());
        } else if (!out.endsWith(QLatin1Char('_'))) {
            out.append(QLatin1Char('_'));
        }
    }
    return out;
}
} // namespace

IoTController::IoTController(const app::ConfigManager *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_nam(new QNetworkAccessManager(this))
{
    m_statusText = isConfigured()
        ? QStringLiteral("Ready to trigger smart devices")
        : QStringLiteral("Set IOT_WEBHOOK_BASE in ~/.config/catchypills/.env");
}

bool IoTController::isConfigured() const
{
    if (!m_config) {
        return false;
    }
    return !m_config->envValue(QStringLiteral("IOT_WEBHOOK_BASE")).trimmed().isEmpty();
}

QString IoTController::resolveWebhookUrl(const QString &deviceId) const
{
    if (!m_config) {
        return {};
    }

    const QString specificKey = QStringLiteral("IOT_WEBHOOK_") + normalizeEnvSuffix(deviceId);
    const QString specificUrl = m_config->envValue(specificKey).trimmed();
    if (!specificUrl.isEmpty()) {
        return specificUrl;
    }

    const QString base = m_config->envValue(QStringLiteral("IOT_WEBHOOK_BASE")).trimmed();
    if (base.isEmpty()) {
        return {};
    }

    const QString encodedId = QString::fromLatin1(QUrl::toPercentEncoding(deviceId));
    if (base.contains(QStringLiteral("{device}"))) {
        QString replaced = base;
        replaced.replace(QStringLiteral("{device}"), encodedId);
        return replaced;
    }
    if (base.contains(QStringLiteral("%1"))) {
        return base.arg(encodedId);
    }
    if (base.endsWith(QLatin1Char('='))) {
        return base + encodedId;
    }
    if (base.contains(QLatin1Char('?'))) {
        return base + QStringLiteral("&device=") + encodedId;
    }
    return (base.endsWith(QLatin1Char('/')) ? base : base + QLatin1Char('/')) + encodedId;
}

void IoTController::triggerDevice(const QString &deviceId)
{
    const QString cleanId = deviceId.trimmed();
    if (cleanId.isEmpty()) {
        return;
    }

    const QString urlStr = resolveWebhookUrl(cleanId);
    const QUrl url(urlStr);
    if (urlStr.isEmpty() || !url.isValid()) {
        m_statusText = QStringLiteral("Missing IOT_WEBHOOK_BASE in .env");
        Q_EMIT stateChanged();
        return;
    }

    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));

    if (m_config) {
        QString token = m_config->envValue(QStringLiteral("IOT_API_KEY")).trimmed();
        if (token.isEmpty()) {
            token = m_config->envValue(QStringLiteral("IOT_WEBHOOK_TOKEN")).trimmed();
        }
        if (!token.isEmpty()) {
            request.setRawHeader("Authorization",
                                 QStringLiteral("Bearer %1").arg(token).toUtf8());
        }
    }

    const QJsonObject payload{{QStringLiteral("deviceId"), cleanId},
                              {QStringLiteral("action"), QStringLiteral("toggle")}};
    const QByteArray body = QJsonDocument(payload).toJson(QJsonDocument::Compact);

    ++m_pendingRequests;
    m_statusText = QStringLiteral("Sending %1 command...").arg(cleanId);
    Q_EMIT stateChanged();

    QNetworkReply *reply = m_nam->post(request, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, cleanId]() {
        onReplyFinished(reply, cleanId);
    });
}

void IoTController::onReplyFinished(QNetworkReply *reply, const QString &deviceId)
{
    reply->deleteLater();
    m_pendingRequests = qMax(0, m_pendingRequests - 1);

    const int statusCode =
        reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

    if (reply->error() != QNetworkReply::NoError
        || (statusCode != 0 && (statusCode < 200 || statusCode >= 300))) {
        m_statusText = QStringLiteral("Failed (%1): %2")
                           .arg(deviceId, reply->errorString());
        qWarning("IoTController: webhook error for %s: %s",
                 qPrintable(deviceId),
                 qPrintable(reply->errorString()));
        Q_EMIT stateChanged();
        return;
    }

    m_lastTriggeredDevice = deviceId;
    m_statusText = QStringLiteral("Toggled %1").arg(deviceId);
    Q_EMIT stateChanged();

    QProcess::startDetached(
        QStringLiteral("notify-send"),
        {QStringLiteral("-a"),
         QStringLiteral("CatchyPills IoT"),
         QStringLiteral("IoT Trigger Sent"),
         QStringLiteral("Toggled device: %1").arg(deviceId)});
}

} // namespace catchypills::iot
