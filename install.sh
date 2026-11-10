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
    DESKTOP_SRC="packaging/io.hearnelabs.CatchyPills.desktop"
else
    echo "==> Installing prebuilt CatchyPills v1.1 release binaries..."
    sudo install -Dm755 "catchypills" "/usr/bin/catchypills"
    sudo install -Dm755 "catchypillsd" "/usr/bin/catchypillsd"
    sudo install -Dm644 "io.hearnelabs.CatchyPills.desktop" \
        "/usr/share/applications/io.hearnelabs.CatchyPills.desktop"
    sudo install -Dm644 "catchypillsd.service" "/usr/lib/systemd/user/catchypillsd.service"
    DESKTOP_SRC="io.hearnelabs.CatchyPills.desktop"
fi

# Install per-user autostart entry so the Settings "Start with System" toggle can
# enable/disable it cleanly without elevated permissions.
mkdir -p "$HOME/.config/autostart"
install -Dm644 "$DESKTOP_SRC" \
    "$HOME/.config/autostart/io.hearnelabs.CatchyPills.desktop"

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
