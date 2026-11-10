#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVector>

class QTimer;

namespace catchypills::notes {

struct NoteEntry {
    qint64 id{0};
    QString content;
    QString createdAtDisplay;
    qint64 alarmAtEpoch{0};
    bool alarmFired{false};
};

/**
 * Persistent SQLite-backed list model for quick To-Do notes & reminders stored inside
 * $XDG_DATA_HOME/CatchyPills/catchypills.db3 (table `notes`, shared cleanly
 * under SQLite WAL mode with catchypillsd).
 */
class NotesModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool hasActiveAlarm READ hasActiveAlarm NOTIFY activeAlarmChanged)
    Q_PROPERTY(qint64 activeAlarmNoteId READ activeAlarmNoteId NOTIFY activeAlarmChanged)
    Q_PROPERTY(QString activeAlarmText READ activeAlarmText NOTIFY activeAlarmChanged)

public:
    enum Roles {
        NoteIdRole = Qt::UserRole + 1,
        ContentRole,
        CreatedAtRole,
        AlarmAtRole,
        AlarmTimeDisplayRole,
        HasPendingAlarmRole,
        AlarmTriggeredRole,
    };
    Q_ENUM(Roles)

    explicit NotesModel(QObject *parent = nullptr);
    ~NotesModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const noexcept { return static_cast<int>(m_notes.size()); }
    bool hasActiveAlarm() const noexcept { return m_activeAlarmNoteId > 0 && !m_activeAlarmText.isEmpty(); }
    qint64 activeAlarmNoteId() const noexcept { return m_activeAlarmNoteId; }
    QString activeAlarmText() const { return m_activeAlarmText; }

    Q_INVOKABLE bool addNote(const QString &content, qint64 alarmEpoch = 0);
    Q_INVOKABLE bool addNoteWithPresetMinutes(const QString &content, int minutesFromNow);
    Q_INVOKABLE qint64 computeAlarmEpochFromHHMM(const QString &hhmm) const;
    Q_INVOKABLE void snoozeAlarm(qint64 noteId, int minutes = 10);
    Q_INVOKABLE void dismissAlarm(qint64 noteId);
    Q_INVOKABLE void deleteNote(qint64 noteId);

Q_SIGNALS:
    void countChanged();
    void activeAlarmChanged();
    void alarmTriggered(qint64 noteId, const QString &content);

private Q_SLOTS:
    void checkAlarms();

private:
    bool openDatabase();
    void loadNotes();
    void triggerAlarmForEntry(int rowIndex);
    void playAlarmSound() const;
    static QString formatTimestamp(const QString &rawTimestamp);
    static QString formatAlarmTimestamp(qint64 epochSeconds);

    QString m_connectionName;
    QVector<NoteEntry> m_notes;
    QTimer *m_alarmTimer{nullptr};
    qint64 m_activeAlarmNoteId{0};
    QString m_activeAlarmText;
};

} // namespace catchypills::notes
