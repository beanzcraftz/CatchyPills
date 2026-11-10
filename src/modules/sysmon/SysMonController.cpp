#include "SysMonController.hpp"

#include <QFile>
#include <QStringList>
#include <QTextStream>
#include <QTimer>

#include <algorithm>
#include <cmath>

namespace catchypills::sysmon {

SysMonController::SysMonController(QObject *parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
{
    m_timer->setInterval(kPollIntervalMs);
    connect(m_timer, &QTimer::timeout, this, &SysMonController::sampleNow);
    sampleNow();
    m_timer->start();
}

void SysMonController::sampleNow()
{
    const int cpu = readCpuUsagePercent();
    const int ram = readRamUsagePercent();

    const bool cpuChanged = (cpu != m_cpuPercent);
    const bool ramChanged = (ram != m_ramPercent);
    const bool initialSample = m_cpuHistory.isEmpty();

    m_cpuPercent = cpu;
    m_ramPercent = ram;

    m_cpuHistory.append(cpu);
    while (m_cpuHistory.size() > kMaxHistorySamples) {
        m_cpuHistory.removeFirst();
    }

    Q_EMIT cpuHistoryChanged();
    if (cpuChanged || initialSample) {
        Q_EMIT cpuPercentChanged();
    }
    if (ramChanged || initialSample) {
        Q_EMIT ramPercentChanged();
    }
    if (cpuChanged || ramChanged || initialSample) {
        Q_EMIT statsUpdated();
    }
}

int SysMonController::readCpuUsagePercent()
{
    QFile file(QStringLiteral("/proc/stat"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return m_cpuPercent;
    }

    // /proc virtual files have size 0 so readAll() avoids premature QFile::atEnd() EOF.
    const QString content = QString::fromLatin1(file.readAll());
    const QStringList lines = content.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    if (lines.isEmpty()) {
        return m_cpuPercent;
    }

    const QString line = lines.constFirst().trimmed();
    if (!line.startsWith(QStringLiteral("cpu"))) {
        return m_cpuPercent;
    }

    const QStringList parts = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    // Expected fields: "cpu", user, nice, system, idle, iowait, irq, softirq, steal...
    if (parts.size() < 5) {
        return m_cpuPercent;
    }

    quint64 user = parts.at(1).toULongLong();
    quint64 nice = parts.at(2).toULongLong();
    quint64 system = parts.at(3).toULongLong();
    quint64 idle = parts.at(4).toULongLong();
    quint64 iowait = parts.size() > 5 ? parts.at(5).toULongLong() : 0ULL;
    quint64 irq = parts.size() > 6 ? parts.at(6).toULongLong() : 0ULL;
    quint64 softirq = parts.size() > 7 ? parts.at(7).toULongLong() : 0ULL;
    quint64 steal = parts.size() > 8 ? parts.at(8).toULongLong() : 0ULL;

    const quint64 idleTicks = idle + iowait;
    const quint64 nonIdleTicks = user + nice + system + irq + softirq + steal;
    const quint64 totalTicks = idleTicks + nonIdleTicks;

    int pct = m_cpuPercent;
    if (m_hasPrevCpu && totalTicks > m_prevTotalTicks) {
        const quint64 deltaTotal = totalTicks - m_prevTotalTicks;
        const quint64 deltaIdle = (idleTicks >= m_prevIdleTicks)
            ? (idleTicks - m_prevIdleTicks)
            : 0ULL;
        const quint64 busyTicks = (deltaTotal >= deltaIdle) ? (deltaTotal - deltaIdle) : 0ULL;
        const double ratio = (100.0 * static_cast<double>(busyTicks))
            / static_cast<double>(deltaTotal);
        pct = std::clamp(static_cast<int>(std::lround(ratio)), 0, 100);
    } else if (!m_hasPrevCpu) {
        pct = 0;
    }

    m_prevTotalTicks = totalTicks;
    m_prevIdleTicks = idleTicks;
    m_hasPrevCpu = true;
    return pct;
}

int SysMonController::readRamUsagePercent() const
{
    QFile file(QStringLiteral("/proc/meminfo"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return m_ramPercent;
    }

    // Read the entire virtual procfs file at once; /proc/meminfo reports 0 size so atEnd() is unreliable.
    const QString raw = QString::fromLatin1(file.readAll());
    const QStringList lines = raw.split(QLatin1Char('\n'), Qt::SkipEmptyParts);

    qint64 memTotal = 0;
    qint64 memAvailable = 0;
    qint64 memFree = 0;
    bool hasAvailable = false;

    for (const QString &line : lines) {
        if (line.startsWith(QStringLiteral("MemTotal:"))) {
            const QStringList parts = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (parts.size() >= 2) {
                memTotal = parts.at(1).toLongLong();
            }
        } else if (line.startsWith(QStringLiteral("MemAvailable:"))) {
            const QStringList parts = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (parts.size() >= 2) {
                memAvailable = parts.at(1).toLongLong();
                hasAvailable = true;
            }
        } else if (line.startsWith(QStringLiteral("MemFree:"))) {
            const QStringList parts = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (parts.size() >= 2) {
                memFree = parts.at(1).toLongLong();
            }
        }
        if (memTotal > 0 && hasAvailable) {
            break;
        }
    }

    if (memTotal <= 0) {
        return m_ramPercent;
    }

    const qint64 effectiveAvail = hasAvailable ? memAvailable : memFree;
    const int ramPct = qRound((static_cast<double>(memTotal - effectiveAvail) / static_cast<double>(memTotal)) * 100.0);
    return std::clamp(ramPct, 0, 100);
}

} // namespace catchypills::sysmon
