# CatchyPills

**CatchyPills** is a native Linux Dynamic Island, clipboard/file-search hub, and screen capture suite engineered specifically for **KDE Plasma 6 (Wayland)** on **CachyOS / Arch Linux**.

It unifies the floating island productivity workflow inspired by Windows **Pill** with the Wayland region-selection and annotation workflow of **OmniShot**, tuned for **32:9 ultrawide displays (`3840×1080`)** with a bottom Plasma panel.

---

## Key Features

- **Wayland-Native Dynamic Island (`zwlr_layer_shell_v1`):**
  - Anchored flush to the top-center bezel (`exclusiveZone = 0`, `KeyboardInteractivityNone` when idle) via `LayerShellQt`.
  - Fixed transparent QML canvas (`760×460`) with dynamic `QWindow::setMask()` (`wl_surface.set_input_region`) so every transparent pixel outside the animated pill passes mouse events directly to windows beneath.
  - Frosted glass blur synchronized to the pill's rounded geometry via `KWindowEffects` (`ext_background_effect_manager_v1` on Plasma 6.8+).
- **Background Clipboard History (`ext_data_control_manager_v1`):**
  - Passive Wayland clipboard monitoring without stealing keyboard focus.
  - Respects KDE/KeePassXC/KWallet privacy metadata by skipping entries carrying `x-kde-passwordManagerHint=secret`.
  - Persists deduplicated text and PNG/WebP/JPEG clips in SQLite (`$XDG_DATA_HOME/CatchyPills/catchypills.db3`).
- **Instant Fuzzy File Search (`ignore` + `notify` + `nucleo`):**
  - Parallel `$HOME` crawler kept live with `inotify` (`notify`), ranked in-memory with `nucleo` fuzzy path matching over Session D-Bus.
- **Drag-and-Drop File Shelf:**
  - Drop files, URLs, or text snippets onto the expanded island shelf for quick staging.
- **Screen Capture, Annotations & Recording (`KWin.ScreenShot2` + `KPipeWire`):**
  - Instant workspace and crop capture over `org.kde.KWin.ScreenShot2` using deadlock-free concurrent pipe reading.
  - Fullscreen `3840×1080` `CaptureOverlay` (`exclusiveZone = -1`) featuring a **4× pixel-accurate loupe magnifier**, live dimensions badge, and embedded **`AnnotationCanvas`** (Arrows, Rectangles, and Blur/Pixelate redaction).
  - Automatically saves PNGs to `~/Pictures/CatchyPills/` and publishes `image/png` to the Wayland clipboard.
  - Recording pipeline initialized with `org.freedesktop.portal.ScreenCast` + `KPipeWire` (`PipeWireRecord`) supporting **GIF (15 fps)**, **WebP (20 fps)**, and **MP4 H.264 (60 fps)** presets.
- **Resilient IPC:**
  - Non-blocking `QDBusServiceWatcher` + async `Ping` backoff automatically reconnects if `catchypillsd` restarts, displaying a subtle offline state in `CollapsedPill` while disconnected.

---

## Architecture

CatchyPills splits UI/Wayland/capture responsibilities from persistent background watching over **Session D-Bus** (`io.hearnelabs.CatchyPillsDaemon`):

```text
+------------------------------------------+        Session D-Bus        +------------------------------------------+
|         catchypills (C++20 / Qt6)        |   io.hearnelabs.CatchyPills |       catchypillsd (Rust Daemon)         |
|                                          |<--------------------------->|                                          |
| - Application (QDBusServiceWatcher)      |  GetRecentClips / Search    | - zbus (io.hearnelabs.CatchyPillsDaemon1)|
| - LayerSurfaceController (LayerShellQt)  |  ClipboardUpdated signal    | - Clipboard Watcher (ext-data-control-v1)|
| - CaptureCoordinator (ScreenShot2 /      |                             | - SQLite WAL store (rusqlite)            |
|   ScreenCast Portal + KPipeWire)         |                             | - Parallel File Indexer (ignore + notify |
| - QML UI (IslandWindow, CaptureOverlay,  |                             |   + nucleo fuzzy matcher)                |
|   AnnotationCanvas, ExpandedDashboard)   |                             |                                          |
+------------------------------------------+                             +------------------------------------------+
```

---

## Dependencies (Arch Linux / CachyOS)

Install the build toolchain, Qt 6 / KDE Frameworks 6 libraries, and runtime tools:

```bash
sudo pacman -S --needed \
    cmake ninja extra-cmake-modules rust pkgconf \
    qt6-base qt6-declarative qt6-wayland \
    layer-shell-qt kpipewire kwindowsystem kglobalaccel \
    ffmpeg libpipewire wayland xdg-desktop-portal xdg-desktop-portal-kde \
    tesseract wl-clipboard
```

---

## Build Instructions

### Option A: Manual CMake + Cargo Build

1. **Build the C++20 / Qt 6 frontend (`catchypills`):**
   ```bash
   cmake -B build -G Ninja \
       -DCMAKE_BUILD_TYPE=Release \
       -DCMAKE_INSTALL_PREFIX=/usr
   cmake --build build
   ```

2. **Build the Rust background daemon (`catchypillsd`):**
   ```bash
   cd daemon
   cargo build --release
   cd ..
   ```

### Option B: Native Arch Package (`makepkg`)

A ready-to-build `PKGBUILD` is provided in `packaging/arch/PKGBUILD`:

```bash
cd packaging/arch
makepkg -si
```

---

## Installation & Autostart

If installing manually (without `makepkg -si`), install both binaries, desktop entries, and the systemd user unit:

```bash
# 1. Install C++ frontend and application .desktop entry (/usr/bin/catchypills)
sudo DESTDIR=/ cmake --install build

# 2. Install XDG autostart entry (KDE Plasma Phase 2 startup)
sudo install -Dm644 packaging/io.hearnelabs.CatchyPills.desktop \
    /etc/xdg/autostart/io.hearnelabs.CatchyPills.desktop

# 3. Install Rust daemon binary and systemd --user unit
sudo install -Dm755 daemon/target/release/catchypillsd /usr/bin/catchypillsd
sudo install -Dm644 packaging/catchypillsd.service \
    /usr/lib/systemd/user/catchypillsd.service
```

### Enable the Background Daemon

Reload your user systemd manager and enable `catchypillsd.service`:

```bash
systemctl --user daemon-reload
systemctl --user enable --now catchypillsd.service
```

Verify the D-Bus service is healthy:

```bash
systemctl --user status catchypillsd.service
qdbus6 io.hearnelabs.CatchyPillsDaemon /io/hearnelabs/CatchyPillsDaemon io.hearnelabs.CatchyPillsDaemon1.Ping
```

> **Note on KWin `ScreenShot2` Permissions:** `packaging/io.hearnelabs.CatchyPills.desktop` declares `X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2`. Running `catchypills` after installing the `.desktop` entry into `/usr/share/applications/` (with matching `app.setDesktopFileName("io.hearnelabs.CatchyPills")`) allows KWin 6 to authorize silent screenshots without OS confirmation prompts.
