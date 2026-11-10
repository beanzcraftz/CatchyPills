#include "FileShelfModel.hpp"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>
#include <QMimeDatabase>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

#include <algorithm>

namespace catchypills::shelf {

namespace {
QString resolveImageThumbnailPath(const QFileInfo &info)
{
    if (!info.exists() || !info.isFile()) {
        return {};
    }

    static const QStringList kImageExtensions = {
        QStringLiteral("png"),  QStringLiteral("jpg"),  QStringLiteral("jpeg"),
        QStringLiteral("webp"), QStringLiteral("gif"),  QStringLiteral("bmp"),
        QStringLiteral("svg"),  QStringLiteral("avif"), QStringLiteral("tiff"),
        QStringLiteral("tif"),  QStringLiteral("ico"),  QStringLiteral("heic"),
        QStringLiteral("heif"), QStringLiteral("jxl"),
    };

    const QString suffix = info.suffix().toLower();
    if (kImageExtensions.contains(suffix)) {
        return info.absoluteFilePath();
    }

    const QMimeType mime = QMimeDatabase().mimeTypeForFile(info, QMimeDatabase::MatchDefault);
    if (mime.isValid() && mime.name().startsWith(QLatin1String("image/"))) {
        return info.absoluteFilePath();
    }

    return {};
}
} // namespace

FileShelfModel::FileShelfModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_expiryTimer(new QTimer(this))
{
    loadFromDisk();

    m_expiryTimer->setInterval(60 * 1000);
    connect(m_expiryTimer, &QTimer::timeout, this, &FileShelfModel::purgeExpired);
    if (m_retentionHours > 0) {
        m_expiryTimer->start();
    }
}

int FileShelfModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : count();
}

QVariant FileShelfModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= count()) {
        return {};
    }

    const ShelfItem &item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item.name;
    case UriRole:
        return item.uri;
    case LocalPathRole:
        return item.localPath;
    case ThumbnailPathRole:
        return item.thumbnailPath;
    case KindRole:
        return item.kind;
    case AddedAtRole:
        return item.addedAt;
    default:
        return {};
    }
}

QHash<int, QByteArray> FileShelfModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {UriRole, "uri"},
        {LocalPathRole, "localPath"},
        {ThumbnailPathRole, "thumbnailPath"},
        {KindRole, "kind"},
        {AddedAtRole, "addedAt"},
    };
}

void FileShelfModel::setRetentionHours(int hours)
{
    const int normalized = std::max(0, hours);
    if (m_retentionHours == normalized) {
        return;
    }

    m_retentionHours = normalized;
    if (m_retentionHours > 0) {
        purgeExpired();
        m_expiryTimer->start();
    } else {
        m_expiryTimer->stop();
    }
    Q_EMIT retentionHoursChanged(m_retentionHours);
}

int FileShelfModel::addUrls(const QStringList &urlStrings)
{
    int added = 0;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();

    // Reverse iterate so the first URL in the batch ends up at row 0.
    for (int i = static_cast<int>(urlStrings.size()) - 1; i >= 0; --i) {
        const QString trimmed = urlStrings.at(i).trimmed();
        if (trimmed.isEmpty()) {
            continue;
        }

        QUrl parsed(trimmed);
        if (!parsed.isValid() || parsed.scheme().isEmpty()) {
            parsed = QUrl::fromUserInput(trimmed);
        }
        if (!parsed.isValid()) {
            continue;
        }

        ShelfItem entry;
        entry.uri = parsed.toString();
        entry.addedAt = now;

        if (parsed.isLocalFile()) {
            const QString local = parsed.toLocalFile();
            const QFileInfo info(local);
            entry.localPath = local;
            entry.name = info.fileName().isEmpty() ? local : info.fileName();
            entry.thumbnailPath = resolveImageThumbnailPath(info);
            if (!entry.thumbnailPath.isEmpty()) {
                entry.kind = QStringLiteral("IMG");
            } else {
                entry.kind = info.isDir() ? QStringLiteral("DIR") : QStringLiteral("FILE");
            }
        } else {
            const QString tail = parsed.fileName();
            entry.name = tail.isEmpty() ? entry.uri : tail;
            entry.kind = QStringLiteral("URL");
        }

        upsertItem(std::move(entry));
        ++added;
    }

    if (added > 0) {
        saveToDisk();
    }
    return added;
}

bool FileShelfModel::addTextSnippet(const QString &text)
{
    const QString trimmed = text.trimmed();
    if (trimmed.isEmpty()) {
        return false;
    }

    ShelfItem entry;
    entry.name = trimmed.left(64).simplified();
    entry.uri = trimmed;
    entry.kind = QStringLiteral("TEXT");
    entry.addedAt = QDateTime::currentMSecsSinceEpoch();

    upsertItem(std::move(entry));
    saveToDisk();
    return true;
}

