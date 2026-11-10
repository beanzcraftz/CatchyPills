# CatchyPills

**CatchyPills** is a native Linux Dynamic Island, clipboard/file-search hub, and screen capture suite engineered specifically for **KDE Plasma 6 (Wayland)** on **CachyOS / Arch Linux**.

It unifies the floating island productivity workflow inspired by Windows **Pill** with the Wayland region-selection and annotation workflow of **OmniShot**, tuned for **32:9 ultrawide displays (`3840×1080`)** with a bottom Plasma panel.

---

## One-Click Installation (CachyOS / Arch Linux)

```bash
git clone https://github.com/beanzcraftz/CatchyPills.git && cd CatchyPills && ./install.sh
```

`install.sh` automatically installs all required dependencies via `pacman`, compiles both `catchypills` (C++20/Qt6) and `catchypillsd` (Rust), installs binaries and XDG autostart entries, enables `catchypillsd.service`, and launches the Dynamic Island right away.

To remove CatchyPills later:

```bash
./uninstall.sh          # Remove binaries, service, and autostart (keeps user data)
./uninstall.sh --purge  # Also delete ~/.config/CatchyPills and ~/.local/share/CatchyPills
```

---

## Key Features

- **Wayland-Native Dynamic Island (`zwlr_layer_shell_v1`):**
  - Anchored to the top bezel (`exclusiveZone = 0`, `KeyboardInteractivityNone` when idle) via `LayerShellQt`.
  - Fixed transparent QML canvas (`760×460`) with dynamic `QWindow::setMask()` (`wl_surface.set_input_region`) so transparent pixels outside the animated pill stay click-through.
  - Frosted glass blur synchronized to the pill geometry via `KWindowEffects` (`ext_background_effect_manager_v1` on Plasma 6.8+).
- **Live Preferences & System Tray (`ConfigManager` + `SettingsWindow.qml`):**
  - Accessible from the **gear icon** in the expanded island header or the **System Tray icon**.
  - Live-updates target monitor, horizontal offset (`-1000` to `+1000` px), top margin (`0`–`64` px), hover collapse delay, auto-hide on fullscreen, clipboard pause/resume, file shelf retention timer, screenshot save folder, auto-copy behavior, and KDE autostart (`~/.config/CatchyPills/CatchyPills.conf`).
- **Background Clipboard History (`ext_data_control_manager_v1`):**
  - Passive Wayland clipboard monitoring without stealing keyboard focus.
  - Skips password manager secrets (`x-kde-passwordManagerHint=secret`) and stores deduplicated clips in SQLite (`$XDG_DATA_HOME/CatchyPills/catchypills.db3`).
- **Instant Fuzzy File Search (`ignore` + `notify` + `nucleo`):**
  - Parallel `$HOME` crawler kept live with `inotify`, fuzzy-matched in memory over Session D-Bus.
- **OmniShot-Style Screen Capture, Annotations & Recording (`KWin.ScreenShot2` + `KPipeWire`):**
  - Fullscreen `3840×1080` `CaptureOverlay` (`exclusiveZone = -1`) with **4× pixel-accurate loupe**, dimensions badge, and **`AnnotationCanvas`** (Arrows, Rectangles, and Blur/Pixelate redaction).
  - Automatically saves PNGs (defaulting to `~/Pictures/Screenshots`) and optionally copies `image/png` to the Wayland clipboard.
  - Recording presets initialized with `org.freedesktop.portal.ScreenCast` + `KPipeWire` (`PipeWireRecord`) for **GIF (15 fps)**, **WebP (20 fps)**, and **MP4 H.264 (60 fps)**.
- **Resilient IPC:**
  - Non-blocking `QDBusServiceWatcher` + async `Ping` backoff automatically reconnects if `catchypillsd` restarts, showing an offline indicator in `CollapsedPill` while disconnected.

---

## Architecture

CatchyPills splits UI/Wayland/capture responsibilities from persistent background watching over **Session D-Bus** (`io.hearnelabs.CatchyPillsDaemon`):

```text
+------------------------------------------+        Session D-Bus        +------------------------------------------+
|         catchypills (C++20 / Qt6)        |   io.hearnelabs.CatchyPills |       catchypillsd (Rust Daemon)         |
|                                          |<--------------------------->|                                          |
| - Application + QSystemTrayIcon          |  GetRecentClips / Search    | - zbus (io.hearnelabs.CatchyPillsDaemon1)|
| - ConfigManager (QSettings INI)          |  SetClipboardPaused         | - Clipboard Watcher (ext-data-control-v1)|
| - LayerSurfaceController (LayerShellQt)  |  ClipboardUpdated signal    | - SQLite WAL store (rusqlite)            |
| - CaptureCoordinator (ScreenShot2 /      |                             | - Parallel File Indexer (ignore + notify |
|   ScreenCast Portal + KPipeWire)         |                             |   + nucleo fuzzy matcher)                |
| - QML UI (Island, Settings, Overlay)     |                             |                                          |
+------------------------------------------+                             +------------------------------------------+
```

---

## Manual / Package Build (Optional)

If you prefer building a native Arch package or running steps manually:

```bash
# Arch / CachyOS package build
cd packaging/arch
makepkg -si
systemctl --user daemon-reload
systemctl --user enable --now catchypillsd.service
```

Or build manually with CMake and Cargo:

```bash
sudo pacman -S --needed cmake ninja extra-cmake-modules rust pkgconf \
    qt6-base qt6-declarative qt6-wayland layer-shell-qt kpipewire \
    kwindowsystem kglobalaccel ffmpeg libpipewire wayland \
    xdg-desktop-portal xdg-desktop-portal-kde tesseract wl-clipboard

cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build
(cd daemon && cargo build --release)
```
