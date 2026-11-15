#include "WeatherController.hpp"
#include "app/ConfigManager.hpp"

#include <QDate>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>
#include <cmath>

namespace catchypills::weather {

WeatherController::WeatherController(const app::ConfigManager *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_nam(new QNetworkAccessManager(this))
    , m_pollTimer(new QTimer(this))
{
    m_pollTimer->setInterval(kPollIntervalMs);
    connect(m_pollTimer, &QTimer::timeout, this, [this]() {
        refresh(true);
    });
    m_pollTimer->start();

    if (m_config) {
        connect(m_config, &app::ConfigManager::envConfigChanged, this, [this]() {
            refresh(true);
        });
    }

    QTimer::singleShot(200, this, [this]() {
        refresh(true);
    });
}

WeatherController::WeatherController(QObject *parent)
    : WeatherController(nullptr, parent)
{
}

void WeatherController::setCoordinates(double latitude, double longitude)
{
    m_latitude = std::clamp(latitude, -90.0, 90.0);
    m_longitude = std::clamp(longitude, -180.0, 180.0);
    Q_EMIT coordinatesChanged();
}

QString WeatherController::resolveHaBaseUrl() const
{
    QString base;
    if (m_config) {
        base = m_config->envValue(QStringLiteral("WEATHER_HA_URL")).trimmed();
        if (base.isEmpty()) {
            base = m_config->envValue(QStringLiteral("IOT_HA_URL")).trimmed();
        }
        if (base.isEmpty()) {
            base = m_config->envValue(QStringLiteral("IOT_WEBHOOK_BASE")).trimmed();
        }
    }
    if (base.isEmpty()) {
        base = QString::fromUtf8(qgetenv("WEATHER_HA_URL")).trimmed();
    }
    if (base.isEmpty()) {
        base = QString::fromUtf8(qgetenv("IOT_HA_URL")).trimmed();
    }
    if (base.isEmpty()) {
        base = QString::fromUtf8(qgetenv("IOT_WEBHOOK_BASE")).trimmed();
    }
    if (base.isEmpty()) {
        base = QStringLiteral("http://192.168.1.244:8123");
    }
    while (base.endsWith(QLatin1Char('/'))) {
        base.chop(1);
    }
    if (base.endsWith(QLatin1String("/api"), Qt::CaseInsensitive)) {
        base.chop(4);
    }
    return base;
}

QString WeatherController::resolveApiKey() const
{
    QString key;
    if (m_config) {
        key = m_config->envValue(QStringLiteral("WEATHER_API_KEY")).trimmed();
        if (key.isEmpty()) {
            key = m_config->envValue(QStringLiteral("IOT_API_KEY")).trimmed();
        }
        if (key.isEmpty()) {
            key = m_config->envValue(QStringLiteral("IOT_WEBHOOK_TOKEN")).trimmed();
        }
    }
    if (key.isEmpty()) {
        key = QString::fromUtf8(qgetenv("WEATHER_API_KEY")).trimmed();
    }
    if (key.isEmpty()) {
        key = QString::fromUtf8(qgetenv("IOT_API_KEY")).trimmed();
    }
    if (key.isEmpty()) {
        key = QString::fromUtf8(qgetenv("IOT_WEBHOOK_TOKEN")).trimmed();
    }
    return key;
}

QString WeatherController::resolveEntityId() const
{
    QString entity;
    if (m_config) {
        entity = m_config->envValue(QStringLiteral("WEATHER_ENTITY")).trimmed();
    }
    if (entity.isEmpty()) {
        entity = QString::fromUtf8(qgetenv("WEATHER_ENTITY")).trimmed();
    }
    if (entity.isEmpty()) {
        entity = QStringLiteral("weather.home");
    }
    return entity;
}

void WeatherController::refresh(bool force)
{
    Q_UNUSED(force);
    if (m_fetchInFlight) {
        return;
    }

    const QString haBase = resolveHaBaseUrl();
    const QString entityId = resolveEntityId();
    const QUrl url(QStringLiteral("%1/api/states/%2").arg(haBase, entityId));
    if (!url.isValid()) {
        return;
    }

    m_fetchInFlight = true;

    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    const QString token = resolveApiKey();
    if (!token.isEmpty()) {
        request.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(token).toUtf8());
    }

    if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply = nullptr;
    }

