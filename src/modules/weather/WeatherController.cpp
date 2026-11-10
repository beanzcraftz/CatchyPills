#include "WeatherController.hpp"

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

WeatherController::WeatherController(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_refreshTimer(new QTimer(this))
{
    m_refreshTimer->setInterval(kCacheIntervalMs);
    connect(m_refreshTimer, &QTimer::timeout, this, [this]() {
        refresh(true);
    });
    m_refreshTimer->start();

    QTimer::singleShot(400, this, [this]() {
        m_initialFetchTriggered = true;
        refresh(true);
    });
}

void WeatherController::setCoordinates(double latitude, double longitude)
{
    const double clampedLat = std::clamp(latitude, -90.0, 90.0);
    const double clampedLon = std::clamp(longitude, -180.0, 180.0);
    const bool changed = (std::abs(m_latitude - clampedLat) >= 1e-6)
                         || (std::abs(m_longitude - clampedLon) >= 1e-6);

    if (!changed && m_initialFetchTriggered) {
        return;
    }

    m_latitude = clampedLat;
    m_longitude = clampedLon;
    m_lastFetchedAt = QDateTime();
    Q_EMIT coordinatesChanged();

    if (m_initialFetchTriggered) {
        if (m_activeReply) {
            m_activeReply->abort();
            m_activeReply = nullptr;
        }
        m_fetchInFlight = false;
        refresh(true);
    }
}

void WeatherController::refresh(bool force)
{
    if (m_fetchInFlight) {
        return;
    }

    if (!force && m_lastFetchedAt.isValid()
        && m_lastFetchedAt.msecsTo(QDateTime::currentDateTime()) < kCacheIntervalMs) {
        return;
    }

    m_initialFetchTriggered = true;
    m_fetchInFlight = true;

    const QString urlStr = QStringLiteral(
        "https://api.open-meteo.com/v1/forecast"
        "?latitude=%1&longitude=%2"
        "&current_weather=true"
        "&daily=weathercode,temperature_2m_max,temperature_2m_min"
        "&timezone=auto")
        .arg(QString::number(m_latitude, 'f', 4),
             QString::number(m_longitude, 'f', 4));

    QNetworkRequest request{QUrl(urlStr)};
    request.setTransferTimeout(10000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.0"));

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
        if (reply->error() != QNetworkReply::OperationCanceledError && !m_available) {
            m_conditionSummary = QStringLiteral("Weather unavailable (retrying automatically)");
            Q_EMIT weatherUpdated();
        }
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
    if (!doc.isObject()) {
        return;
    }

    const QJsonObject root = doc.object();
    const QJsonObject cw = root.value(QStringLiteral("current_weather")).toObject();
    if (cw.isEmpty()) {
        return;
    }

    const double tempC = cw.value(QStringLiteral("temperature")).toDouble(0.0);
    const double windKmh = cw.value(QStringLiteral("windspeed")).toDouble(0.0);
    const int wmoCode = cw.value(QStringLiteral("weathercode")).toInt(-1);
    const bool isDay = cw.value(QStringLiteral("is_day")).toInt(1) != 0;

    QString icon;
    QString desc;
    mapWeatherCode(wmoCode, isDay, icon, desc);

    QVariantList nextForecast;
    const QJsonObject daily = root.value(QStringLiteral("daily")).toObject();
    if (!daily.isEmpty()) {
        const QJsonArray times = daily.value(QStringLiteral("time")).toArray();
        const QJsonArray codes = daily.value(QStringLiteral("weathercode")).toArray();
        const QJsonArray maxTemps = daily.value(QStringLiteral("temperature_2m_max")).toArray();
        const QJsonArray minTemps = daily.value(QStringLiteral("temperature_2m_min")).toArray();

        const qsizetype dayCount = std::min({times.size(), codes.size(), maxTemps.size(), minTemps.size()});
        for (qsizetype i = 0; i < dayCount; ++i) {
            const QString dateStr = times.at(i).toString();
            const QDate date = QDate::fromString(dateStr, Qt::ISODate);
            const QString dayOfWeek = date.isValid()
                ? QLocale::c().toString(date, QStringLiteral("ddd"))
                : dateStr;

            const int dayCode = codes.at(i).toInt(-1);
            const int maxT = static_cast<int>(std::lround(maxTemps.at(i).toDouble(0.0)));
            const int minT = static_cast<int>(std::lround(minTemps.at(i).toDouble(0.0)));

            QString dayIcon;
            QString dayDesc;
            mapWeatherCode(dayCode, true, dayIcon, dayDesc);

            QVariantMap entry;
            entry.insert(QStringLiteral("dayOfWeek"), dayOfWeek);
            entry.insert(QStringLiteral("maxTemp"), maxT);
            entry.insert(QStringLiteral("minTemp"), minT);
            entry.insert(QStringLiteral("icon"), dayIcon);
            entry.insert(QStringLiteral("condition"), dayDesc);
            nextForecast.append(entry);
        }
    }

    m_lastFetchedAt = QDateTime::currentDateTime();
    m_available = true;
    m_forecastData = std::move(nextForecast);
    m_temperatureText = QStringLiteral("%1°C").arg(static_cast<int>(std::lround(tempC)));
    m_conditionIcon = icon;
    m_conditionSummary = QStringLiteral("%1 • %2 • Wind %3 km/h")
                             .arg(desc, m_temperatureText)
                             .arg(static_cast<int>(std::lround(windKmh)));
    m_lastUpdatedText = m_lastFetchedAt.toString(QStringLiteral("HH:mm"));

    Q_EMIT weatherUpdated();
}

void WeatherController::mapWeatherCode(
    int wmoCode,
    bool isDay,
    QString &iconOut,
    QString &labelOut) const
{
    switch (wmoCode) {
    case 0:
        iconOut = isDay ? QStringLiteral("☀️") : QStringLiteral("🌙");
        labelOut = QStringLiteral("Clear sky");
        break;
    case 1:
        iconOut = isDay ? QStringLiteral("🌤️") : QStringLiteral("🌙");
        labelOut = QStringLiteral("Mainly clear");
        break;
    case 2:
        iconOut = QStringLiteral("⛅");
        labelOut = QStringLiteral("Partly cloudy");
        break;
    case 3:
        iconOut = QStringLiteral("☁️");
        labelOut = QStringLiteral("Overcast");
        break;
    case 45:
    case 48:
        iconOut = QStringLiteral("🌫️");
        labelOut = QStringLiteral("Foggy");
        break;
    case 51:
    case 53:
    case 55:
        iconOut = QStringLiteral("🌦️");
        labelOut = QStringLiteral("Drizzle");
        break;
    case 56:
    case 57:
        iconOut = QStringLiteral("🌧️");
        labelOut = QStringLiteral("Freezing drizzle");
        break;
    case 61:
    case 63:
    case 65:
        iconOut = QStringLiteral("🌧️");
        labelOut = QStringLiteral("Rain");
        break;
    case 66:
    case 67:
        iconOut = QStringLiteral("🌧️");
        labelOut = QStringLiteral("Freezing rain");
        break;
    case 71:
    case 73:
    case 75:
    case 77:
        iconOut = QStringLiteral("❄️");
        labelOut = QStringLiteral("Snow");
        break;
    case 80:
    case 81:
    case 82:
        iconOut = QStringLiteral("🌧️");
        labelOut = QStringLiteral("Rain showers");
        break;
    case 85:
    case 86:
        iconOut = QStringLiteral("🌨️");
        labelOut = QStringLiteral("Snow showers");
        break;
    case 95:
        iconOut = QStringLiteral("⛈️");
        labelOut = QStringLiteral("Thunderstorm");
        break;
    case 96:
    case 99:
        iconOut = QStringLiteral("⛈️");
        labelOut = QStringLiteral("Thunderstorm & hail");
        break;
    default:
        iconOut = QStringLiteral("🌡️");
        labelOut = QStringLiteral("Current conditions");
        break;
    }
}

} // namespace catchypills::weather
