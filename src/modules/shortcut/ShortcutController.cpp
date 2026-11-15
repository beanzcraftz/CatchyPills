#include "ShortcutController.hpp"

#include <QAction>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QKeySequence>
#include <KGlobalAccel>
#include <QDebug>

namespace catchypills::shortcut {

ShortcutController::ShortcutController(QObject *parent)
    : QObject(parent)
{
    m_action = new QAction(this);
    m_action->setObjectName(QStringLiteral("toggle_dropdown"));
    m_action->setText(QStringLiteral("Toggle CatchyPills Dropdown"));

    registerGlobalShortcut();
}

bool ShortcutController::registerGlobalShortcut()
{
    // Register global shortcut Meta+C via KDE KGlobalAccel (KF6)
    // KGlobalAccel registers the action with org.kde.kglobalaccel over D-Bus
    const bool success = KGlobalAccel::setGlobalShortcut(
        m_action, QKeySequence(Qt::META | Qt::Key_C));

    connect(m_action, &QAction::triggered, this, &ShortcutController::onShortcutTriggered);

    registerViaDBus();

    qInfo() << "CatchyPills global shortcut (Meta+C) registered:" << success;
    return success;
}

void ShortcutController::registerViaDBus()
{
    // Listen for direct D-Bus signal from org.kde.kglobalaccel for catchypills component
    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.kde.kglobalaccel"),
        QStringLiteral("/component/catchypills"),
        QStringLiteral("org.kde.kglobalaccel.Component"),
        QStringLiteral("globalShortcutPressed"),
        this,
        SLOT(onShortcutTriggered()));
}

void ShortcutController::onShortcutTriggered()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_lastTriggerTime < 250) {
        return; // Debounce duplicate triggers
    }
    m_lastTriggerTime = now;

    qDebug() << "Global shortcut Meta+C triggered -> toggleVisibility";
    Q_EMIT toggleVisibility();
}

void ShortcutController::toggle()
{
    onShortcutTriggered();
}

} // namespace catchypills::shortcut
