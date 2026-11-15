#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

class QProcess;
class QTimer;

namespace catchypills::peripheral {

/**
 * Polls Logitech peripheral telemetry (battery percentage, DPI sensitivity)
 * via the Solaar CLI (`solaar show "G502 X PLUS"`) and exposes readouts for QML.
 */
class PeripheralController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString mouseBattery READ mouseBattery NOTIFY telemetryUpdated)
    Q_PROPERTY(QString mouseDpi READ mouseDpi NOTIFY telemetryUpdated)
    Q_PROPERTY(int batteryPercentage READ batteryPercentage NOTIFY telemetryUpdated)
    Q_PROPERTY(bool connected READ isConnected NOTIFY telemetryUpdated)
    Q_PROPERTY(QString statusText READ statusText NOTIFY telemetryUpdated)

public:
    static constexpr int kDefaultPollIntervalMs = 10000;

    explicit PeripheralController(QObject *parent = nullptr);
    ~PeripheralController() override;

    QString mouseBattery() const { return m_mouseBattery; }
    QString mouseDpi() const { return m_mouseDpi; }
    int batteryPercentage() const noexcept { return m_batteryPercentage; }
    bool isConnected() const noexcept { return m_connected; }
    QString statusText() const { return m_statusText; }

    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void telemetryUpdated();

private:
    void onProcessFinished(int exitCode);

    QTimer *m_pollTimer{nullptr};
    QPointer<QProcess> m_process;
    QString m_mouseBattery{QStringLiteral("--")};
    QString m_mouseDpi{QStringLiteral("-- DPI")};
    int m_batteryPercentage{-1};
    bool m_connected{false};
    QString m_statusText{QStringLiteral("Connecting...")};
};

} // namespace catchypills::peripheral
