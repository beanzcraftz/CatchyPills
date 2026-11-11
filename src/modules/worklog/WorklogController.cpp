#include "WorklogController.hpp"

#include "app/ConfigManager.hpp"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QUrl>

namespace catchypills::worklog {

namespace {
QString expandHomePrefix(const QString &raw)
{
    const QString trimmed = raw.trimmed();
    if (trimmed == QStringLiteral("~")) {
        return QDir::homePath();
    }
    if (trimmed.startsWith(QStringLiteral("~/"))) {
        return QDir::homePath() + trimmed.mid(1);
    }
    return trimmed;
}
} // namespace

WorklogController::WorklogController(const app::ConfigManager *config, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_nam(new QNetworkAccessManager(this))
    , m_connectionName(QStringLiteral("catchypills_worklog_sqlite"))
{
}

WorklogController::~WorklogController()
{
    if (QSqlDatabase::contains(m_connectionName)) {
        {
            QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
            if (db.isOpen()) {
                db.close();
            }
        }
        QSqlDatabase::removeDatabase(m_connectionName);
    }
}

QString WorklogController::resolvedDbPath() const
{
    if (m_config) {
        const QString configured =
            expandHomePrefix(m_config->envValue(QStringLiteral("WORKLOG_DB_PATH")));
        if (!configured.isEmpty()) {
            return configured;
        }
    }
    const QString dataDir =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/CatchyPills");
    return dataDir + QStringLiteral("/worklog.db3");
}

QString WorklogController::resolvedApiUrl() const
{
    if (!m_config) {
        return {};
    }
    return m_config->envValue(QStringLiteral("WORKLOG_API_URL")).trimmed();
}

bool WorklogController::useHttpApi() const
{
    if (!m_config) {
        return false;
    }
    const bool hasDbOverride =
        !m_config->envValue(QStringLiteral("WORKLOG_DB_PATH")).trimmed().isEmpty();
    return !hasDbOverride && !resolvedApiUrl().isEmpty();
}

void WorklogController::setEnabled(bool enabled)
{
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    if (m_enabled) {
        refresh();
    } else if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply = nullptr;
        m_requestInFlight = false;
    }
}

void WorklogController::refresh()
{
    if (!m_enabled) {
        return;
    }
    if (useHttpApi()) {
        refreshHttpApi();
    } else if (ensureSqliteReady()) {
        loadStateFromSqlite();
    }
}

void WorklogController::reloadConfig()
{
    if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply = nullptr;
    }
    m_requestInFlight = false;
    m_dbReady = false;
    if (QSqlDatabase::contains(m_connectionName)) {
        {
            QSqlDatabase db = QSqlDatabase::database(m_connectionName, false);
            if (db.isOpen()) {
                db.close();
            }
        }
        QSqlDatabase::removeDatabase(m_connectionName);
    }

    m_punchedIn = false;
    m_activeRowId = 0;
    m_activeStartEpoch = 0;
    m_startedAtText.clear();
    m_lastDurationText.clear();
    m_statusText = QStringLiteral("Ready");
    Q_EMIT stateChanged();

    if (m_enabled) {
        refresh();
    }
}

void WorklogController::togglePunchClock()
{
    if (!m_enabled) {
        return;
    }
    if (useHttpApi()) {
        toggleHttpPunchClock();
    } else {
        toggleSqlitePunchClock();
    }
}

