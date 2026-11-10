#include "wayland/LayerSurfaceController.hpp"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QUrl>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("catchypills"));
    app.setApplicationDisplayName(QStringLiteral("CatchyPills"));
    app.setOrganizationName(QStringLiteral("HearneLabs"));
    app.setOrganizationDomain(QStringLiteral("hearnelabs.io"));
    // Must match the installed .desktop filename for KWin ScreenShot2 authorization.
    app.setDesktopFileName(QStringLiteral("io.hearnelabs.CatchyPills"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule("CatchyPills", "IslandWindow");
    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
    if (!window) {
        return -1;
    }

    auto *layerController = new catchypills::wayland::LayerSurfaceController(window, window);
    engine.rootContext()->setContextProperty(QStringLiteral("layerController"), layerController);

    // Configure zwlr_layer_shell_v1 before mapping the Wayland surface.
    layerController->attachToLayerShell();
    window->show();

    return app.exec();
}
