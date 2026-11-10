#include "NotesModel.hpp"

#include <QApplication>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTime>
#include <QTimeZone>
#include <QTimer>

namespace catchypills::notes {

namespace {
constexpr int kAlarmCheckIntervalMs = 5000;
} // namespace

NotesModel::NotesModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_connectionName(QStringLiteral("catchypills_notes_sqlite"))
    , m_alarmTimer(new QTimer(this))
{
    if (openDatabase()) {
        loadNotes();
    }

    m_alarmTimer->setInterval(kAlarmCheckIntervalMs);
    connect(m_alarmTimer, &QTimer::timeout, this, &NotesModel::checkAlarms);
    m_alarmTimer->start();

    QTimer::singleShot(1000, this, &NotesModel::checkAlarms);
}

NotesModel::~NotesModel()
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

int NotesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : count();
}

QVariant NotesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= count()) {
        return {};
    }

    const NoteEntry &entry = m_notes.at(index.row());
    switch (role) {
    case NoteIdRole:
        return entry.id;
    case ContentRole:
        return entry.content;
    case CreatedAtRole:
        return entry.createdAtDisplay;
    case AlarmAtRole:
        return entry.alarmAtEpoch;
    case AlarmTimeDisplayRole:
        return formatAlarmTimestamp(entry.alarmAtEpoch);
    case HasPendingAlarmRole:
        return entry.alarmAtEpoch > 0 && !entry.alarmFired;
    case AlarmTriggeredRole:
        return entry.alarmAtEpoch > 0 && entry.alarmFired;
    default:
        return {};
    }
}

QHash<int, QByteArray> NotesModel::roleNames() const
{
    return {
        {NoteIdRole, "noteId"},
        {ContentRole, "content"},
        {CreatedAtRole, "createdAt"},
        {AlarmAtRole, "alarmAt"},
        {AlarmTimeDisplayRole, "alarmTimeText"},
        {HasPendingAlarmRole, "hasPendingAlarm"},
        {AlarmTriggeredRole, "alarmTriggered"},
    };
}

bool NotesModel::addNote(const QString &content, qint64 alarmEpoch)
{
    const QString trimmed = content.trimmed();
    if (trimmed.isEmpty()) {
        return false;
    }

    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (!db.isOpen()) {
        return false;
    }

    const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    const QString storedIso = nowUtc.toString(Qt::ISODate);
    const qint64 sanitizedAlarm = alarmEpoch > 0 ? alarmEpoch : 0;

    QSqlQuery insert(db);
    insert.prepare(QStringLiteral(
        "INSERT INTO notes (content, created_at, alarm_at, alarm_fired) "
        "VALUES (:content, :created_at, :alarm_at, 0)"));
    insert.bindValue(QStringLiteral(":content"), trimmed);
    insert.bindValue(QStringLiteral(":created_at"), storedIso);
    insert.bindValue(QStringLiteral(":alarm_at"),
                     sanitizedAlarm > 0 ? QVariant(sanitizedAlarm) : QVariant(QMetaType(QMetaType::LongLong)));
    if (!insert.exec()) {
        qWarning("NotesModel: insert failed: %s", qPrintable(insert.lastError().text()));
        return false;
    }

    NoteEntry entry;
    entry.id = insert.lastInsertId().toLongLong();
    entry.content = trimmed;
    entry.createdAtDisplay = nowUtc.toLocalTime().toString(QStringLiteral("MMM dd, hh:mm AP"));
    entry.alarmAtEpoch = sanitizedAlarm;
    entry.alarmFired = false;

    beginInsertRows(QModelIndex(), 0, 0);
    m_notes.prepend(std::move(entry));
    endInsertRows();
    Q_EMIT countChanged();
    return true;
}

bool NotesModel::addNoteWithPresetMinutes(const QString &content, int minutesFromNow)
{
    const qint64 alarmEpoch = minutesFromNow > 0
        ? QDateTime::currentSecsSinceEpoch() + static_cast<qint64>(minutesFromNow) * 60
        : 0;
    return addNote(content, alarmEpoch);
}

qint64 NotesModel::computeAlarmEpochFromHHMM(const QString &hhmm) const
{
    const QString trimmed = hhmm.trimmed();
    QTime parsed = QTime::fromString(trimmed, QStringLiteral("H:mm"));
    if (!parsed.isValid()) {
        parsed = QTime::fromString(trimmed, QStringLiteral("HH:mm"));
    }
    if (!parsed.isValid()) {
        return -1;
    }

    const QDateTime now = QDateTime::currentDateTime();
    QDateTime target(now.date(), parsed, now.timeZone());
    if (target <= now) {
        target = target.addDays(1);
    }
    return target.toSecsSinceEpoch();
}