bool WorklogController::ensureSqliteReady()
{
    if (m_dbReady && QSqlDatabase::contains(m_connectionName)) {
        QSqlDatabase existing = QSqlDatabase::database(m_connectionName, false);
        if (existing.isOpen()) {
            return true;
        }
    }

    const QString dbPath = resolvedDbPath();
    const QFileInfo fi(dbPath);
    QDir().mkpath(fi.absolutePath());

    QSqlDatabase db = QSqlDatabase::contains(m_connectionName)
        ? QSqlDatabase::database(m_connectionName)
        : QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
    db.setDatabaseName(dbPath);

    if (!db.open()) {
        m_statusText = QStringLiteral("DB error: %1").arg(db.lastError().text());
        Q_EMIT stateChanged();
        return false;
    }

    QSqlQuery pragma(db);
    pragma.exec(QStringLiteral("PRAGMA journal_mode = WAL;"));
    pragma.exec(QStringLiteral("PRAGMA busy_timeout = 5000;"));

    QString chosenTable;
    if (m_config) {
        chosenTable = m_config->envValue(QStringLiteral("WORKLOG_DB_TABLE")).trimmed();
    }

    if (chosenTable.isEmpty()) {
        QSet<QString> existingTables;
        QSqlQuery tablesQuery(db);
        if (tablesQuery.exec(
                QStringLiteral("SELECT name FROM sqlite_master "
                               "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))) {
            while (tablesQuery.next()) {
                existingTables.insert(tablesQuery.value(0).toString());
            }
        }

        const QStringList candidates = {
            QStringLiteral("worklog_shifts"),
            QStringLiteral("shifts"),
            QStringLiteral("worklog"),
            QStringLiteral("time_logs"),
            QStringLiteral("work_sessions"),
        };
        for (const QString &candidate : candidates) {
            if (existingTables.contains(candidate)) {
                chosenTable = candidate;
                break;
            }
        }
        if (chosenTable.isEmpty()) {
            chosenTable = QStringLiteral("worklog_shifts");
        }
    }

    m_tableName = chosenTable;

    QSqlQuery createQuery(db);
    if (!createQuery.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS \"%1\" ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, "
            "start_time TEXT NOT NULL, "
            "end_time TEXT NULL, "
            "start_epoch INTEGER NULL, "
            "end_epoch INTEGER NULL, "
            "duration_seconds INTEGER NULL, "
            "duration_minutes REAL NULL)")
                              .arg(m_tableName))) {
        m_statusText = QStringLiteral("Schema error: %1").arg(createQuery.lastError().text());
        Q_EMIT stateChanged();
        return false;
    }

    m_tableColumns.clear();
    QSqlQuery infoQuery(db);
    if (infoQuery.exec(QStringLiteral("PRAGMA table_info(\"%1\")").arg(m_tableName))) {
        while (infoQuery.next()) {
            m_tableColumns.insert(infoQuery.value(1).toString());
        }
    }

    m_dbReady = true;
    return true;
}

void WorklogController::loadStateFromSqlite()
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (!db.isOpen()) {
        return;
    }

    const QString pkCol = m_tableColumns.contains(QStringLiteral("id"))
        ? QStringLiteral("id")
        : QStringLiteral("rowid");
    const bool hasStartEpoch = m_tableColumns.contains(QStringLiteral("start_epoch"));
    const bool hasDurationSecs = m_tableColumns.contains(QStringLiteral("duration_seconds"));
    const bool hasDurationMins = m_tableColumns.contains(QStringLiteral("duration_minutes"));

    m_punchedIn = false;
    m_activeRowId = 0;
    m_activeStartEpoch = 0;
    m_startedAtText.clear();

    QSqlQuery openQuery(db);
    const QString openSql = QStringLiteral(
        "SELECT %1, start_time%2 FROM \"%3\" "
        "WHERE end_time IS NULL OR TRIM(CAST(end_time AS TEXT)) = '' "
        "ORDER BY %1 DESC LIMIT 1")
                                .arg(pkCol,
                                     hasStartEpoch ? QStringLiteral(", start_epoch") : QString(),
                                     m_tableName);

    if (openQuery.exec(openSql) && openQuery.next()) {
        m_punchedIn = true;
        m_activeRowId = openQuery.value(0).toLongLong();
        const QString startStr = openQuery.value(1).toString();
        qint64 epoch = hasStartEpoch ? openQuery.value(2).toLongLong() : 0;
        QDateTime startedDt;
        if (epoch > 0) {
            startedDt = QDateTime::fromSecsSinceEpoch(epoch);
        } else {
            startedDt = QDateTime::fromString(startStr, Qt::ISODate);
            if (!startedDt.isValid()) {
                startedDt = QDateTime::fromString(startStr, QStringLiteral("yyyy-MM-dd HH:mm:ss"));
            }
            if (startedDt.isValid()) {
                epoch = startedDt.toSecsSinceEpoch();
            }
        }
        m_activeStartEpoch = epoch > 0 ? epoch : QDateTime::currentSecsSinceEpoch();
        m_startedAtText = startedDt.isValid()
            ? startedDt.toString(QStringLiteral("hh:mm AP"))
            : QStringLiteral("Active");
        m_statusText = QStringLiteral("Shift active since %1").arg(m_startedAtText);
    } else {
        m_statusText = QStringLiteral("Off shift");
    }

    QSqlQuery lastQuery(db);
    QString durExpr = QStringLiteral("0");
    if (hasDurationSecs) {
        durExpr = QStringLiteral("COALESCE(duration_seconds, 0)");
    } else if (hasDurationMins) {
        durExpr = QStringLiteral("CAST(ROUND(COALESCE(duration_minutes, 0) * 60) AS INTEGER)");
    }

    const QString lastSql = QStringLiteral(
        "SELECT start_time, end_time, %1 FROM \"%2\" "
        "WHERE end_time IS NOT NULL AND TRIM(CAST(end_time AS TEXT)) != '' "
        "ORDER BY %3 DESC LIMIT 1")
                                .arg(durExpr, m_tableName, pkCol);

    if (lastQuery.exec(lastSql) && lastQuery.next()) {
        qint64 durSecs = lastQuery.value(2).toLongLong();
        if (durSecs <= 0) {
            const QDateTime sDt = QDateTime::fromString(lastQuery.value(0).toString(), Qt::ISODate);
            const QDateTime eDt = QDateTime::fromString(lastQuery.value(1).toString(), Qt::ISODate);
            if (sDt.isValid() && eDt.isValid()) {
                durSecs = qMax<qint64>(0, sDt.secsTo(eDt));
            }
        }
        if (durSecs > 0) {
            m_lastDurationText = formatDurationSeconds(durSecs);
        }
    }

    Q_EMIT stateChanged();
}

