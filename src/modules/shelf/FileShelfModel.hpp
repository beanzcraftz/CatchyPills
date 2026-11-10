#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QVector>

class QTimer;

namespace catchypills::shelf {

struct ShelfItem {
    QString name;
    QString uri;
    QString localPath;
    QString kind;
    qint64 addedAt{0};
};

/**
 * Persistent list model backing the File Shelf dropzone in ExpandedDashboard / FileShelfView.
 * Accepts dropped URLs/files (from Dolphin and other Wayland apps) as well as text snippets,
 * persisting staged items across restarts and expiring entries per ConfigManager retention.
 */
class FileShelfModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int retentionHours READ retentionHours WRITE setRetentionHours NOTIFY retentionHoursChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        UriRole,
        LocalPathRole,
        KindRole,
        AddedAtRole,
    };
    Q_ENUM(Roles)

    explicit FileShelfModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const noexcept { return static_cast<int>(m_items.size()); }
    int retentionHours() const noexcept { return m_retentionHours; }
    void setRetentionHours(int hours);

    Q_INVOKABLE int addUrls(const QStringList &urlStrings);
    Q_INVOKABLE bool addTextSnippet(const QString &text);
    Q_INVOKABLE void removeItem(int index);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void copyItem(int index) const;
    Q_INVOKABLE void purgeExpired();

Q_SIGNALS:
    void countChanged();
    void retentionHoursChanged(int hours);

private:
    QString storageFilePath() const;
    void loadFromDisk();
    void saveToDisk() const;
    void upsertItem(ShelfItem item);

    QVector<ShelfItem> m_items;
    int m_retentionHours{24};
    QTimer *m_expiryTimer{nullptr};
};

} // namespace catchypills::shelf
