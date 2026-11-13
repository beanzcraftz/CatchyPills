cmake_minimum_required(VERSION 3.24)

project(CatchyPills
    VERSION 1.1.0
    DESCRIPTION "Dynamic floating island, clipboard/search hub, and Wayland capture suite for KDE Plasma 6"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTORCC ON)

include(GNUInstallDirs)

# Core Qt6 modules: Widgets is required by QSystemTrayIcon and KF6::GlobalAccel.
find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    Qml
    Quick
    DBus
    Sql
    Network
)

# Sets up AUTOMOC/AUTORCC, QML tooling policies, and Wayland-friendly Qt defaults.
qt_standard_project_setup(REQUIRES 6.5)
if(COMMAND qt_policy)
    qt_policy(SET QTP0004 NEW)
endif()

# KDE Frameworks 6 & Plasma 6 Wayland integration libraries.
find_package(KF6WindowSystem REQUIRED)
find_package(KF6GlobalAccel REQUIRED)
find_package(LayerShellQt REQUIRED)
find_package(KPipeWire REQUIRED)

qt_add_executable(catchypills
    src/main.cpp
    resources.qrc
    src/app/Application.hpp
    src/app/Application.cpp
    src/app/ConfigManager.hpp
    src/app/ConfigManager.cpp
    src/core/DaemonClient.hpp
    src/core/DaemonClient.cpp
    src/modules/capture/CaptureCoordinator.hpp
    src/modules/capture/CaptureCoordinator.cpp
    src/modules/iot/IoTController.hpp
    src/modules/iot/IoTController.cpp
    src/modules/itsm/ITSMController.hpp
    src/modules/itsm/ITSMController.cpp
    src/modules/media/MprisController.hpp
    src/modules/media/MprisController.cpp
    src/modules/notes/NotesModel.hpp
    src/modules/notes/NotesModel.cpp
    src/modules/solar/SolarController.hpp
    src/modules/solar/SolarController.cpp
    src/modules/sysmon/SysMonController.hpp
    src/modules/sysmon/SysMonController.cpp
    src/modules/weather/WeatherController.hpp
    src/modules/weather/WeatherController.cpp
    src/modules/worklog/WorklogController.hpp
    src/modules/worklog/WorklogController.cpp
    src/wayland/LayerSurfaceController.hpp
    src/wayland/LayerSurfaceController.cpp
)

qt_add_qml_module(catchypills
    URI CatchyPills
    VERSION 1.0
    QML_FILES
        src/ui/IslandWindow.qml
        src/ui/components/CollapsedPill.qml
        src/ui/components/ExpandedDashboard.qml
        src/ui/components/ClipboardView.qml
        src/ui/components/IoTView.qml
        src/ui/components/ITSMView.qml
        src/ui/components/MediaView.qml
        src/ui/components/NotesView.qml
        src/ui/components/SearchPaletteView.qml
        src/ui/capture/CaptureOverlay.qml
        src/ui/capture/AnnotationCanvas.qml
        src/ui/settings/SettingsWindow.qml
)

target_include_directories(catchypills PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

# Note exact imported target names on KDE Plasma 6 / CachyOS:
# - LayerShellQt provides LayerShellQt::Interface
# - KPipeWire provides K::KPipeWire, K::KPipeWireRecord, and K::KPipeWireDmaBuf
target_link_libraries(catchypills PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Qml
    Qt6::Quick
    Qt6::DBus
    Qt6::Sql
    Qt6::Network
    KF6::WindowSystem
    KF6::GlobalAccel
    LayerShellQt::Interface
    K::KPipeWire
    K::KPipeWireRecord
    K::KPipeWireDmaBuf
)

target_compile_options(catchypills PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)

install(TARGETS catchypills
    RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)

install(FILES packaging/io.beanzcraftz.CatchyPills.desktop
    DESTINATION "${CMAKE_INSTALL_DATADIR}/applications"
)

install(FILES assets/logo.png
    DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/128x128/apps"
    RENAME catchypills.png
)

install(FILES assets/logo.png
    DESTINATION "${CMAKE_INSTALL_DATADIR}/pixmaps"
    RENAME catchypills.png
)
