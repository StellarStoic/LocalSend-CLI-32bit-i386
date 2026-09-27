#!/bin/bash
# install-desktop-integration.sh — run as root ON the target.
# Installs the binary system-wide, adds the menu entries (dashboard, plain receive,
# send clipboard, send file, and the danger-gated auto-accept receive), and validates
# everything.
#
#   sudo bash install-desktop-integration.sh [/path/to/localsend-cli-386]
#
# With no argument it uses the binary next to this script. It deliberately does NOT
# fall back to a shared /tmp path: that silently installed a months-old build once,
# and only the version read-back below caught it.
#
# Idempotent: re-running replaces the binary, wrappers and launchers in place.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BIN_SRC="${1:-$HERE/localsend-cli-386}"
APP_DIR=/usr/local/share/localsend-cli
BIN=/usr/local/bin/localsend-cli
MODE=/usr/local/bin/localsend-cli-mode
ICON_DIR=/usr/share/icons/hicolor/scalable/apps
APPS_DIR=/usr/share/applications

[ -f "$BIN_SRC" ] || { echo "binary not found: $BIN_SRC" >&2; exit 1; }

echo "== binary"
install -m 0755 "$BIN_SRC" "$BIN"
file "$BIN" | cut -c1-100
sha256sum "$BIN"
# Print what was actually installed, so an old build cannot slip through unnoticed.
INSTALLED_VERSION=$("$BIN" --version 2>/dev/null | head -1 || true)
echo "   version: ${INSTALLED_VERSION:-unknown}"

echo
echo "== wrappers (one script, mode chosen by the name it is called by)"
install -m 0755 "$HERE/localsend-mode.sh" "$MODE"
ln -sf "$MODE" /usr/local/bin/localsend-cli-receive
ln -sf "$MODE" /usr/local/bin/localsend-cli-quicksave
ln -sf "$MODE" /usr/local/bin/localsend-cli-sendtext
ln -sf "$MODE" /usr/local/bin/localsend-cli-sendfile
echo "   $MODE  (+ symlinks localsend-cli-receive, -quicksave, -sendtext, -sendfile)"
install -d "$APP_DIR"
install -m 0755 "$HERE/localsend-mode.sh" "$APP_DIR/localsend-mode.sh"
install -m 0755 "$HERE/set-device-name.sh" "$APP_DIR/set-device-name.sh"

echo
echo "== icons (scalable SVG, stay sharp at panel size)"
install -d "$ICON_DIR"
for i in localsend-cli.svg localsend-cli-warning.svg; do
    install -m 0644 "$HERE/$i" "$ICON_DIR/$i"
    install -m 0644 "$HERE/$i" "$APP_DIR/$i"
    echo "   $ICON_DIR/$i"
done

echo
echo "== menu entries"
for f in localsend-cli.desktop localsend-cli-receive.desktop localsend-cli-quicksave.desktop localsend-cli-sendtext.desktop localsend-cli-sendfile.desktop; do
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
echo "== check the launchers resolve"
ls -l "$BIN" /usr/local/bin/localsend-cli-receive /usr/local/bin/localsend-cli-quicksave 2>&1 | sed 's/^/   /'
"$BIN" --version | sed 's/^/   /'

echo
echo "== menu entries now visible to the session =="
grep -h -E "^(Name|Exec|Terminal|Categories)=" "$APPS_DIR"/localsend-cli*.desktop | sed 's/^/   /'

echo
echo "Done. Entries appear under Applications → Network (search \"LocalSend\"; the XFCE"
echo "Whisker menu matches names and keywords). If your menu looks cached, log out and"
echo "back in once, or run: xfce4-panel -r"
echo
echo "Only ONE LocalSend can run at a time (they all want port 53317). The wrapper for"
echo "the receive entries checks for that first and explains the clash instead of"
echo "failing with a bind error. The auto-accept entry additionally demands you type"
echo "the word 'danger' before it starts."
