#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

echo "==> Installing CachyOS / Arch Linux dependencies..."
if [[ -f "CMakeLists.txt" ]]; then
    DEPS=(
        cmake
        ninja
        extra-cmake-modules
        pkgconf
        vulkan-headers
        qt6-base
        qt6-declarative
        qt6-wayland
        layer-shell-qt
        kpipewire
        kwindowsystem
        kglobalaccel
        ffmpeg
        libpipewire
        wayland
        xdg-desktop-portal
        xdg-desktop-portal-kde
        tesseract
        wl-clipboard
    )
    if ! pacman -Qi rustup >/dev/null 2>&1; then
        DEPS+=(rust)
    fi
else
    DEPS=(
        qt6-base
        qt6-declarative
        qt6-wayland
        layer-shell-qt
        kpipewire
        kwindowsystem
        kglobalaccel
        ffmpeg
        libpipewire
        wayland
        xdg-desktop-portal
        xdg-desktop-portal-kde
        tesseract
        wl-clipboard
    )
fi

sudo pacman -S --needed --noconfirm "${DEPS[@]}"

if [[ -f "CMakeLists.txt" ]]; then
    echo "==> Building CatchyPills C++20/Qt6 frontend..."
    cmake -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -Wno-deprecated
    cmake --build build --parallel

    echo "==> Building catchypillsd Rust background daemon..."
    pushd daemon >/dev/null
    cargo build --release
    popd >/dev/null

    echo "==> Installing binaries, desktop entry, autostart, and systemd user service..."
    sudo DESTDIR=/ cmake --install build
    sudo install -Dm755 "daemon/target/release/catchypillsd" "/usr/bin/catchypillsd"
    sudo install -Dm644 "packaging/catchypillsd.service" "/usr/lib/systemd/user/catchypillsd.service"
    mkdir -p "$HOME/.local/bin"
    install -Dm755 "build/catchypills" "$HOME/.local/bin/catchypills"
    DESKTOP_SRC="packaging/io.beanzcraftz.CatchyPills.desktop"
else
    echo "==> Installing prebuilt CatchyPills v1.1 release binaries..."
    sudo install -Dm755 "catchypills" "/usr/bin/catchypills"
    sudo install -Dm755 "catchypillsd" "/usr/bin/catchypillsd"
    sudo install -Dm644 "io.beanzcraftz.CatchyPills.desktop" \
        "/usr/share/applications/io.beanzcraftz.CatchyPills.desktop"
    sudo install -Dm644 "catchypillsd.service" "/usr/lib/systemd/user/catchypillsd.service"
    mkdir -p "$HOME/.local/bin"
    install -Dm755 "catchypills" "$HOME/.local/bin/catchypills"
    DESKTOP_SRC="io.beanzcraftz.CatchyPills.desktop"
fi

echo "==> Installing desktop icon and application shortcuts..."
if [[ -f "assets/logo.png" ]]; then
    sudo install -Dm644 "assets/logo.png" "/usr/share/icons/hicolor/128x128/apps/catchypills.png"
    sudo install -Dm644 "assets/logo.png" "/usr/share/pixmaps/catchypills.png"
    mkdir -p "$HOME/.local/share/icons/hicolor/128x128/apps"
    mkdir -p "$HOME/.local/share/pixmaps"
    install -Dm644 "assets/logo.png" "$HOME/.local/share/icons/hicolor/128x128/apps/catchypills.png"
    install -Dm644 "assets/logo.png" "$HOME/.local/share/pixmaps/catchypills.png"
fi

# Install user application menu entry
mkdir -p "$HOME/.local/share/applications"
install -Dm644 "$DESKTOP_SRC" "$HOME/.local/share/applications/io.beanzcraftz.CatchyPills.desktop"

# Install desktop shortcut
if [[ -d "$HOME/Desktop" ]]; then
    install -Dm755 "$DESKTOP_SRC" "$HOME/Desktop/CatchyPills.desktop"
    if command -v gio >/dev/null 2>&1; then
        gio set "$HOME/Desktop/CatchyPills.desktop" metadata::trusted true >/dev/null 2>&1 || true
    fi
fi

# Install per-user autostart entry so the Settings "Start with System" toggle can
# enable/disable it cleanly without elevated permissions.
mkdir -p "$HOME/.config/autostart"
install -Dm644 "$DESKTOP_SRC" \
    "$HOME/.config/autostart/io.beanzcraftz.CatchyPills.desktop"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

echo "==> Enabling and starting catchypillsd systemd user service..."
systemctl --user daemon-reload
systemctl --user enable --now catchypillsd.service

echo "==> Launching CatchyPills Dynamic Island..."
pkill -x catchypills >/dev/null 2>&1 || true
nohup /usr/bin/catchypills >/dev/null 2>&1 &
disown || true

echo "✓ CatchyPills installed and running!"
