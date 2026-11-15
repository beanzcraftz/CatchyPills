#pragma once

#include <QObject>

class QAction;

namespace catchypills::shortcut {

/**
 * Manages KDE Plasma 6 Wayland global shortcuts via KGlobalAccel and D-Bus.
 * Binds Meta+C to toggle visibility of the CatchyPills drop-down window.
 */
class ShortcutController final : public QObject
{
    Q_OBJECT

public:
    explicit ShortcutController(QObject *parent = nullptr);
    ~ShortcutController() override = default;

    bool registerGlobalShortcut();

    Q_INVOKABLE void toggle();

Q_SIGNALS:
    void toggleVisibility();

private Q_SLOTS:
    void onShortcutTriggered();

private:
    void registerViaDBus();

    QAction *m_action{nullptr};
    qint64 m_lastTriggerTime{0};
};

} // namespace catchypills::shortcut
