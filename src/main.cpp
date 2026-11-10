#include "app/Application.hpp"

#include <QGuiApplication>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
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
