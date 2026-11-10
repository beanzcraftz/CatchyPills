#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVector>

namespace catchypills::notes {

struct NoteEntry {
    qint64 id{0};
    QString content;
    QString createdAtDisplay;
};

/**
 * Persistent SQLite-backed list model for quick To-Do notes stored inside
 * $XDG_DATA_HOME/CatchyPills/catchypills.db3 (table `notes`, shared cleanly
 * under SQLite WAL mode with catchypillsd).
 */
class NotesModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        NoteIdRole = Qt::UserRole + 1,
        ContentRole,
        CreatedAtRole,
    };
    Q_ENUM(Roles)

    explicit NotesModel(QObject *parent = nullptr);
    ~NotesModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const noexcept { return static_cast<int>(m_notes.size()); }

    Q_INVOKABLE bool addNote(const QString &content);
    Q_INVOKABLE void deleteNote(qint64 noteId);

Q_SIGNALS:
    void countChanged();

private:
    bool openDatabase();
    void loadNotes();
    static QString formatTimestamp(const QString &rawTimestamp);

    QString m_connectionName;
    QVector<NoteEntry> m_notes;
};

} // namespace catchypills::notes