void WorklogController::toggleSqlitePunchClock()
{
    if (!ensureSqliteReady()) {
        return;
    }

    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (!db.isOpen()) {
        return;
    }

    const QDateTime now = QDateTime::currentDateTime();
    const qint64 nowEpoch = now.toSecsSinceEpoch();
    const QString nowIso = now.toString(Qt::ISODate);

    if (!m_punchedIn) {
        QStringList cols{QStringLiteral("start_time")};
        QStringList placeholders{QStringLiteral(":start_time")};
        if (m_tableColumns.contains(QStringLiteral("start_epoch"))) {
            cols.append(QStringLiteral("start_epoch"));
            placeholders.append(QStringLiteral(":start_epoch"));
        }

        QSqlQuery insert(db);
        insert.prepare(QStringLiteral("INSERT INTO \"%1\" (%2) VALUES (%3)")
                           .arg(m_tableName, cols.join(QStringLiteral(", ")), placeholders.join(QStringLiteral(", "))));
        insert.bindValue(QStringLiteral(":start_time"), nowIso);
        if (cols.contains(QStringLiteral("start_epoch"))) {
            insert.bindValue(QStringLiteral(":start_epoch"), nowEpoch);
        }

        if (!insert.exec()) {
            m_statusText = QStringLiteral("Punch in failed: %1").arg(insert.lastError().text());
            Q_EMIT stateChanged();
            return;
        }

        m_punchedIn = true;
        m_activeRowId = insert.lastInsertId().toLongLong();
        m_activeStartEpoch = nowEpoch;
        m_startedAtText = now.toString(QStringLiteral("hh:mm AP"));
        m_statusText = QStringLiteral("Punched in at %1").arg(m_startedAtText);
        Q_EMIT stateChanged();

        QProcess::startDetached(
            QStringLiteral("notify-send"),
            {QStringLiteral("-a"),
             QStringLiteral("CatchyPills Worklog"),
             QStringLiteral("Punched In"),
             QStringLiteral("Shift started at %1").arg(m_startedAtText)});
        return;
    }

    const qint64 durationSecs = m_activeStartEpoch > 0
        ? qMax<qint64>(0, nowEpoch - m_activeStartEpoch)
        : 0;
    const double durationMins = static_cast<double>(durationSecs) / 60.0;
    const double durationHours = static_cast<double>(durationSecs) / 3600.0;

    QStringList setClauses{QStringLiteral("end_time = :end_time")};
    if (m_tableColumns.contains(QStringLiteral("end_epoch"))) {
        setClauses.append(QStringLiteral("end_epoch = :end_epoch"));
    }
    if (m_tableColumns.contains(QStringLiteral("duration_seconds"))) {
        setClauses.append(QStringLiteral("duration_seconds = :duration_seconds"));
    }
    if (m_tableColumns.contains(QStringLiteral("duration_minutes"))) {
        setClauses.append(QStringLiteral("duration_minutes = :duration_minutes"));
    }
    if (m_tableColumns.contains(QStringLiteral("duration_hours"))) {
        setClauses.append(QStringLiteral("duration_hours = :duration_hours"));
    }
    if (m_tableColumns.contains(QStringLiteral("duration"))) {
        setClauses.append(QStringLiteral("duration = :duration"));
    }

    const QString pkCol = m_tableColumns.contains(QStringLiteral("id"))
        ? QStringLiteral("id")
        : QStringLiteral("rowid");

    QSqlQuery upd(db);
    upd.prepare(QStringLiteral("UPDATE \"%1\" SET %2 WHERE %3 = :id")
                    .arg(m_tableName, setClauses.join(QStringLiteral(", ")), pkCol));
    upd.bindValue(QStringLiteral(":end_time"), nowIso);
    upd.bindValue(QStringLiteral(":end_epoch"), nowEpoch);
    upd.bindValue(QStringLiteral(":duration_seconds"), durationSecs);
    upd.bindValue(QStringLiteral(":duration_minutes"), durationMins);
    upd.bindValue(QStringLiteral(":duration_hours"), durationHours);
    upd.bindValue(QStringLiteral(":duration"), formatDurationSeconds(durationSecs));
    upd.bindValue(QStringLiteral(":id"), m_activeRowId);

    if (!upd.exec()) {
        m_statusText = QStringLiteral("Punch out failed: %1").arg(upd.lastError().text());
        Q_EMIT stateChanged();
        return;
    }

    m_punchedIn = false;
    m_activeRowId = 0;
    m_activeStartEpoch = 0;
    m_startedAtText.clear();
    m_lastDurationText = formatDurationSeconds(durationSecs);
    m_statusText = QStringLiteral("Logged %1").arg(m_lastDurationText);
    Q_EMIT stateChanged();

    QProcess::startDetached(
        QStringLiteral("notify-send"),
        {QStringLiteral("-a"),
         QStringLiteral("CatchyPills Worklog"),
         QStringLiteral("Punched Out"),
         QStringLiteral("Shift duration logged: %1").arg(m_lastDurationText)});
}