void FileShelfModel::removeItem(int index)
{
    if (index < 0 || index >= count()) {
        return;
    }

    beginRemoveRows(QModelIndex(), index, index);
    m_items.removeAt(index);
    endRemoveRows();
    Q_EMIT countChanged();
    saveToDisk();
}

void FileShelfModel::clear()
{
    if (m_items.isEmpty()) {
        return;
    }

    beginResetModel();
    m_items.clear();
    endResetModel();
    Q_EMIT countChanged();
    saveToDisk();
}

void FileShelfModel::copyItem(int index) const
{
    if (index < 0 || index >= count()) {
        return;
    }

    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        return;
    }

    const ShelfItem &item = m_items.at(index);
    auto *mime = new QMimeData();
    if (item.kind == QStringLiteral("TEXT")) {
        mime->setText(item.uri);
    } else {
        mime->setUrls({QUrl(item.uri)});
        mime->setText(item.localPath.isEmpty() ? item.uri : item.localPath);
    }
    clipboard->setMimeData(mime);
}

void FileShelfModel::purgeExpired()
{
    if (m_retentionHours <= 0 || m_items.isEmpty()) {
        return;
    }

    const qint64 cutoff =
        QDateTime::currentMSecsSinceEpoch() - (static_cast<qint64>(m_retentionHours) * 3600LL * 1000LL);

    bool changed = false;
    for (int i = count() - 1; i >= 0; --i) {
        if (m_items.at(i).addedAt > 0 && m_items.at(i).addedAt < cutoff) {
            beginRemoveRows(QModelIndex(), i, i);
            m_items.removeAt(i);
            endRemoveRows();
            changed = true;
        }
    }

    if (changed) {
        Q_EMIT countChanged();
        saveToDisk();
    }
}

void FileShelfModel::upsertItem(ShelfItem item)
{
    for (int i = 0; i < count(); ++i) {
        if (m_items.at(i).uri == item.uri) {
            beginRemoveRows(QModelIndex(), i, i);
            m_items.removeAt(i);
            endRemoveRows();
            break;
        }
    }

    beginInsertRows(QModelIndex(), 0, 0);
    m_items.prepend(std::move(item));
    endInsertRows();
    Q_EMIT countChanged();
}

QString FileShelfModel::storageFilePath() const
{
    const QString dataDir =
        QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/CatchyPills");
    QDir().mkpath(dataDir);
    return dataDir + QStringLiteral("/shelf.json");
}

void FileShelfModel::loadFromDisk()
{
    QFile file(storageFilePath());
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray()) {
        return;
    }

    beginResetModel();
    m_items.clear();
    const QJsonArray arr = doc.array();
    for (const QJsonValue &val : arr) {
        if (!val.isObject()) {
            continue;
        }
        const QJsonObject obj = val.toObject();
        ShelfItem item;
        item.name = obj.value(QStringLiteral("name")).toString();
        item.uri = obj.value(QStringLiteral("uri")).toString();
        item.localPath = obj.value(QStringLiteral("localPath")).toString();
        item.thumbnailPath = obj.value(QStringLiteral("thumbnailPath")).toString();
        if (item.thumbnailPath.isEmpty() && !item.localPath.isEmpty()) {
            item.thumbnailPath = resolveImageThumbnailPath(QFileInfo(item.localPath));
        } else if (!item.thumbnailPath.isEmpty() && !QFileInfo::exists(item.thumbnailPath)) {
            item.thumbnailPath.clear();
        }
        item.kind = obj.value(QStringLiteral("kind")).toString();
        item.addedAt = obj.value(QStringLiteral("addedAt")).toInteger();
        if (!item.uri.isEmpty()) {
            m_items.append(std::move(item));
        }
    }
    endResetModel();
    Q_EMIT countChanged();
}

void FileShelfModel::saveToDisk() const
{
    QJsonArray arr;
    for (const ShelfItem &item : m_items) {
        QJsonObject obj;
        obj.insert(QStringLiteral("name"), item.name);
        obj.insert(QStringLiteral("uri"), item.uri);
        obj.insert(QStringLiteral("localPath"), item.localPath);
        obj.insert(QStringLiteral("thumbnailPath"), item.thumbnailPath);
        obj.insert(QStringLiteral("kind"), item.kind);
        obj.insert(QStringLiteral("addedAt"), item.addedAt);
        arr.append(obj);
    }

    QSaveFile out(storageFilePath());
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    out.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    out.commit();
}

} // namespace catchypills::shelf
