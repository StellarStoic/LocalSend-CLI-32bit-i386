#!/bin/bash
# install-desktop-integration.sh — run as root ON the target.
# Installs the binary system-wide, adds menu entries, and validates them.
#
#   sudo bash install-desktop-integration.sh /path/to/localsend-cli-386
#
# Idempotent: re-running replaces the binary and the launchers in place.
set -euo pipefail

BIN_SRC="${1:-/tmp/localsend-cli-386}"
APP_DIR=/usr/local/share/localsend-cli
BIN=/usr/local/bin/localsend-cli
ICON_DIR=/usr/share/icons/hicolor/scalable/apps
APPS_DIR=/usr/share/applications

[ -f "$BIN_SRC" ] || { echo "binary not found: $BIN_SRC" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)

echo "== binary"
install -m 0755 "$BIN_SRC" "$BIN"
file "$BIN" | cut -c1-100
sha256sum "$BIN"

echo
echo "== icon (scalable SVG, so it stays sharp at panel size)"
install -d "$ICON_DIR"
install -m 0644 "$HERE/localsend-cli.svg" "$ICON_DIR/localsend-cli.svg"
# also drop a copy next to the app for reference
install -d "$APP_DIR"
install -m 0644 "$HERE/localsend-cli.svg" "$APP_DIR/localsend-cli.svg"

echo "== menu entries"
for f in localsend-cli.desktop localsend-cli-receive.desktop; do
    install -m 0644 "$HERE/$f" "$APPS_DIR/$f"
    if desktop-file-validate "$APPS_DIR/$f"; then
        echo "   $f: valid"
    else
        echo "   $f: VALIDATION FAILED (see above)" >&2
    fi
done

echo
echo "== refreshing desktop + icon caches"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" && echo "   desktop database updated"
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null | tail -1 || true

echo
echo "== check the launcher actually resolves"
command -v localsend-cli && localsend-cli --version

echo
echo "== menu entries now visible to the session =="
grep -h -E "^(Name|Exec|Terminal|Categories)=" "$APPS_DIR"/localsend-cli*.desktop | sed 's/^/   /'

echo
echo "Done. The entries appear under Applications → Network (or search \"LocalSend\";"
echo "the XFCE Whisker menu finds it by name or keywords). If your panel shows a menu"
echo "cache, log out and back in once, or run: xfce4-panel -r"
