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
constexpr const char *kKnownDeviceIds[] = {
    "office_ac",
    "office_fan",
    "office_outlet",
    "office_lamp",
    "shed_ac",
    "shed_fan",
    "shed_outlet",
    "shed_lights",
    "air_compressor",
    "all_off",
};

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

QString haServiceForDomain(const QString &domain)
{
    if (domain == QLatin1String("scene") || domain == QLatin1String("script")) {
        return QStringLiteral("turn_on");
    }
    if (domain == QLatin1String("button") || domain == QLatin1String("input_button")) {
        return QStringLiteral("press");
    }
    return QStringLiteral("toggle");
}

QString stripTrailingApiSuffix(QString url)
{
    while (url.endsWith(QLatin1Char('/'))) {
        url.chop(1);
    }
    for (const char *suffix : {"/api/webhook", "/api/services", "/api"}) {
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

IoTController::IoTController(const app::ConfigManager *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_nam(new QNetworkAccessManager(this))
{
    m_statusText = isConfigured()
        ? QStringLiteral("Ready to trigger smart devices")
        : QStringLiteral("Set Home Assistant URL in Settings or ~/.config/catchypills/.env");
}

void IoTController::reloadConfig()
{
    m_statusText = isConfigured()
        ? QStringLiteral("Ready to trigger smart devices")
        : QStringLiteral("Set Home Assistant URL in Settings or ~/.config/catchypills/.env");
    Q_EMIT stateChanged();
}

bool IoTController::isConfigured() const
{
    if (!m_config) {
        return false;
    }
    if (!resolveHaBaseUrl().isEmpty()) {
        return true;
    }
    for (const char *id : kKnownDeviceIds) {
        const QString suffix = normalizeEnvSuffix(QString::fromLatin1(id));
        if (!m_config->envValue(QStringLiteral("IOT_WEBHOOK_") + suffix).trimmed().isEmpty()
            || !m_config->envValue(QStringLiteral("IOT_ENTITY_") + suffix).trimmed().isEmpty()) {
            return true;
        }
    }
    return false;
}

QString IoTController::resolveHaBaseUrl() const
{
    if (!m_config) {
        return {};
    }
    QString base = m_config->envValue(QStringLiteral("IOT_HA_URL")).trimmed();
    if (base.isEmpty()) {
        base = m_config->envValue(QStringLiteral("IOT_WEBHOOK_BASE")).trimmed();
    }
    return stripTrailingApiSuffix(base);
}

QString IoTController::resolveEntityId(const QString &deviceId) const
{
    if (!m_config) {
        return {};
    }
    const QString primaryKey = QStringLiteral("IOT_ENTITY_") + normalizeEnvSuffix(deviceId);
    const QString val = m_config->envValue(primaryKey).trimmed();
    if (!val.isEmpty()) {
        return val;
    }

    // Friendly fallbacks for office / shed aliases
    QStringList fallbacks;
    if (deviceId == QLatin1String("office_ac")) {
        fallbacks << QStringLiteral("IOT_ENTITY_SHED_AC") << QStringLiteral("IOT_ENTITY_GREE_AC");
    } else if (deviceId == QLatin1String("office_fan")) {
        fallbacks << QStringLiteral("IOT_ENTITY_ARLEC_FAN") << QStringLiteral("IOT_ENTITY_SHED_FAN");
    } else if (deviceId == QLatin1String("office_outlet")) {
        fallbacks << QStringLiteral("IOT_ENTITY_POWER_OUTLET") << QStringLiteral("IOT_ENTITY_SHED_OUTLET");
    } else if (deviceId == QLatin1String("office_lamp")) {
        fallbacks << QStringLiteral("IOT_ENTITY_LAMP") << QStringLiteral("IOT_ENTITY_OFFICE_LIGHTS")
                  << QStringLiteral("IOT_ENTITY_SHED_LIGHTS");
    }

    for (const QString &alt : fallbacks) {
        const QString altVal = m_config->envValue(alt).trimmed();
        if (!altVal.isEmpty()) {
            return altVal;
        }
    }

    return {};
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

    QUrl url;
    QJsonObject payload;
    QString entityId = resolveEntityId(cleanId);

    if (!entityId.isEmpty()) {
        if (!entityId.contains(QLatin1Char('.'))) {
            const QString defaultDomain = (cleanId.contains(QLatin1String("light")) || cleanId.contains(QLatin1String("lamp")))
                ? QStringLiteral("light")
                : (cleanId.contains(QLatin1String("ac")) || cleanId.contains(QLatin1String("climate")))
                    ? QStringLiteral("climate")
                    : (cleanId.contains(QLatin1String("all_off")) || cleanId.contains(QLatin1String("scene")))
                        ? QStringLiteral("scene")
                        : QStringLiteral("switch");
            entityId = QStringLiteral("%1.%2").arg(defaultDomain, entityId);
        }

        const int dotIdx = entityId.indexOf(QLatin1Char('.'));
        if (dotIdx <= 0 || dotIdx >= entityId.size() - 1) {
            m_statusText = QStringLiteral("Invalid HA entity '%1' (expected domain.name)").arg(entityId);
            Q_EMIT stateChanged();
            return;
        }
        const QString haBase = resolveHaBaseUrl();
        if (haBase.isEmpty()) {
            m_statusText = QStringLiteral("Set Home Assistant URL in Settings or .env");
            Q_EMIT stateChanged();
            return;
        }
        const QString domain = entityId.left(dotIdx).toLower();
        const QString service = haServiceForDomain(domain);
        url = QUrl(QStringLiteral("%1/api/services/%2/%3").arg(haBase, domain, service));
        payload = QJsonObject{{QStringLiteral("entity_id"), entityId}};
    } else {
        const QString specificWebhook = m_config
            ? m_config->envValue(QStringLiteral("IOT_WEBHOOK_") + normalizeEnvSuffix(cleanId)).trimmed()
            : QString();
        const QString base = m_config
            ? m_config->envValue(QStringLiteral("IOT_WEBHOOK_BASE")).trimmed()
            : QString();

        bool anyHaEntityConfigured = m_config && !m_config->envValue(QStringLiteral("IOT_HA_URL")).trimmed().isEmpty();
        if (!anyHaEntityConfigured && m_config) {
            for (const char *id : kKnownDeviceIds) {
                if (!resolveEntityId(QString::fromLatin1(id)).isEmpty()) {
                    anyHaEntityConfigured = true;
                    break;
                }
            }
        }

        if (specificWebhook.isEmpty() && anyHaEntityConfigured && !base.contains(QStringLiteral("webhook"), Qt::CaseInsensitive)) {
            m_statusText = QStringLiteral("Map IOT_ENTITY_%1 in Settings").arg(normalizeEnvSuffix(cleanId));
            Q_EMIT stateChanged();
            return;
        }

        const QString urlStr = resolveWebhookUrl(cleanId);
        url = QUrl(urlStr);
        if (urlStr.isEmpty() || !url.isValid()) {
            m_statusText = QStringLiteral("Set Home Assistant URL or entity in Settings");
            Q_EMIT stateChanged();
            return;
        }
        payload = QJsonObject{{QStringLiteral("deviceId"), cleanId},
                              {QStringLiteral("action"), QStringLiteral("toggle")}};
    }

    if (!url.isValid()) {
        m_statusText = QStringLiteral("Invalid Home Assistant / webhook URL");
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
        const QString detail = statusCode > 0
            ? QStringLiteral("HTTP %1: %2").arg(statusCode).arg(reply->errorString())
            : reply->errorString();
        m_statusText = QStringLiteral("Failed (%1): %2").arg(deviceId, detail);
        qWarning("IoTController: request error for %s (%s): %s",
                 qPrintable(deviceId),
                 qPrintable(reply->url().toString()),
                 qPrintable(detail));
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
