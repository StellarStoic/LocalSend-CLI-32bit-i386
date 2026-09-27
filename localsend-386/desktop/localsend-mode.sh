#!/bin/bash
# localsend-mode.sh — one wrapper for the non-dashboard menu entries.
#
# Install it four ways and the mode follows the name it is called by:
#   localsend-cli-receive      -> plain receive (you approve each sender)
#   localsend-cli-quicksave    -> auto-accept receive, behind a typed danger gate
#   localsend-cli-sendtext     -> send text/clipboard (no port needed)
#   localsend-cli-sendfile <f> -> send a file; drop one onto this launcher and its
#                                 path arrives as the argument (no port needed)
#   localsend-cli-mode <mode>  -> explicit mode argument
#
# Why a wrapper at all: LocalSend binds port 53317, so a second instance started
# while the dashboard is open dies with "bind: address already in use" — a raw Go
# error right after a success banner. This checks first and says something useful.
set -u

mode=$(basename "$0")
case "$mode" in
    localsend-cli-receive)  mode=receive ;;
    localsend-cli-quicksave) mode=quicksave ;;
    localsend-cli-sendtext) mode=clipboard ;;
    localsend-cli-sendfile) mode=sendfile ;;
    *) mode="${1:-receive}"; shift || true ;;
esac

case "$mode" in
    receive|quicksave|clipboard|sendfile) ;;
    *) echo "usage: $(basename "$0") [receive|quicksave|clipboard|sendfile <file>] [extra localsend-cli args]" >&2; exit 2 ;;
esac

# ---- send a file (drag & drop) ---------------------------------------------------
# Dropping a file onto a launcher hands this script its path, so a file can go out
# without going through the dashboard's box. Also handled before the port
# pre-flight, for the same reason as the clipboard: sending never binds 53317.
if [ "$mode" = "sendfile" ]; then
    file="${1:-}"
    if [ -z "$file" ]; then
        echo
        echo "  No file given. Drop a file onto this launcher, or run:"
        echo "    $(basename "$0") /path/to/file"
        echo
        [ -t 0 ] && { printf "  Press Enter to close. "; read -r _ || true; }
        exit 1
    fi
    if [ ! -e "$file" ]; then
        echo
        echo "  No such file: $file"
        echo
        [ -t 0 ] && { printf "  Press Enter to close. "; read -r _ || true; }
        exit 1
    fi
    if [ -d "$file" ]; then
        echo
        echo "  That is a directory, and LocalSend sends files: $file"
        echo "  (tar it up first if you meant to send a folder)"
        echo
        [ -t 0 ] && { printf "  Press Enter to close. "; read -r _ || true; }
        exit 1
    fi
    echo "  Sending: $file"
    exec localsend-cli send "$file"
fi

# ---- clipboard / text send ------------------------------------------------------
# Handled before the port pre-flight: sending never binds 53317, so a running
# receiver must not block it.
if [ "$mode" = "clipboard" ]; then
    text=""
    if command -v xclip >/dev/null 2>&1; then
        text=$(xclip -selection clipboard -o 2>/dev/null || true)
    fi
    if [ -z "$text" ] && [ -n "${DISPLAY:-}" ] && command -v zenity >/dev/null 2>&1; then
        text=$(zenity --entry --width=520 \
            --title="LocalSend — send text" \
            --text="The clipboard is empty. Type or paste the text to send:" 2>/dev/null || true)
    fi
    if [ -z "$text" ]; then
        echo
        echo "  Nothing to send: the clipboard is empty and no text was entered."
        echo "  Copy some text first, or send inline:  localsend-cli send-text \"hello\""
        echo
        [ -t 0 ] && { printf "  Press Enter to close. "; read -r _ || true; }
        exit 1
    fi
    printf '\n  Text to send (%s characters):\n\n' "${#text}"
    printf '%s\n\n' "$text" | sed 's/^/    /'
    printf '  Send this?  [Y]es / [e]dit in editor / [n]o: '
    read -r ans || ans=n
    case "$ans" in
        e|E)
            tmp=$(mktemp)
            printf '%s\n' "$text" > "$tmp"
            "${EDITOR:-nano}" "$tmp"
            text=$(cat "$tmp")
            rm -f "$tmp"
            [ -z "$text" ] && { echo "  Empty after editing — nothing sent."; exit 1; }
            ;;
        n|N) echo "  Nothing sent."; exit 0 ;;
    esac
    # Recipient selection happens in the CLI's own picker.
    exec localsend-cli send-text "$text"
fi
# --------------------------------------------------------------------------------

