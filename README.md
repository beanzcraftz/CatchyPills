# CatchyPills

**CatchyPills** is a Wayland-native Dynamic Island productivity hub, clipboard & file-search center, and screen capture suite engineered for **KDE Plasma 6 (`kwin_wayland`)** on **CachyOS / Arch Linux**.

Built specifically for ultrawide displays (`3840×1080`) and multi-monitor setups (`DP-1` / `DP-2`), CatchyPills puts everyday desktop tools in a lightweight top-bezel floating pill so you never have to break focus or alt-tab through windows to copy clips, log notes, control music, sample colors, record clips, or locate files.

---

## Why CatchyPills Saves Time

| Workflow | Without CatchyPills | With CatchyPills |
| :--- | :--- | :--- |
| **Multi-Monitor Repositioning** | Open settings to move widgets or risk accidental expansions while dragging | **Right-click drag** the pill cleanly anywhere on your monitor or across display bezels (`DP-1` ↔ `DP-2`) with zero accidental expand |
| **Clipboard & Snippets** | Overwrite copies cleanly lost once something new is copied | Passive Wayland watcher stores history in SQLite; one hover + click restores or pins clips permanently |
| **Quick Notes** | Launch a heavy editor or browser tab just to jot down a command/task | Built-in persistent SQLite To-Do & scratchpad right inside the island |
| **Screen Capture & MP4 Clips** | Switch tools for snipping, pixel inspection, blur redaction, and region MP4 capture | Unified fullscreen `4×` loupe selector with annotations, direct **OmniShot** handoff, and region-cropped MP4 recording with native **Save As** |
| **Screen Color Sampling** | Open GIMP/KColorChooser just to grab one CSS hex code | Click **Pick Screen Color (HEX)** in Capture to sample any pixel and copy `#RRGGBB` straight to clipboard |
| **Local File & Web Search** | Wait for file manager indexing or switch windows to search | Instant in-memory Rust fuzzy search (`nucleo`) over `$HOME` or one-click DuckDuckGo lookup |
| **System & Weather Glance** | Run `htop`/widgets or open a browser tab for weather | Live `2s` CPU sparkline + RAM% directly on the collapsed pill and a 30-minute cached weather readout in the dashboard header |

---

## Key Features

### Dynamic Island & Multi-Monitor Positioning
- **LayerShellQt (`zwlr_layer_shell_v1`):** Anchors unobtrusively without pushing maximized windows out of place (`exclusiveZone = 0`). Uses dynamic `QWindow::setMask()` / `Qt::WindowTransparentForInput` so transparent pixels stay click-through and synchronized with KDE blur (`KWindowEffects`).
- **Right-Click Drag Across Outputs:** Hold and drag the collapsed pill with the **right mouse button** to move smoothly across bezels and re-anchor onto adjacent monitors (`DP-1` ↔ `DP-2`). Left-clicking and hovering remain reserved for expanding the dashboard.
- **Settings & System Tray:** Live preferences (target monitor, offsets, hover settle timer, collapse delay, fullscreen auto-hide, screenshot folder, auto-copy toggle, clipboard capture pause, shelf retention, autostart) accessible from the header gear button (`⚙`) or system tray.

### Clipboard History (`ext_data_control_manager_v1`)
- Monitors the Wayland clipboard passively in the background without stealing focus.
- Respects password managers by ignoring `x-kde-passwordManagerHint=secret` payloads.
- Stores deduplicated text, URLs, and image previews in SQLite (`$XDG_DATA_HOME/CatchyPills/catchypills.db3`); click to copy or pin favorites permanently.

### Drop Inbox / File Shelf
- Drag files, images, or URLs onto the pill to unlock the canvas drop target automatically and stage items with generated image thumbnails.
- Click staged items to copy paths or drag files back out to target applications.

### SpotiBar Media Integration (MPRIS2)
- Controls any MPRIS2-compatible player (Spotify, VLC, browsers, etc.) directly from the **Media** tab.
- Displays album art, metadata, responsive Play/Pause/Prev/Next transport buttons, an animated 4-bar equalizer, and switchable **CachyCyberWave** (`#00E5A3`) and **NativePlasmaBreeze** (`#38BDF8`) themes.

### Quick Notes (SQLite Scratchpad)
- Type tasks or snippets cleanly inside the **Notes** tab and press `Enter` to persist them locally in SQLite with completion checkboxes and one-click delete.

### Unified Search (Local Fuzzy + Web)
- Segmented mode switch cleanly separates:
  - **Local Files:** Instant fuzzy matching powered by Rust (`ignore` + `notify` + `nucleo`) inside `catchypillsd`.
  - **Web Search:** Opens DuckDuckGo queries directly in your default browser.