    QNetworkReply *reply = m_nam->get(request);
    m_activeReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onReplyFinished(reply);
    });
}

void WeatherController::onReplyFinished(QNetworkReply *reply)
{
    reply->deleteLater();
    if (m_activeReply != reply) {
        return;
    }
    m_activeReply = nullptr;
    m_fetchInFlight = false;

    if (reply->error() != QNetworkReply::NoError) {
        if (!m_available) {
            m_weatherTemp = QStringLiteral("--°C");
            m_weatherState = QStringLiteral("unavailable");
            m_conditionSummary = QStringLiteral("Unavailable");
            Q_EMIT weatherUpdated();
        }
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
    if (!doc.isObject()) {
        return;
    }

    const QJsonObject root = doc.object();
    m_weatherState = root.value(QStringLiteral("state")).toString();

    const QJsonObject attrs = root.value(QStringLiteral("attributes")).toObject();
    if (attrs.contains(QStringLiteral("temperature"))) {
        const double temp = attrs.value(QStringLiteral("temperature")).toDouble(0.0);
        m_weatherTemp = QStringLiteral("%1°C").arg(static_cast<int>(std::lround(temp)));
    } else {
        m_weatherTemp = QStringLiteral("--°C");
    }

    m_available = true;
    m_lastFetchedAt = QDateTime::currentDateTime();
    m_lastUpdatedText = m_lastFetchedAt.toString(QStringLiteral("HH:mm"));

    m_conditionIcon = mapHaStateToIcon(m_weatherState);
    m_conditionSummary = formatHaState(m_weatherState);

    Q_EMIT weatherUpdated();

    fetchForecast();
}

void WeatherController::fetchForecast()
{
    const QString haBase = resolveHaBaseUrl();
    const QString entityId = resolveEntityId();
    const QString token = resolveApiKey();
    const QUrl url(QStringLiteral("%1/api/services/weather/get_forecasts?return_response").arg(haBase));

    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    if (!token.isEmpty()) {
        request.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(token).toUtf8());
    }

    const QJsonObject payload{{QStringLiteral("entity_id"), entityId},
                              {QStringLiteral("type"), QStringLiteral("daily")}};
    const QByteArray body = QJsonDocument(payload).toJson(QJsonDocument::Compact);

    if (m_forecastReply) {
        m_forecastReply->abort();
        m_forecastReply = nullptr;
    }

    QNetworkReply *reply = m_nam->post(request, body);
    m_forecastReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, entityId]() {
        reply->deleteLater();
        if (m_forecastReply != reply) {
            return;
        }
        m_forecastReply = nullptr;

        if (reply->error() != QNetworkReply::NoError) {
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (!doc.isObject()) {
            return;
        }

        const QJsonObject root = doc.object();
        const QJsonObject srvResp = root.value(QStringLiteral("service_response")).toObject();
        const QJsonObject entObj = srvResp.value(entityId).toObject();
        const QJsonArray forecastArr = entObj.value(QStringLiteral("forecast")).toArray();
        if (forecastArr.isEmpty()) {
            return;
        }

        QVariantList nextForecast;
        for (const QJsonValue &val : forecastArr) {
            const QJsonObject dayObj = val.toObject();
            const QString dtStr = dayObj.value(QStringLiteral("datetime")).toString();
            const QDateTime dt = QDateTime::fromString(dtStr, Qt::ISODate);
            const QString dayOfWeek = dt.isValid()
                ? QLocale::c().toString(dt.date(), QStringLiteral("ddd"))
                : dtStr.left(10);
            const QString cond = dayObj.value(QStringLiteral("condition")).toString();
            const int maxT = static_cast<int>(std::lround(dayObj.value(QStringLiteral("temperature")).toDouble(0.0)));
            const int minT = static_cast<int>(std::lround(dayObj.value(QStringLiteral("templow")).toDouble(0.0)));

            QVariantMap entry;
            entry.insert(QStringLiteral("dayOfWeek"), dayOfWeek);
            entry.insert(QStringLiteral("maxTemp"), maxT);
            entry.insert(QStringLiteral("minTemp"), minT);
            entry.insert(QStringLiteral("icon"), mapHaStateToIcon(cond));
            entry.insert(QStringLiteral("condition"), formatHaState(cond));
            nextForecast.append(entry);
        }

        m_forecastData = std::move(nextForecast);
        Q_EMIT weatherUpdated();
    });
}

