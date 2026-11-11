#include "SolarController.hpp"

#include "app/ConfigManager.hpp"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTime>
#include <QTimer>
#include <QUrl>

#include <algorithm>

namespace catchypills::solar {

SolarController::SolarController(const app::ConfigManager *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_nam(new QNetworkAccessManager(this))
    , m_pollTimer(new QTimer(this))
{
    int intervalMs = kDefaultPollIntervalMs;
    if (m_config) {
        bool ok = false;
        const int customMs = m_config->envValue(QStringLiteral("SOLAR_POLL_INTERVAL_MS")).toInt(&ok);
        if (ok && customMs > 0) {
            intervalMs = std::clamp(customMs, 2000, 300000);
        }
    }

    m_pollTimer->setInterval(intervalMs);
    connect(m_pollTimer, &QTimer::timeout, this, &SolarController::refresh);
}

QString SolarController::endpointUrl() const
{
    if (!m_config) {
        return {};
    }
    return m_config->envValue(QStringLiteral("SOLAR_API_URL")).trimmed();
}

bool SolarController::isConfigured() const
{
    return !endpointUrl().isEmpty();
}

void SolarController::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;

    if (!m_enabled) {
        m_pollTimer->stop();
        if (m_activeReply) {
            m_activeReply->abort();
            m_activeReply = nullptr;
        }
        m_fetchInFlight = false;
        return;
    }

    if (isConfigured()) {
        refresh();
        m_pollTimer->start();
    } else {
        Q_EMIT telemetryUpdated();
    }
}

void SolarController::refresh()
{
    if (!m_enabled || m_fetchInFlight) {
        return;
    }

    const QString urlStr = endpointUrl();
    const QUrl url(urlStr);
    if (urlStr.isEmpty() || !url.isValid()) {
        Q_EMIT telemetryUpdated();
        return;
    }

    m_fetchInFlight = true;

    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));

    if (m_config) {
        const QString apiKey = m_config->envValue(QStringLiteral("SOLAR_API_KEY")).trimmed();
        if (!apiKey.isEmpty()) {
            request.setRawHeader("Authorization",
                                 QStringLiteral("Bearer %1").arg(apiKey).toUtf8());
        }
    }

    QNetworkReply *reply = m_nam->get(request);
    m_activeReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onReplyFinished(reply);
    });
}

void SolarController::onReplyFinished(QNetworkReply *reply)
{
    reply->deleteLater();
    if (m_activeReply != reply) {
        m_fetchInFlight = false;
        return;
    }
    m_activeReply = nullptr;
    m_fetchInFlight = false;

    if (reply->error() != QNetworkReply::NoError) {
        qWarning("SolarController: telemetry fetch failed: %s", qPrintable(reply->errorString()));
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
    if (!doc.isObject()) {
        return;
    }

    QJsonObject obj = doc.object();
    if (!obj.contains(QStringLiteral("current_generation_kw"))
        && obj.value(QStringLiteral("data")).isObject()) {
        obj = obj.value(QStringLiteral("data")).toObject();
    }

    if (!obj.contains(QStringLiteral("current_generation_kw"))
        || !obj.contains(QStringLiteral("household_consumption_kw"))) {
        return;
    }

    m_generationKw = obj.value(QStringLiteral("current_generation_kw")).toDouble();
    m_consumptionKw = obj.value(QStringLiteral("household_consumption_kw")).toDouble();
    m_generationText = QStringLiteral("%1 kW").arg(QString::number(m_generationKw, 'f', 1));
    m_consumptionText = QStringLiteral("%1 kW").arg(QString::number(m_consumptionKw, 'f', 1));
    m_available = true;
    m_lastUpdatedText = QTime::currentTime().toString(QStringLiteral("HH:mm:ss"));

    Q_EMIT telemetryUpdated();
}

} // namespace catchypills::solar