### OmniShot Capture Suite & Wayland Eyedropper
- **Fullscreen Interactive Selector:** Freezes a crisp screen backdrop for a `4×` pixel-perfect loupe and coordinate readout, with **Arrow**, **Rect**, and pixel **Blur** annotation tools (`Ctrl+Z` undo).
- **Screenshot (OmniShot):** Sends annotated region captures straight into `omnishot --edit-existing` cleanly after unmapping the overlay.
- **Region MP4 Recording (`KPipeWire` + `ffmpeg`):** Captures the chosen region to `/tmp/catchypills_raw_screencast.mp4`, releases the LayerShell overlay cleanly on **Stop Recording**, opens a non-blocking **Save As** dialog (`org.freedesktop.portal.FileChooser::SaveFile` with `QFileDialog::open()` fallback) defaulting to `~/Videos/screencast_yyyyMMdd_HHmmss.mp4`, runs `ffmpeg` region cropping, cleans up `/tmp/`, and notifies via `notify-send` with the exact destination folder.
- **Pick Screen Color (HEX):** Uses `org.freedesktop.portal.Screenshot::PickColor` to sample any pixel on screen, copies uppercase `#RRGGBB` to your Wayland clipboard, and confirms via desktop notification.

### System Monitor Sparkline & Cached Weather Widget
- **Collapsed Pill SysMon:** Polls `/proc/stat` and `/proc/meminfo` every `2000 ms`, keeping a rolling 20-sample CPU history drawn as a `#00E5A3` neon-emerald sparkline + compact monospace CPU/RAM readout (with `CPU: XX% | RAM: XX%` hover tooltip).
- **Header Weather Pill:** Queries Open-Meteo (`current_weather=true`) over `Qt6::Network` and caches responses for 30 minutes (`QTimer`), mapping WMO codes to condition icons (`☀️`, `⛅`, `🌧️`, `⛈️`) with a hover tooltip showing full conditions, wind speed, and last update timestamp.

---

## Architecture

CatchyPills splits high-speed Wayland UI rendering and screen capture (`catchypills`, C++20/Qt6) from persistent background clipboard/filesystem indexing (`catchypillsd`, Rust) over **Session D-Bus** (`io.hearnelabs.CatchyPillsDaemon`):

```text
+--------------------------------------------+       Session D-Bus        +--------------------------------------------+
|          catchypills (C++20 / Qt6)         |  io.hearnelabs.CatchyPills |        catchypillsd (Rust Daemon)          |
|                                            |<-------------------------->|                                            |
| - LayerSurfaceController (LayerShellQt)    |  GetRecentClips / Search   | - zbus (io.hearnelabs.CatchyPillsDaemon1)  |
| - IslandWindow / CollapsedPill / Settings  |  SetClipboardPaused        | - ext_data_control_v1 Clipboard Watcher    |
| - SysMonController (/proc/stat & meminfo)  |  ClipboardUpdated signal   | - SQLite WAL store (rusqlite)              |
| - WeatherController (Open-Meteo 30m cache) |                            | - Parallel File Indexer (ignore + notify   |
| - MprisController (MPRIS2 D-Bus)           |                            |   + nucleo fuzzy matcher)                  |
| - CaptureCoordinator (ScreenShot2, PickColor|                            |                                            |
|   ScreenCast Portal + KPipeWire + SaveFile)|                            |                                            |
+--------------------------------------------+                            +--------------------------------------------+
```

Auto-restart resilience: `catchypillsd.service` runs with `Restart=on-failure`, while the Qt frontend monitors bus ownership via `QDBusServiceWatcher` and non-blocking exponential `Ping` backoff.

---

## Installation Guide (CachyOS / Arch Linux)

### Option 1: One-Click Source Install (Recommended)

```bash
git clone https://github.com/beanzcraftz/CatchyPills.git
cd CatchyPills
./install.sh
```

`install.sh` automatically:
1. Installs required dependencies via `sudo pacman -S --needed --noconfirm`.
2. Builds `catchypills` (C++20 / Qt6 / Ninja) and `catchypillsd` (Rust `--release`).
3. Installs `/usr/bin/catchypills`, `/usr/bin/catchypillsd`, desktop entries (`io.hearnelabs.CatchyPills.desktop`), XDG autostart, and `catchypillsd.service`.
4. Enables `catchypillsd.service` with `systemctl --user enable --now` and launches CatchyPills immediately.

### Option 2: Installing a Prebuilt Release 1.0 Bundle

If installing from a packaged `catchypills-v1.0-cachyos-x86_64.tar.gz` release archive:

```bash
tar -xzf catchypills-v1.0-cachyos-x86_64.tar.gz
cd catchypills-v1.0
./install.sh
```

---

## Packaging a Distribution Release

To compile Release targets and bundle everything into `dist/catchypills-v1.0-cachyos-x86_64.tar.gz`:

```bash
./package_release.sh
```

---

## Uninstalling

```bash
./uninstall.sh          # Removes binaries, desktop entry, autostart, and service (preserves user data)
./uninstall.sh --purge  # Also deletes ~/.config/CatchyPills and ~/.local/share/CatchyPills
```