QString WeatherController::mapHaStateToIcon(const QString &state)
{
    const QString s = state.trimmed().toLower();
    if (s == QLatin1String("sunny") || s == QLatin1String("clear")) {
        return QStringLiteral("☀️");
    }
    if (s == QLatin1String("clear-night")) {
        return QStringLiteral("🌙");
    }
    if (s == QLatin1String("partlycloudy") || s == QLatin1String("partly-cloudy")) {
        return QStringLiteral("⛅");
    }
    if (s == QLatin1String("cloudy") || s == QLatin1String("overcast")) {
        return QStringLiteral("☁️");
    }
    if (s == QLatin1String("rainy") || s == QLatin1String("pouring")) {
        return QStringLiteral("🌧️");
    }
    if (s == QLatin1String("lightning") || s == QLatin1String("lightning-rainy")
        || s == QLatin1String("thunderstorm")) {
        return QStringLiteral("⛈️");
    }
    if (s == QLatin1String("snowy") || s == QLatin1String("snowy-rainy")
        || s == QLatin1String("hail")) {
        return QStringLiteral("🌨️");
    }
    if (s == QLatin1String("fog")) {
        return QStringLiteral("🌫️");
    }
    if (s == QLatin1String("windy") || s == QLatin1String("windy-variant")) {
        return QStringLiteral("💨");
    }
    return QStringLiteral("🌤️");
}

QString WeatherController::formatHaState(const QString &state)
{
    const QString s = state.trimmed().toLower();
    if (s.isEmpty() || s == QLatin1String("unavailable")) {
        return QStringLiteral("Unavailable");
    }
    if (s == QLatin1String("sunny")) return QStringLiteral("Sunny");
    if (s == QLatin1String("clear")) return QStringLiteral("Clear");
    if (s == QLatin1String("clear-night")) return QStringLiteral("Clear Night");
    if (s == QLatin1String("partlycloudy") || s == QLatin1String("partly-cloudy")) {
        return QStringLiteral("Partly Cloudy");
    }
    if (s == QLatin1String("cloudy")) return QStringLiteral("Cloudy");
    if (s == QLatin1String("overcast")) return QStringLiteral("Overcast");
    if (s == QLatin1String("rainy")) return QStringLiteral("Rainy");
    if (s == QLatin1String("pouring")) return QStringLiteral("Heavy Rain");
    if (s == QLatin1String("lightning")) return QStringLiteral("Lightning");
    if (s == QLatin1String("lightning-rainy")) return QStringLiteral("Thunderstorms & Rain");
    if (s == QLatin1String("thunderstorm")) return QStringLiteral("Thunderstorm");
    if (s == QLatin1String("snowy")) return QStringLiteral("Snowy");
    if (s == QLatin1String("snowy-rainy")) return QStringLiteral("Snow & Rain");
    if (s == QLatin1String("hail")) return QStringLiteral("Hail");
    if (s == QLatin1String("fog")) return QStringLiteral("Foggy");
    if (s == QLatin1String("windy") || s == QLatin1String("windy-variant")) return QStringLiteral("Windy");

    return state.at(0).toUpper() + state.mid(1);
}

} // namespace catchypills::weather
