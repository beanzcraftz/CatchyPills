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
#include <cmath>

namespace catchypills::solar {

namespace {

double parseJsonDouble(const QJsonValue &val, double defaultVal = 0.0)
{
    if (val.isDouble()) {
        return val.toDouble();
    }
    if (val.isString()) {
        bool ok = false;
        const double parsed = val.toString().trimmed().toDouble(&ok);
        if (ok) {
            return parsed;
        }
    }
    return defaultVal;
}

QString stripTrailingApiSuffix(QString url)
{
    while (url.endsWith(QLatin1Char('/'))) {
        url.chop(1);
    }
    for (const char *suffix : {"/api/webhook", "/api/services", "/api/template", "/api"}) {
        const QString suffixStr = QString::fromLatin1(suffix);
        if (url.endsWith(suffixStr, Qt::CaseInsensitive)) {
            url.chop(suffixStr.size());
            break;
        }
    }
    while (url.endsWith(QLatin1Char('/'))) {
        url.chop(1);
    }
    return url;
}

} // namespace

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

void SolarController::reloadConfig()
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

    if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply = nullptr;
    }
    m_fetchInFlight = false;

    if (!isConfigured()) {
        m_pollTimer->stop();
        m_available = false;
        m_generationKw = 0.0;
        m_consumptionKw = 0.0;
        m_dailyGenerationKwh = 0.0;
        m_dailyConsumptionKwh = 0.0;
        m_generationText = QStringLiteral("-- kW");
        m_consumptionText = QStringLiteral("-- kW");
        m_dailyGenerationText.clear();
        m_dailyConsumptionText.clear();
        m_netText = QStringLiteral("0.0 kW");
        m_lastUpdatedText.clear();
        Q_EMIT telemetryUpdated();
        return;
    }

    Q_EMIT telemetryUpdated();
    if (m_enabled) {
        refresh();
        if (!m_pollTimer->isActive()) {
            m_pollTimer->start();
        }
    }
}

QString SolarController::endpointUrl() const
{
    if (!m_config) {
        return {};
    }
    return m_config->envValue(QStringLiteral("SOLAR_API_URL")).trimmed();
}

QString SolarController::resolveHaBaseUrl() const
{
    if (!m_config) {
        return {};
    }
    QString base = m_config->envValue(QStringLiteral("SOLAR_API_URL")).trimmed();
    if (base.isEmpty() || !base.startsWith(QLatin1String("http"), Qt::CaseInsensitive)
        || base.contains(QLatin1String(":8123"))) {
        QString haBase = m_config->envValue(QStringLiteral("IOT_HA_URL")).trimmed();
        if (haBase.isEmpty()) {
            haBase = m_config->envValue(QStringLiteral("IOT_WEBHOOK_BASE")).trimmed();
        }
        if (!haBase.isEmpty()) {
            base = haBase;
        }
    }
    return stripTrailingApiSuffix(base);
}

QString SolarController::resolveApiKey() const
{
    if (!m_config) {
        return {};
    }
    QString key = m_config->envValue(QStringLiteral("SOLAR_API_KEY")).trimmed();
    if (key.isEmpty()) {
        key = m_config->envValue(QStringLiteral("IOT_API_KEY")).trimmed();
    }
    return key;
}

