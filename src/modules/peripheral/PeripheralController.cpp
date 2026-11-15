#include "PeripheralController.hpp"

#include <QProcess>
#include <QRegularExpression>
#include <QTimer>

namespace catchypills::peripheral {

PeripheralController::PeripheralController(QObject *parent)
    : QObject(parent)
    , m_pollTimer(new QTimer(this))
{
    m_pollTimer->setInterval(kDefaultPollIntervalMs);
    connect(m_pollTimer, &QTimer::timeout, this, &PeripheralController::refresh);
    m_pollTimer->start();

    // Initial immediate poll
    refresh();
}

PeripheralController::~PeripheralController()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(500);
    }
}

void PeripheralController::refresh()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        return;
    }

    m_process = new QProcess(this);
    connect(m_process, &QProcess::finished, this, &PeripheralController::onProcessFinished);

    const QStringList args{QStringLiteral("show"), QStringLiteral("G502 X PLUS")};
    m_process->start(QStringLiteral("solaar"), args);
}

void PeripheralController::onProcessFinished(int exitCode)
{
    if (!m_process) {
        return;
    }

    const QString output = QString::fromUtf8(m_process->readAllStandardOutput());
    m_process->deleteLater();
    m_process = nullptr;

    if (exitCode != 0 || !output.contains(QStringLiteral("G502 X PLUS"), Qt::CaseInsensitive)) {
        m_connected = false;
        m_statusText = QStringLiteral("Asleep or Standby");
        m_mouseBattery = QStringLiteral("--");
        m_mouseDpi = QStringLiteral("-- DPI");
        m_batteryPercentage = -1;
        Q_EMIT telemetryUpdated();
        return;
    }

    static const QRegularExpression batteryRegex(QStringLiteral(R"(Battery:\s*(\d+)%)"));
    static const QRegularExpression dpiRegex(QStringLiteral(R"(Sensitivity \(DPI\)\s*:\s*(\d+))"));

    const auto batteryMatch = batteryRegex.match(output);
    bool parsedTelemetry = false;

    if (batteryMatch.hasMatch()) {
        bool ok = false;
        const int pct = batteryMatch.captured(1).toInt(&ok);
        if (ok) {
            m_batteryPercentage = pct;
            m_mouseBattery = QStringLiteral("%1%").arg(pct);
            parsedTelemetry = true;
        }
    }

    const auto dpiMatch = dpiRegex.match(output);
    if (dpiMatch.hasMatch()) {
        m_mouseDpi = QStringLiteral("%1 DPI").arg(dpiMatch.captured(1));
        parsedTelemetry = true;
    }

    if (parsedTelemetry) {
        m_connected = true;
        m_statusText = QStringLiteral("Connected");
    } else {
        m_connected = false;
        m_statusText = QStringLiteral("Standby");
    }

    Q_EMIT telemetryUpdated();
}

} // namespace catchypills::peripheral