void WorklogController::refreshHttpApi()
{
    if (m_requestInFlight) {
        return;
    }

    const QUrl url(resolvedApiUrl());
    if (!url.isValid()) {
        m_statusText = QStringLiteral("Invalid WORKLOG_API_URL");
        Q_EMIT stateChanged();
        return;
    }

    m_requestInFlight = true;
    Q_EMIT stateChanged();

    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));
    if (m_config) {
        const QString token = m_config->envValue(QStringLiteral("WORKLOG_API_KEY")).trimmed();
        if (!token.isEmpty()) {
            request.setRawHeader("Authorization",
                                 QStringLiteral("Bearer %1").arg(token).toUtf8());
        }
    }

    QNetworkReply *reply = m_nam->get(request);
    m_activeReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (m_activeReply != reply) {
            m_requestInFlight = false;
            return;
        }
        m_activeReply = nullptr;
        m_requestInFlight = false;
        if (reply->error() == QNetworkReply::NoError) {
            applyHttpJson(reply->readAll(), false);
        } else {
            m_statusText = QStringLiteral("API offline");
            Q_EMIT stateChanged();
        }
    });
}

void WorklogController::toggleHttpPunchClock()
{
    if (m_requestInFlight) {
        return;
    }

    const QUrl url(resolvedApiUrl());
    if (!url.isValid()) {
        m_statusText = QStringLiteral("Invalid WORKLOG_API_URL");
        Q_EMIT stateChanged();
        return;
    }

    m_requestInFlight = true;
    Q_EMIT stateChanged();

    QNetworkRequest request(url);
    request.setTransferTimeout(8000);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("CatchyPills/1.1"));
    if (m_config) {
        const QString token = m_config->envValue(QStringLiteral("WORKLOG_API_KEY")).trimmed();
        if (!token.isEmpty()) {
            request.setRawHeader("Authorization",
                                 QStringLiteral("Bearer %1").arg(token).toUtf8());
        }
    }

    const QString action = m_punchedIn ? QStringLiteral("punch_out") : QStringLiteral("punch_in");
    const QJsonObject payload{{QStringLiteral("action"), action},
                              {QStringLiteral("timestamp"),
                               QDateTime::currentDateTime().toString(Qt::ISODate)}};

    QNetworkReply *reply = m_nam->post(request, QJsonDocument(payload).toJson(QJsonDocument::Compact));
    m_activeReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (m_activeReply != reply) {
            m_requestInFlight = false;
            return;
        }
        m_activeReply = nullptr;
        m_requestInFlight = false;

        if (reply->error() != QNetworkReply::NoError) {
            m_statusText = QStringLiteral("Sync failed: %1").arg(reply->errorString());
            Q_EMIT stateChanged();
            return;
        }
        applyHttpJson(reply->readAll(), true);
    });
}

