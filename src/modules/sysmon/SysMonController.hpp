#pragma once

#include <QObject>
#include <QVariantList>

#include <cstdint>

class QTimer;

namespace catchypills::sysmon {

/**
 * Polls Linux /proc/stat and /proc/meminfo on a 2-second interval to expose live
 * CPU/RAM percentages and a rolling 20-sample CPU history for CollapsedPill.qml.
 */
class SysMonController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int cpuPercent READ cpuPercent NOTIFY cpuPercentChanged)
    Q_PROPERTY(int ramPercent READ ramPercent NOTIFY ramPercentChanged)
    Q_PROPERTY(QVariantList cpuHistory READ cpuHistory NOTIFY cpuHistoryChanged)

public:
    static constexpr int kPollIntervalMs = 2000;
    static constexpr int kMaxHistorySamples = 20;

    explicit SysMonController(QObject *parent = nullptr);

    int cpuPercent() const noexcept { return m_cpuPercent; }
    int ramPercent() const noexcept { return m_ramPercent; }
    QVariantList cpuHistory() const { return m_cpuHistory; }

    Q_INVOKABLE void sampleNow();

Q_SIGNALS:
    void cpuPercentChanged();
    void ramPercentChanged();
    void statsUpdated();
    void cpuHistoryChanged();

private:
    int readCpuUsagePercent();
    int readRamUsagePercent() const;

    QTimer *m_timer{nullptr};
    QVariantList m_cpuHistory;
    quint64 m_prevTotalTicks{0};
    quint64 m_prevIdleTicks{0};
    bool m_hasPrevCpu{false};
    int m_cpuPercent{0};
    int m_ramPercent{0};
};

} // namespace catchypills::sysmon