void NotesModel::snoozeAlarm(qint64 noteId, int minutes)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (!db.isOpen()) {
        return;
    }

    const int clampMinutes = qMax(1, minutes);
    const qint64 newAlarmEpoch = QDateTime::currentSecsSinceEpoch() + static_cast<qint64>(clampMinutes) * 60;

    QSqlQuery query(db);
    query.prepare(QStringLiteral("UPDATE notes SET alarm_at = :alarm_at, alarm_fired = 0 WHERE id = :id"));
    query.bindValue(QStringLiteral(":alarm_at"), newAlarmEpoch);
    query.bindValue(QStringLiteral(":id"), noteId);
    if (!query.exec()) {
        qWarning("NotesModel: snooze update failed: %s", qPrintable(query.lastError().text()));
        return;
    }

    for (int i = 0; i < count(); ++i) {
        if (m_notes.at(i).id == noteId) {
            m_notes[i].alarmAtEpoch = newAlarmEpoch;
            m_notes[i].alarmFired = false;
            const QModelIndex idx = index(i, 0);
            Q_EMIT dataChanged(idx, idx, {AlarmAtRole, AlarmTimeDisplayRole, HasPendingAlarmRole, AlarmTriggeredRole});
            break;
        }
    }

    if (m_activeAlarmNoteId == noteId) {
        m_activeAlarmNoteId = 0;
        m_activeAlarmText.clear();
        Q_EMIT activeAlarmChanged();
    }
}

void NotesModel::dismissAlarm(qint64 noteId)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (db.isOpen()) {
        QSqlQuery query(db);
        query.prepare(QStringLiteral("UPDATE notes SET alarm_at = NULL, alarm_fired = 1 WHERE id = :id"));
        query.bindValue(QStringLiteral(":id"), noteId);
        if (!query.exec()) {
            qWarning("NotesModel: dismiss update failed: %s", qPrintable(query.lastError().text()));
        }
    }

    for (int i = 0; i < count(); ++i) {
        if (m_notes.at(i).id == noteId) {
            m_notes[i].alarmAtEpoch = 0;
            m_notes[i].alarmFired = true;
            const QModelIndex idx = index(i, 0);
            Q_EMIT dataChanged(idx, idx, {AlarmAtRole, AlarmTimeDisplayRole, HasPendingAlarmRole, AlarmTriggeredRole});
            break;
        }
    }

    if (m_activeAlarmNoteId == noteId) {
        m_activeAlarmNoteId = 0;
        m_activeAlarmText.clear();
        Q_EMIT activeAlarmChanged();
    }
}

void NotesModel::deleteNote(qint64 noteId)
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (!db.isOpen()) {
        return;
    }

    QSqlQuery del(db);
    del.prepare(QStringLiteral("DELETE FROM notes WHERE id = :id"));
    del.bindValue(QStringLiteral(":id"), noteId);
    if (!del.exec()) {
        qWarning("NotesModel: delete failed: %s", qPrintable(del.lastError().text()));
        return;
    }

    for (int i = 0; i < count(); ++i) {
        if (m_notes.at(i).id == noteId) {
            beginRemoveRows(QModelIndex(), i, i);
            m_notes.removeAt(i);
            endRemoveRows();
            Q_EMIT countChanged();
            break;
        }
    }

    if (m_activeAlarmNoteId == noteId) {
        m_activeAlarmNoteId = 0;
        m_activeAlarmText.clear();
        Q_EMIT activeAlarmChanged();
    }
}

void NotesModel::checkAlarms()
{
    const qint64 nowEpoch = QDateTime::currentSecsSinceEpoch();
    for (int i = 0; i < count(); ++i) {
        const NoteEntry &entry = m_notes.at(i);
        if (entry.alarmAtEpoch > 0 && !entry.alarmFired && entry.alarmAtEpoch <= nowEpoch) {
            triggerAlarmForEntry(i);
        }
    }
}

void NotesModel::triggerAlarmForEntry(int rowIndex)
{
    if (rowIndex < 0 || rowIndex >= count()) {
        return;
    }

    NoteEntry &entry = m_notes[rowIndex];
    entry.alarmFired = true;

    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (db.isOpen()) {
        QSqlQuery upd(db);
        upd.prepare(QStringLiteral("UPDATE notes SET alarm_fired = 1 WHERE id = :id"));
        upd.bindValue(QStringLiteral(":id"), entry.id);
        if (!upd.exec()) {
            qWarning("NotesModel: alarm_fired update failed: %s", qPrintable(upd.lastError().text()));
        }
    }

    const QModelIndex idx = index(rowIndex, 0);
    Q_EMIT dataChanged(idx, idx, {HasPendingAlarmRole, AlarmTriggeredRole});

    m_activeAlarmNoteId = entry.id;
    m_activeAlarmText = entry.content;
    Q_EMIT activeAlarmChanged();
    Q_EMIT alarmTriggered(entry.id, entry.content);

    playAlarmSound();

    QProcess::startDetached(QStringLiteral("notify-send"), {
        QStringLiteral("-u"), QStringLiteral("critical"),
        QStringLiteral("-a"), QStringLiteral("CatchyPills"),
        QStringLiteral("-i"), QStringLiteral("alarm-symbolic"),
        QStringLiteral("CatchyPills Reminder"),
        entry.content,
    });
}