void WorklogController::applyHttpJson(const QByteArray &payload, bool isToggle)
{
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (doc.isObject()) {
        const QJsonObject obj = doc.object();
        const bool hasFlag = obj.contains(QStringLiteral("punched_in"))
            || obj.contains(QStringLiteral("active"));
        if (hasFlag) {
            m_punchedIn = obj.contains(QStringLiteral("punched_in"))
                ? obj.value(QStringLiteral("punched_in")).toBool()
                : obj.value(QStringLiteral("active")).toBool();
        } else if (isToggle) {
            m_punchedIn = !m_punchedIn;
        }

        if (m_punchedIn) {
            qint64 startEp = obj.value(QStringLiteral("start_epoch")).toInteger();
            if (startEp <= 0 && obj.contains(QStringLiteral("start_time"))) {
                const QDateTime dt =
                    QDateTime::fromString(obj.value(QStringLiteral("start_time")).toString(), Qt::ISODate);
                if (dt.isValid()) {
                    startEp = dt.toSecsSinceEpoch();
                }
            }
            if (startEp <= 0) {
                startEp = QDateTime::currentSecsSinceEpoch();
            }
            m_activeStartEpoch = startEp;
            m_startedAtText = QDateTime::fromSecsSinceEpoch(startEp).toString(QStringLiteral("hh:mm AP"));
            m_statusText = QStringLiteral("Punched in at %1").arg(m_startedAtText);
        } else {
            const qint64 durSecs = obj.value(QStringLiteral("duration_seconds")).toInteger();
            if (durSecs > 0) {
                m_lastDurationText = formatDurationSeconds(durSecs);
            } else if (m_activeStartEpoch > 0) {
                m_lastDurationText = formatDurationSeconds(
                    qMax<qint64>(0, QDateTime::currentSecsSinceEpoch() - m_activeStartEpoch));
            }
            m_activeStartEpoch = 0;
            m_startedAtText.clear();
            m_statusText = m_lastDurationText.isEmpty()
                ? QStringLiteral("Off shift")
                : QStringLiteral("Logged %1").arg(m_lastDurationText);
        }
        Q_EMIT stateChanged();
        return;
    }

    if (isToggle) {
        const qint64 nowEpoch = QDateTime::currentSecsSinceEpoch();
        if (!m_punchedIn) {
            m_punchedIn = true;
            m_activeStartEpoch = nowEpoch;
            m_startedAtText = QDateTime::currentDateTime().toString(QStringLiteral("hh:mm AP"));
            m_statusText = QStringLiteral("Punched in at %1").arg(m_startedAtText);
        } else {
            m_lastDurationText = formatDurationSeconds(
                m_activeStartEpoch > 0 ? qMax<qint64>(0, nowEpoch - m_activeStartEpoch) : 0);
            m_punchedIn = false;
            m_activeStartEpoch = 0;
            m_startedAtText.clear();
            m_statusText = QStringLiteral("Logged %1").arg(m_lastDurationText);
        }
        Q_EMIT stateChanged();
    }
}

QString WorklogController::formatDurationSeconds(qint64 totalSeconds)
{
    const qint64 safeSecs = qMax<qint64>(0, totalSeconds);
    const qint64 hours = safeSecs / 3600;
    const qint64 minutes = (safeSecs % 3600) / 60;
    const qint64 seconds = safeSecs % 60;
    return QStringLiteral("%1:%2:%3")
        .arg(hours, 2, 10, QLatin1Char('0'))
        .arg(minutes, 2, 10, QLatin1Char('0'))
        .arg(seconds, 2, 10, QLatin1Char('0'));
}

} // namespace catchypills::worklog
