#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

VERSION="v1.1"
PKG_NAME="catchypills-${VERSION}"
STAGE_DIR="$REPO_ROOT/dist/${PKG_NAME}"
TARBALL_PATH="$REPO_ROOT/dist/catchypills-${VERSION}-cachyos-x86_64.tar.gz"

echo "==> [1/4] Building C++20/Qt6 Release binary (catchypills)..."
cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -G Ninja \
    -Wno-deprecated \
    -B "$REPO_ROOT/build"
cmake --build "$REPO_ROOT/build" --parallel

echo "==> [2/4] Building Rust Release daemon (catchypillsd)..."
cargo build --release --manifest-path "$REPO_ROOT/daemon/Cargo.toml"

echo "==> [3/4] Staging distribution bundle at ${STAGE_DIR}..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/assets"

install -Dm755 "$REPO_ROOT/build/catchypills" "$STAGE_DIR/catchypills"
install -Dm755 "$REPO_ROOT/daemon/target/release/catchypillsd" "$STAGE_DIR/catchypillsd"
install -Dm644 "$REPO_ROOT/README.md" "$STAGE_DIR/README.md"
install -Dm755 "$REPO_ROOT/install.sh" "$STAGE_DIR/install.sh"
install -Dm755 "$REPO_ROOT/uninstall.sh" "$STAGE_DIR/uninstall.sh"
install -Dm644 "$REPO_ROOT/packaging/io.hearnelabs.CatchyPills.desktop" \
    "$STAGE_DIR/io.hearnelabs.CatchyPills.desktop"
install -Dm644 "$REPO_ROOT/packaging/catchypillsd.service" \
    "$STAGE_DIR/catchypillsd.service"

if [[ -d "$REPO_ROOT/assets" ]]; then
    cp -a "$REPO_ROOT/assets/." "$STAGE_DIR/assets/"
fi

echo "==> [4/4] Creating compressed release archive..."
rm -f "$TARBALL_PATH"
tar -czf "$TARBALL_PATH" -C "$REPO_ROOT/dist" "$PKG_NAME"

echo "✓ Release tarball ready: $TARBALL_PATH"
