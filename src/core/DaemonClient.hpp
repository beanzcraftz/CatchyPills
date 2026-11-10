#pragma once

#include <QDBusArgument>
#include <QMetaType>
#include <QObject>
#include <QString>
#include <QVariantList>

namespace catchypills::core {

struct ClipboardEntryDto {
    qint64 id{0};
    QString kind;
    QString preview;
    qint64 createdAt{0};
};

struct FileMatchDto {
    QString name;
    QString path;
    quint32 score{0};
};

/**
 * Session D-Bus client connecting the C++20/Qt6 Dynamic Island to the Rust
 * catchypillsd background daemon (io.hearnelabs.CatchyPillsDaemon1).
 */
class DaemonClient final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString latestClipPreview READ latestClipPreview NOTIFY latestClipPreviewChanged)
    Q_PROPERTY(QVariantList recentClips READ recentClips NOTIFY recentClipsChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)

public:
    explicit DaemonClient(QObject *parent = nullptr);

    QString latestClipPreview() const { return m_latestClipPreview; }
    QVariantList recentClips() const { return m_recentClips; }
    QVariantList searchResults() const { return m_searchResults; }

    Q_INVOKABLE void refreshClips(int limit = 25);
    Q_INVOKABLE void searchFiles(const QString &query, int limit = 25);
    Q_INVOKABLE void setClipboardPaused(bool paused);
    Q_INVOKABLE void setItsmEnabled(bool enabled);
    Q_INVOKABLE void copyClipText(const QString &text);

Q_SIGNALS:
    void latestClipPreviewChanged();
    void recentClipsChanged();
    void searchResultsChanged();
    void clipboardUpdated(qint64 clipId, const QString &preview);
    void htmlClipboardReady(const QString &htmlText);

private Q_SLOTS:
    void onClipboardUpdated(qint64 clipId, const QString &preview);
    void onHtmlClipboardReady(const QString &htmlText);

private:
    static constexpr const char *kServiceName = "io.hearnelabs.CatchyPillsDaemon";
    static constexpr const char *kObjectPath = "/io/hearnelabs/CatchyPillsDaemon";
    static constexpr const char *kInterfaceName = "io.hearnelabs.CatchyPillsDaemon1";

    QString m_latestClipPreview;
    QVariantList m_recentClips;
    QVariantList m_searchResults;
};

} // namespace catchypills::core

Q_DECLARE_METATYPE(catchypills::core::ClipboardEntryDto)
Q_DECLARE_METATYPE(QList<catchypills::core::ClipboardEntryDto>)
Q_DECLARE_METATYPE(catchypills::core::FileMatchDto)
Q_DECLARE_METATYPE(QList<catchypills::core::FileMatchDto>)

QDBusArgument &operator<<(QDBusArgument &arg, const catchypills::core::ClipboardEntryDto &item);
const QDBusArgument &operator>>(const QDBusArgument &arg, catchypills::core::ClipboardEntryDto &item);

QDBusArgument &operator<<(QDBusArgument &arg, const catchypills::core::FileMatchDto &item);
const QDBusArgument &operator>>(const QDBusArgument &arg, catchypills::core::FileMatchDto &item);