OUT="${LOCALSEND_OUTPUT_DIR:-$HOME/Downloads/localsend-cli}"

# ---- pre-flight: fail loudly and usefully, never with a raw bind error ----------
# Port-aware: a second instance on a different --port is fine, so only the port
# actually being used is treated as a conflict.
port=53317
for a in "$@"; do
    case "$a" in
        --port=*) port="${a#--port=}" ;;
        --port)   ;;
    esac
done

port_busy() {
    command -v ss >/dev/null 2>&1 || return 1
    ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
}

if port_busy; then
    echo
    if pgrep -x localsend-cli >/dev/null 2>&1; then
        pids=$(pgrep -x localsend-cli | tr '\n' ' ')
        echo "  Another LocalSend is already running (pid ${pids% }) and holds port ${port}."
        echo
        echo "    * if that is the LocalSend dashboard window, use its own Receive /"
        echo "      Quick Save actions, or close it first;"
        echo "    * if it is an earlier receive window, close that one."
    else
        echo "  Port ${port} is in use by something that is not localsend-cli."
        echo "  Find it with:  sudo ss -lntp | grep ${port}"
    fi
    echo
    echo "  Alternatively run this on a different port:  $(basename "$0") --port=53318"
    echo
    [ -t 0 ] && { printf "  Press Enter to close. "; read -r _ || true; }
    exit 1
fi
# --------------------------------------------------------------------------------

if [ "$mode" = "receive" ]; then
    echo
    echo "  LocalSend receive mode."
    echo "  Incoming transfers ask for approval; answer 'accept and pair' to stop"
    echo "  that device asking again. Files land in: $OUT"
    echo
    # Flags go BEFORE the subcommand: Go's flag package stops at the first
    # positional token, and although the wrapper's binary reorders argv, passing
    # them in the documented order keeps this predictable with any build.
    exec localsend-cli --output-dir "$OUT" "$@" receive
fi

# ---- quicksave: the dangerous one, behind a typed gate -------------------------
if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "localsend-cli-quicksave: run this in a terminal." >&2
    echo "It requires a typed confirmation before enabling auto-accept;" >&2
    echo "a non-interactive caller must use: localsend-cli --quick-save receive" >&2
    exit 1
fi

if [ -t 1 ]; then
    RED=$'\033[1;31m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
    RED=""; BOLD=""; DIM=""; OFF=""
fi

clear 2>/dev/null || true
printf '%s' "$RED"
cat <<'BANNER'
  ┌──────────────────────────────────────────────────────────────────────┐
  │   D A N G E R   —   A U T O - A C C E P T   R E C E I V E   M O D E   │
  └──────────────────────────────────────────────────────────────────────┘
BANNER
printf '%s' "$OFF"
cat <<EOF

  This starts LocalSend in ${BOLD}--quick-save${OFF} mode: ${BOLD}incoming transfers are
  accepted and written to disk without asking you anything.${OFF}

  Why that is dangerous:

    * Nothing prompts you. Anything sent while this window is open is
      written to ${BOLD}$OUT${OFF} without you seeing it first.

    * There is no authentication beyond being on the same network. On
      café / hotel / office / guest Wi-Fi, ${BOLD}any device that can reach
      this machine can push files at it${OFF} — no approval, no name, no
      warning.

    * Received files are untrusted input by definition. Auto-accept is
      how a file you never agreed to receive ends up on your disk to be
      opened later.

    * Disk fill: it cannot warn you, so it will happily write until the
      disk is full.

  ${BOLD}Safer alternative that usually does what people actually want:${OFF}
  use the "LocalSend (receive)" entry and answer ${BOLD}"accept and pair"${OFF}
  once per device. That device then stops asking, and every other device
  still needs your approval.

  ${DIM}This window is the switch. Closing it (Ctrl-C, or closing the
  terminal) turns auto-accept off again. Nothing is saved: the next
  launch is back to the safe default.${OFF}

EOF

printf '%s' "$RED"
printf '  To continue, type the word  danger  and press Enter: '
printf '%s' "$OFF"
read -r answer || exit 1

case "$answer" in
    danger|DANGER|Danger)
        ;;
    *)
        echo
        echo "  Not confirmed — nothing was started. That is the safe outcome."
        sleep 2
        exit 0
        ;;
esac

echo
printf '%s  Auto-accept is ON. Output directory: %s%s\n' "$RED" "$OUT" "$OFF"
echo "  Every transfer from any device on this network will be accepted silently."
echo "  Press Ctrl-C (or close the window) to stop — that re-arms the safety."
echo
exec localsend-cli --quick-save --output-dir "$OUT" "$@" receive
