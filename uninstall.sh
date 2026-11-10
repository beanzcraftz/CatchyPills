#!/usr/bin/env bash
set -euo pipefail

PURGE_DATA=false
if [[ "${1:-}" == "--purge" ]]; then
    PURGE_DATA=true
fi

echo "==> Stopping running CatchyPills processes and systemd user service..."
pkill -x catchypills >/dev/null 2>&1 || true
systemctl --user disable --now catchypillsd.service >/dev/null 2>&1 || true

echo "==> Removing installed binaries, desktop files, and unit..."
sudo rm -f /usr/bin/catchypills \
    /usr/bin/catchypillsd \
    /usr/share/applications/io.hearnelabs.CatchyPills.desktop \
    /etc/xdg/autostart/io.hearnelabs.CatchyPills.desktop \
    /usr/lib/systemd/user/catchypillsd.service

rm -f "$HOME/.config/autostart/io.hearnelabs.CatchyPills.desktop"

systemctl --user daemon-reload >/dev/null 2>&1 || true
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

if [[ "$PURGE_DATA" == true ]]; then
    echo "==> Purging user settings and clipboard history..."
    rm -rf "$HOME/.config/CatchyPills" "$HOME/.local/share/CatchyPills"
else
    echo "    Kept user config/data (~/.config/CatchyPills & ~/.local/share/CatchyPills). Pass --purge to delete."
fi

echo "✓ CatchyPills uninstalled."