bool SolarController::isConfigured() const
{
    if (!m_config) {
        return false;
    }
    if (!m_config->envValue(QStringLiteral("SOLAR_GEN_ENTITY")).trimmed().isEmpty()) {
        return true;
    }
    const QString url = endpointUrl();
    if (!url.isEmpty()) {
        return true;
    }
    return false;
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
    if (!m_enabled || m_fetchInFlight || !m_config) {
        return;
    }

    const QString customApiUrl = endpointUrl();
    const QString genEntity = m_config->envValue(QStringLiteral("SOLAR_GEN_ENTITY")).trimmed();
    const QString loadEntity = m_config->envValue(QStringLiteral("SOLAR_LOAD_ENTITY")).trimmed();
    const QString dailyGenEntity = m_config->envValue(QStringLiteral("SOLAR_DAILY_GEN_ENTITY")).trimmed();
    const QString dailyLoadEntity = m_config->envValue(QStringLiteral("SOLAR_DAILY_LOAD_ENTITY")).trimmed();

    const bool isHaMode = !genEntity.isEmpty()
        || customApiUrl.contains(QLatin1String("/api/template"), Qt::CaseInsensitive)
        || (!customApiUrl.isEmpty() && customApiUrl.contains(QLatin1String(":8123")));

    if (isHaMode) {
        const QString haBase = resolveHaBaseUrl();
        if (haBase.isEmpty()) {
            Q_EMIT telemetryUpdated();
            return;
        }

        const QUrl url(haBase + QStringLiteral("/api/template"));
        if (!url.isValid()) {
            Q_EMIT telemetryUpdated();
            return;
        }

        m_fetchInFlight = true;

        QNetworkRequest request(url);
        request.setTransferTimeout(8000);
        request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));
        request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

        const QString apiKey = resolveApiKey();
        if (!apiKey.isEmpty()) {
            request.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(apiKey).toUtf8());
        }

        const QString activeGen = !genEntity.isEmpty() ? genEntity : QStringLiteral("sensor.beans_residence_plant_power");
        const QString activeLoad = !loadEntity.isEmpty() ? loadEntity : QStringLiteral("sensor.beans_residence_sensor_83128");
        const QString activeDailyGen = !dailyGenEntity.isEmpty() ? dailyGenEntity : QStringLiteral("sensor.beans_residence_daily_yield_of_plant");
        const QString activeDailyLoad = !dailyLoadEntity.isEmpty() ? dailyLoadEntity : QStringLiteral("sensor.beans_residence_daily_load_consumption");

        const QString tmpl = QStringLiteral(
            "{\"current_generation_kw\": {{ (states('%1') | float(0) / (1000 if state_attr('%1', 'unit_of_measurement') == 'W' else 1)) | round(2) }}, "
            "\"household_consumption_kw\": {{ (states('%2') | float(0) / (1000 if state_attr('%2', 'unit_of_measurement') == 'W' else 1)) | round(2) }}, "
            "\"daily_generation_kwh\": {{ (states('%3') | float(0) / (1000 if state_attr('%3', 'unit_of_measurement') == 'Wh' else 1)) | round(1) }}, "
            "\"daily_consumption_kwh\": {{ (states('%4') | float(0) / (1000 if state_attr('%4', 'unit_of_measurement') == 'Wh' else 1)) | round(1) }}}"
        ).arg(activeGen, activeLoad, activeDailyGen, activeDailyLoad);

        QJsonObject bodyObj;
        bodyObj.insert(QStringLiteral("template"), tmpl);
        const QByteArray bodyData = QJsonDocument(bodyObj).toJson(QJsonDocument::Compact);

        QNetworkReply *reply = m_nam->post(request, bodyData);
        m_activeReply = reply;
        connect(reply, &QNetworkReply::finished, this, [this, reply]() {
            onReplyFinished(reply);
        });
        return;
    }

    const QUrl url(customApiUrl);
    if (customApiUrl.isEmpty() || !url.isValid()) {
        Q_EMIT telemetryUpdated();
        return;
    }

    m_fetchInFlight = true;

    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));

    const QString apiKey = resolveApiKey();
    if (!apiKey.isEmpty()) {
        request.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(apiKey).toUtf8());
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

    const QByteArray rawData = reply->readAll();
    const QJsonDocument doc = QJsonDocument::fromJson(rawData);
    if (!doc.isObject()) {
        qWarning("SolarController: response is not a valid JSON object: %s", qPrintable(QString::fromUtf8(rawData).left(200)));
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

    m_generationKw = parseJsonDouble(obj.value(QStringLiteral("current_generation_kw")));
    m_consumptionKw = parseJsonDouble(obj.value(QStringLiteral("household_consumption_kw")));
    m_dailyGenerationKwh = parseJsonDouble(obj.value(QStringLiteral("daily_generation_kwh")));
    m_dailyConsumptionKwh = parseJsonDouble(obj.value(QStringLiteral("daily_consumption_kwh")));

    m_generationText = QStringLiteral("%1 kW").arg(QString::number(m_generationKw, 'f', 1));
    m_consumptionText = QStringLiteral("%1 kW").arg(QString::number(m_consumptionKw, 'f', 1));

    if (m_dailyGenerationKwh > 0.0 || obj.contains(QStringLiteral("daily_generation_kwh"))) {
        m_dailyGenerationText = QStringLiteral("%1 kWh").arg(QString::number(m_dailyGenerationKwh, 'f', 1));
    } else {
        m_dailyGenerationText.clear();
    }

    if (m_dailyConsumptionKwh > 0.0 || obj.contains(QStringLiteral("daily_consumption_kwh"))) {
        m_dailyConsumptionText = QStringLiteral("%1 kWh").arg(QString::number(m_dailyConsumptionKwh, 'f', 1));
    } else {
        m_dailyConsumptionText.clear();
    }

    const double diff = m_generationKw - m_consumptionKw;
    if (diff >= 0.05) {
        m_netText = QStringLiteral("+%1 kW").arg(QString::number(diff, 'f', 1));
    } else if (diff <= -0.05) {
        m_netText = QStringLiteral("%1 kW").arg(QString::number(std::abs(diff), 'f', 1));
    } else {
        m_netText = QStringLiteral("0.0 kW");
    }

    m_available = true;
    m_lastUpdatedText = QTime::currentTime().toString(QStringLiteral("HH:mm:ss"));

    Q_EMIT telemetryUpdated();
}

} // namespace catchypills::solar
