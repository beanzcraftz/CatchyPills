#pragma once

#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;

namespace catchypills::app {
class ConfigManager;
}

namespace catchypills::worklog {

/**
 * Tracks active work shifts against a local Streamlit SQLite database
 * (WORKLOG_DB_PATH in .env) or an HTTP endpoint (WORKLOG_API_URL in .env).
 */
class WorklogController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool punchedIn READ isPunchedIn NOTIFY stateChanged)
    Q_PROPERTY(qint64 activeStartEpoch READ activeStartEpoch NOTIFY stateChanged)
    Q_PROPERTY(QString startedAtText READ startedAtText NOTIFY stateChanged)
    Q_PROPERTY(QString lastDurationText READ lastDurationText NOTIFY stateChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ isBusy NOTIFY stateChanged)

public:
    explicit WorklogController(const app::ConfigManager *config, QObject *parent = nullptr);
    ~WorklogController() override;

    bool isPunchedIn() const noexcept { return m_punchedIn; }
    qint64 activeStartEpoch() const noexcept { return m_activeStartEpoch; }
    QString startedAtText() const { return m_startedAtText; }
    QString lastDurationText() const { return m_lastDurationText; }
    QString statusText() const { return m_statusText; }
    bool isBusy() const noexcept { return m_requestInFlight; }

    Q_INVOKABLE void setEnabled(bool enabled);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void togglePunchClock();
    Q_INVOKABLE void reloadConfig();

Q_SIGNALS:
    void stateChanged();

private:
    QString resolvedDbPath() const;
    QString resolvedApiUrl() const;
    bool useHttpApi() const;

    bool ensureSqliteReady();
    void loadStateFromSqlite();
    void toggleSqlitePunchClock();

    void refreshHttpApi();
    void toggleHttpPunchClock();
    void applyHttpJson(const QByteArray &payload, bool isToggle);

    static QString formatDurationSeconds(qint64 totalSeconds);

    const app::ConfigManager *m_config{nullptr};
    QNetworkAccessManager *m_nam{nullptr};
    QPointer<QNetworkReply> m_activeReply;
    QString m_connectionName;
    QString m_tableName{QStringLiteral("worklog_shifts")};
    QSet<QString> m_tableColumns;
    bool m_enabled{false};
    bool m_dbReady{false};
    bool m_punchedIn{false};
    bool m_requestInFlight{false};
    qint64 m_activeRowId{0};
    qint64 m_activeStartEpoch{0};
    QString m_startedAtText;
    QString m_lastDurationText;
    QString m_statusText{QStringLiteral("Ready")};
};

} // namespace catchypills::worklog
