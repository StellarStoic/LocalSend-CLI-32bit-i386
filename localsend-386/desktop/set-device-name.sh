#!/bin/bash
# Pin the LocalSend device name on this machine so other devices see a stable
# name instead of a new random adjective+noun on every launch.
# Usage: bash set-device-name.sh ["IdeaPad"]
set -euo pipefail
NAME="${1:-IdeaPad}"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/localsend-cli/config.yaml"

if [ ! -f "$CFG" ]; then
    echo "config not found: $CFG (run localsend-cli once first)" >&2
    exit 1
fi
cp "$CFG" "$CFG.bak-$(date +%F-%H%M%S)"

if grep -qE '^[[:space:]]*device_name:' "$CFG"; then
    sed -i "s|^[[:space:]]*device_name:.*|device_name: \"$NAME\"|" "$CFG"
    echo "updated existing device_name -> $NAME"
else
    printf '\n# Added by set-device-name.sh: stable name for the device list.\ndevice_name: "%s"\n' "$NAME" >> "$CFG"
    echo "appended device_name -> $NAME"
fi

echo "--- effective settings now:"
grep -nE '^[[:space:]]*(device_name|port|output_dir|quick_save):' "$CFG" | sed 's/^/   /'
