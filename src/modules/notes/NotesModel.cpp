#include "NotesModel.hpp"

#include <QDateTime>
#include <QDir>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTimeZone>

namespace catchypills::notes {

NotesModel::NotesModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_connectionName(QStringLiteral("catchypills_notes_sqlite"))
{
    if (openDatabase()) {
        loadNotes();
    }
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
    };
}

bool NotesModel::addNote(const QString &content)
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

    QSqlQuery insert(db);
    insert.prepare(QStringLiteral("INSERT INTO notes (content, created_at) VALUES (:content, :created_at)"));
    insert.bindValue(QStringLiteral(":content"), trimmed);
    insert.bindValue(QStringLiteral(":created_at"), storedIso);
    if (!insert.exec()) {
        qWarning("NotesModel: insert failed: %s", qPrintable(insert.lastError().text()));
        return false;
    }

    NoteEntry entry;
    entry.id = insert.lastInsertId().toLongLong();
    entry.content = trimmed;
    entry.createdAtDisplay = nowUtc.toLocalTime().toString(QStringLiteral("MMM dd, hh:mm AP"));

    beginInsertRows(QModelIndex(), 0, 0);
    m_notes.prepend(std::move(entry));
    endInsertRows();
    Q_EMIT countChanged();
    return true;
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
            "created_at DATETIME)"))) {
        qWarning("NotesModel: failed to create notes table: %s", qPrintable(schema.lastError().text()));
        return false;
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
    if (!query.exec(QStringLiteral("SELECT id, content, created_at FROM notes ORDER BY id DESC"))) {
        return;
    }

    beginResetModel();
    m_notes.clear();
    while (query.next()) {
        NoteEntry entry;
        entry.id = query.value(0).toLongLong();
        entry.content = query.value(1).toString();
        entry.createdAtDisplay = formatTimestamp(query.value(2).toString());
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

} // namespace catchypills::notes
