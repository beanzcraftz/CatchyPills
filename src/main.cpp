#include "app/Application.hpp"

#include <QApplication>

int main(int argc, char *argv[])
{
    // QApplication (QtWidgets) is required for native QSystemTrayIcon / KStatusNotifierItem.
    QApplication app(argc, argv);
    app.setQuitOnLastWindowClosed(false);
    app.setApplicationName(QStringLiteral("catchypills"));
    app.setApplicationDisplayName(QStringLiteral("CatchyPills"));
    app.setOrganizationName(QStringLiteral("HearneLabs"));
    app.setOrganizationDomain(QStringLiteral("hearnelabs.io"));
    // Must match the installed .desktop filename for KWin ScreenShot2 authorization.
    app.setDesktopFileName(QStringLiteral("io.hearnelabs.CatchyPills"));

    catchypills::app::Application controller;
    if (!controller.initialize()) {
        return -1;
    }

    return app.exec();
}