void NotesModel::playAlarmSound() const
{
    const QString soundPath = QStringLiteral("/usr/share/sounds/freedesktop/stereo/complete.oga");
    const QString paplayBin = QStandardPaths::findExecutable(QStringLiteral("paplay"));
    if (!paplayBin.isEmpty() && QFileInfo::exists(soundPath)) {
        if (QProcess::startDetached(paplayBin, {soundPath})) {
            return;
        }
    }

    const QString canberraBin = QStandardPaths::findExecutable(QStringLiteral("canberra-gtk-play"));
    if (!canberraBin.isEmpty()) {
        if (QProcess::startDetached(canberraBin, {QStringLiteral("-i"), QStringLiteral("message-new-instant")})) {
            return;
        }
    }

    const QString tputBin = QStandardPaths::findExecutable(QStringLiteral("tput"));
    if (!tputBin.isEmpty()) {
        QProcess::startDetached(tputBin, {QStringLiteral("bel")});
    }
    QApplication::beep();
}

bool NotesModel::openDatabase()
{
    const QString dataDir =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/CatchyPills");
    QDir().mkpath(dataDir);

    QSqlDatabase db = QSqlDatabase::contains(m_connectionName)
        ? QSqlDatabase::database(m_connectionName)
        : QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
    db.setDatabaseName(dataDir + QStringLiteral("/catchypills.db3"));

    if (!db.open()) {
        qWarning("NotesModel: failed to open catchypills.db3: %s", qPrintable(db.lastError().text()));
        return false;
    }

    QSqlQuery pragma(db);
    pragma.exec(QStringLiteral("PRAGMA journal_mode = WAL;"));
    pragma.exec(QStringLiteral("PRAGMA busy_timeout = 5000;"));

    QSqlQuery schema(db);
    if (!schema.exec(QStringLiteral(
            "CREATE TABLE IF NOT EXISTS notes ("
            "id INTEGER PRIMARY KEY, "
            "content TEXT, "
            "created_at DATETIME, "
            "alarm_at INTEGER NULL, "
            "alarm_fired INTEGER NOT NULL DEFAULT 0)"))) {
        qWarning("NotesModel: failed to create notes table: %s", qPrintable(schema.lastError().text()));
        return false;
    }

    bool hasAlarmAt = false;
    bool hasAlarmFired = false;
    QSqlQuery info(db);
    if (info.exec(QStringLiteral("PRAGMA table_info(notes);"))) {
        while (info.next()) {
            const QString col = info.value(1).toString();
            if (col == QStringLiteral("alarm_at")) {
                hasAlarmAt = true;
            } else if (col == QStringLiteral("alarm_fired")) {
                hasAlarmFired = true;
            }
        }
    }

    if (!hasAlarmAt) {
        QSqlQuery alter(db);
        alter.exec(QStringLiteral("ALTER TABLE notes ADD COLUMN alarm_at INTEGER NULL;"));
    }
    if (!hasAlarmFired) {
        QSqlQuery alter(db);
        alter.exec(QStringLiteral("ALTER TABLE notes ADD COLUMN alarm_fired INTEGER NOT NULL DEFAULT 0;"));
    }

    return true;
}

void NotesModel::loadNotes()
{
    QSqlDatabase db = QSqlDatabase::database(m_connectionName);
    if (!db.isOpen()) {
        return;
    }

    QSqlQuery query(db);
    if (!query.exec(QStringLiteral(
            "SELECT id, content, created_at, COALESCE(alarm_at, 0), COALESCE(alarm_fired, 0) "
            "FROM notes ORDER BY id DESC"))) {
        return;
    }

    beginResetModel();
    m_notes.clear();
    while (query.next()) {
        NoteEntry entry;
        entry.id = query.value(0).toLongLong();
        entry.content = query.value(1).toString();
        entry.createdAtDisplay = formatTimestamp(query.value(2).toString());
        entry.alarmAtEpoch = query.value(3).toLongLong();
        entry.alarmFired = query.value(4).toInt() != 0;
        m_notes.append(std::move(entry));
    }
    endResetModel();
    Q_EMIT countChanged();
}

QString NotesModel::formatTimestamp(const QString &rawTimestamp)
{
    const QString trimmed = rawTimestamp.trimmed();
    QDateTime dt = QDateTime::fromString(trimmed, Qt::ISODate);
    if (!dt.isValid()) {
        dt = QDateTime::fromString(trimmed, QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        if (dt.isValid()) {
            dt.setTimeZone(QTimeZone::utc());
        }
    }
    if (!dt.isValid()) {
        return trimmed;
    }
    return dt.toLocalTime().toString(QStringLiteral("MMM dd, hh:mm AP"));
}

QString NotesModel::formatAlarmTimestamp(qint64 epochSeconds)
{
    if (epochSeconds <= 0) {
        return QString();
    }
    const QDateTime dt = QDateTime::fromSecsSinceEpoch(epochSeconds).toLocalTime();
    if (!dt.isValid()) {
        return QString();
    }
    if (dt.date() == QDate::currentDate()) {
        return dt.toString(QStringLiteral("HH:mm"));
    }
    return dt.toString(QStringLiteral("ddd HH:mm"));
}

} // namespace catchypills::notes
